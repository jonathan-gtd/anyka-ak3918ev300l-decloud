import sys
# Add a JPEG snapshot thread to ak_rtsp_stream.c: a third (JPEG) encoder bound to the main VI channel at
# SNAP_FPS frames/s, written atomically to SNAP_PATH (default /tmp/www/snapshot.jpg). SNAP=0 disables it.
p = sys.argv[1]
s = open(p, encoding='latin-1').read()

func = r'''
/* ---- JPEG snapshot (added by anyka-ak3918ev300l-decloud) ---- */
static void *snapshot_th(void *arg)
{
    const char *path = getenv("SNAP_PATH") ? getenv("SNAP_PATH") : "/tmp/www/snapshot.jpg";
    int fps = getenv("SNAP_FPS") ? atoi(getenv("SNAP_FPS")) : 1;
    char tmp[256];
    struct venc_param p;
    struct venc_rc_param rc;
    int h = -1;
    (void)arg;
    if (fps < 1) fps = 1;
    snprintf(tmp, sizeof(tmp), "%s.tmp", path);
    ak_thread_set_name("snapshot_th");

    memset(&p, 0, sizeof(p));
    memset(&rc, 0, sizeof(rc));
    p.width  = rtsp_param.venc_info[0][0].ve_param.width;
    p.height = rtsp_param.venc_info[0][0].ve_param.height;
    p.fps = fps;
    p.goplen = 1;
    p.target_kbps = 4096;
    p.max_kbps = 4096;
    p.br_mode = BR_MODE_CBR;
    p.minqp = 20;
    p.maxqp = 48;
    p.initqp = 50;
    p.jpeg_qlevel = JPEG_QLEVEL_DEFAULT;
    p.chroma_mode = CHROMA_4_2_0;
    p.max_picture_size = 0;
    p.enc_level = 30;
    p.smart_mode = 0;
    p.smart_goplen = 100;
    p.smart_quality = 50;
    p.enc_out_type = MJPEG_ENC_TYPE;
    p.profile = PROFILE_JPEG;
    rc.enable_MMA = 1;
    if (ak_venc_open_ex(&p, &rc, &h) || h < 0) {
        printf("SNAPSHOT: jpeg encoder open failed\n");
        return NULL;
    }

    APP_CHN_S S, D;
    APP_BIND_PARAM bp;
    S.mid = MODULE_ID_VI;   S.oid = VIDEO_CHN0;
    D.mid = MODULE_ID_VENC; D.oid = h;
    bp.frame_rate = fps;
    bp.frame_depth = 2;
    bp.mode = USER_ENCODE_MODE;
    if (ak_app_video_bind_chn(&S, &D, &bp) != AK_SUCCESS) {
        printf("SNAPSHOT: bind to VI chn0 failed\n");
        ak_venc_close(h);
        return NULL;
    }
    ak_app_video_set_dst_chn_active(&D, AK_TRUE);
    printf("SNAPSHOT: %dx%d jpeg, %d fps -> %s\n", p.width, p.height, fps, path);

    struct video_stream *st = ak_mem_alloc(MODULE_ID_APP, sizeof(struct video_stream));
    while (st) {
        if (ak_app_video_venc_get_stream(&D, st) == AK_SUCCESS) {
            if (st->len > 0) {
                FILE *f = fopen(tmp, "wb");
                if (f) {
                    fwrite(st->data, 1, st->len, f);
                    fclose(f);
                    rename(tmp, path);
                }
            }
            ak_venc_release_stream(h, st);
        } else {
            ak_sleep_ms(100);
        }
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
    '    if (!getenv("SNAP") || atoi(getenv("SNAP")) != 0) {\n'
    '        ak_pthread_t snap_tid;\n'
    '        ak_thread_create(&snap_tid, snapshot_th, NULL, ANYKA_THREAD_MIN_STACK_SIZE, 19);\n'
    '    }\n', 1)

open(p, 'w', encoding='latin-1').write(s)
print("patch snapshot OK")
