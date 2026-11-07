import sys
# Add an automatic day/night thread to ak_rtsp_stream.c.
# Day/night is decided from the ISP luminance index (ak_vpss_get_cur_lumi, high = dark) with a wide
# hysteresis (DN_D2N / DN_N2D) and a 30 s minimum per state. At night, every DN_PROBE s (300) the IR LEDs are
# switched off for ~2.5 s to check whether it is really daylight. On a switch: IR-cut pulse (GPIO 17/18), IR LEDs (GPIO 56),
# ISP day/night profile (ak_vi_switch_mode). Mode: /tmp/daynight.mode = auto | day | night (default auto).
# State in /tmp/daynight.state, luminance trace in /tmp/daynight.log. DN=0 in the environment disables it.
p = sys.argv[1]
s = open(p, encoding='latin-1').read()

func = r'''
/* ---- automatic day/night (added by anyka-ak3918ev300l-decloud) ---- */
struct dn_threshold {             /* = struct ak_auto_day_night_threshold of the vendor SDK */
    int day_to_night_lum, night_to_day_lum;
    int night_cnt[5], day_cnt[10];
    int lock_time, quick_switch_mode, day2night_sleep_time, night2day_sleep_time;
};
int ak_vpss_set_auto_day_night_param(int dev, void *param);
int ak_vpss_get_auto_day_night_level(int dev, int pre_ir_level, int *new_ir_level);
int ak_vpss_get_cur_lumi(int dev, int *lumi);

#define DN_IRCUT_NIGHT 17   /* pulse = filter out (night) */
#define DN_IRCUT_DAY   18   /* pulse = filter in (day) */
#define DN_IR_LED      56   /* 1 = IR LEDs on */

static void dn_write(const char *path, const char *val)
{
    FILE *f = fopen(path, "w");
    if (f) { fputs(val, f); fclose(f); }
}
static void dn_gpio(int g, int v)
{
    char p[64];
    snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/value", g);
    dn_write(p, v ? "1" : "0");
}
static void dn_gpio_out(int g)
{
    char p[64], n[8];
    snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d", g);
    if (access(p, F_OK) != 0) { snprintf(n, sizeof(n), "%d", g); dn_write("/sys/class/gpio/export", n); }
    snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/direction", g);
    dn_write(p, "low");
}
static void dn_apply(int night)
{
    if (night) {
        ak_vi_switch_mode(VIDEO_DEV0, VI_MODE_NIGHTTIME);
        dn_gpio(DN_IR_LED, 1);
        dn_gpio(DN_IRCUT_DAY, 0); dn_gpio(DN_IRCUT_NIGHT, 1);
        ak_sleep_ms(150);
        dn_gpio(DN_IRCUT_NIGHT, 0);
    } else {
        dn_gpio(DN_IRCUT_NIGHT, 0); dn_gpio(DN_IRCUT_DAY, 1);
        ak_sleep_ms(150);
        dn_gpio(DN_IRCUT_DAY, 0);
        dn_gpio(DN_IR_LED, 0);
        ak_vi_switch_mode(VIDEO_DEV0, VI_MODE_DAY_OUTDOOR);
    }
    dn_write("/tmp/daynight.state", night ? "night\n" : "day\n");
    printf("DAYNIGHT: -> %s\n", night ? "night" : "day");
}
static void *daynight_th(void *arg)
{
    (void)arg;
    ak_thread_set_name("daynight_th");
    dn_gpio_out(DN_IRCUT_NIGHT); dn_gpio_out(DN_IRCUT_DAY); dn_gpio_out(DN_IR_LED);

    struct dn_threshold th;
    memset(&th, 0, sizeof(th));
    th.day_to_night_lum = getenv("DN_D2N") ? atoi(getenv("DN_D2N")) : 3584;
    th.night_to_day_lum = getenv("DN_N2D") ? atoi(getenv("DN_N2D")) : 1536;
    th.lock_time = 60000;
    for (int i = 0; i < 5; i++)  th.night_cnt[i] = 15000;
    for (int i = 0; i < 10; i++) th.day_cnt[i] = 300000;
    int r = ak_vpss_set_auto_day_night_param(VIDEO_DEV0, &th);
    printf("DAYNIGHT: thresholds d2n=%d n2d=%d (ret %d)\n", th.day_to_night_lum, th.night_to_day_lum, r);

    int cur = -1, cand = -1, cnt = 0, tick = 0, last_sw = -1000;
    int d2n = th.day_to_night_lum, n2d = th.night_to_day_lum;
    int probe = getenv("DN_PROBE") ? atoi(getenv("DN_PROBE")) : 300, last_probe = 0;
    ak_sleep_ms(5000);                /* let the AE settle before the first decision */
    for (;;) {
        char mode[16] = "auto";
        FILE *f = fopen("/tmp/daynight.mode", "r");
        if (f) { if (!fgets(mode, sizeof(mode), f)) strcpy(mode, "auto"); fclose(f); }
        int want, need;
        if (!strncmp(mode, "day", 3))        { want = 0; need = 1; }
        else if (!strncmp(mode, "night", 5)) { want = 1; need = 1; }
        else {
            /* own rule on the ISP luminance index (the vendor auto level does not switch with these libs):
             * high index = dark scene. Wide hysteresis so the IR LEDs do not bounce us back to day. */
            int lumi = -1;
            ak_vpss_get_cur_lumi(VIDEO_DEV0, &lumi);
            want = cur < 0 ? (lumi > d2n) : cur;
            if (cur == 0 && lumi > d2n) want = 1;
            /* At night the IR LEDs light the scene, so the luminance alone cannot tell "lit by IR" from
             * "daylight". Every PROBE seconds: IR LEDs off for ~2.5 s, measure, IR back on. */
            if (cur == 1 && tick - last_probe >= probe && tick - last_sw >= 30) {
                last_probe = tick;
                dn_gpio(DN_IR_LED, 0);
                ak_sleep_ms(2500);
                int l2 = -1;
                ak_vpss_get_cur_lumi(VIDEO_DEV0, &l2);
                printf("DAYNIGHT: probe without IR, lumi=%d (day if < %d)\n", l2, n2d);
                if (l2 >= 0 && l2 < n2d) { dn_apply(0); cur = 0; cand = 0; cnt = 0; last_sw = tick; want = 0; }
                else dn_gpio(DN_IR_LED, 1);
            }
            need = cur < 0 ? 1 : 3;           /* 3 consecutive seconds before switching */
            if (cur >= 0 && want != cur && tick - last_sw < 30) want = cur;   /* minimum 30 s per state */
        }
        if (want != cur) {
            cnt = (want == cand) ? cnt + 1 : 1;
            cand = want;
            if (cnt >= need) { dn_apply(want); cur = want; cnt = 0; last_sw = tick; }
        } else {
            cnt = 0;
        }
        if (++tick % 2 == 0) {
            int lumi = -1;
            ak_vpss_get_cur_lumi(VIDEO_DEV0, &lumi);
            char line[96];
            snprintf(line, sizeof(line), "mode=%s state=%s lumi=%d\n", strtok(mode, "\r\n") ? mode : "auto",
                     cur ? "night" : "day", lumi);
            dn_write("/tmp/daynight.log", line);
        }
        ak_sleep_ms(1000);
    }
    return NULL;
}
'''

anchor_main = 'int main(int argc, char **argv)'
assert s.count(anchor_main) == 1, ("main", s.count(anchor_main))
s = s.replace(anchor_main, func + '\n' + anchor_main, 1)

anchor_start = '    signal (SIGPIPE, SIG_IGN);\n'
assert s.count(anchor_start) == 1, ("sigpipe", s.count(anchor_start))
s = s.replace(anchor_start, anchor_start +
    '    if (!getenv("DN") || atoi(getenv("DN")) != 0) {\n'
    '        ak_pthread_t dn_tid;\n'
    '        ak_thread_create(&dn_tid, daynight_th, NULL, ANYKA_THREAD_MIN_STACK_SIZE, 19);\n'
    '    }\n', 1)

open(p, 'w', encoding='latin-1').write(s)
print("patch daynight OK")
