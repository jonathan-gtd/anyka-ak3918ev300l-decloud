# camup.ps1 - DEV/LIVE MODE: from a stock boot, log in over serial, kill the cloud app, take over the watchdog,
# join Wi-Fi and start the RTSP server from RAM (nothing is written to flash). serlog.ps1 must be running.
# Needs an HTTP server on your LAN serving wdkeep, notso, up.sh, rtspd, librtsp_server.so (see dev/up.sh).
# Usage: .\camup.ps1 -Ssid MySSID -Psk 'MyPassword' -Srv http://192.168.1.10:8088 [-K0 1536] [-K1 300] [-F 15]
param(
    [Parameter(Mandatory=$true)][string]$Ssid,
    [Parameter(Mandatory=$true)][string]$Psk,
    [Parameter(Mandatory=$true)][string]$Srv,
    [int]$K0 = 1536, [int]$K1 = 300, [int]$F = 15
)
$d = Split-Path -Parent $MyInvocation.MyCommand.Path
$sq = Join-Path $d "sq.ps1"
function Q($cmds, $wait) { & $sq -Cmds $cmds -Wait $wait }

# 1) login (stock rootfs patched with an empty root password)
$o = Q @('^C', '', '#sleep 1500', 'root', '#sleep 1500', 'echo LOGIN_OK') 5
if ($o -notmatch 'LOGIN_OK') { $o = Q @('', '#sleep 2500', 'root', '#sleep 1500', 'echo LOGIN_OK') 5 }
if ($o -notmatch 'LOGIN_OK') { Write-Host "login FAILED"; exit 1 }
Write-Host "login OK"

# 2) kill the cloud (daemon owns /dev/watchdog and reboots if ipc dies) + shell feeder as a bridge + Wi-Fi
$bs = @(
 'killall -9 daemon',
 '( while :; do echo 1 > /dev/watchdog 2>/dev/null; sleep 1; done ) &',
 '#sleep 800',
 'killall -9 ipc',
 'echo 0 > /proc/sys/kernel/panic_on_oops; echo 4 > /proc/sys/kernel/printk',
 "echo 'ctrl_interface=/var/run/wpa_supplicant' > /tmp/w.conf",
 "echo 'network={' >> /tmp/w.conf",
 "echo ' ssid=""$Ssid""' >> /tmp/w.conf",
 "echo ' psk=""$Psk""' >> /tmp/w.conf",
 "echo ' key_mgmt=WPA-PSK' >> /tmp/w.conf",
 "echo ' scan_ssid=1' >> /tmp/w.conf",
 "echo '}' >> /tmp/w.conf",
 'ifconfig wlan0 up; mkdir -p /var/run/wpa_supplicant',
 '/app/bin/wpa_supplicant -Dnl80211 -i wlan0 -c /tmp/w.conf -B -P /tmp/w.pid',
 '#sleep 9000',
 'udhcpc -i wlan0 -s /usr/share/udhcpc/default.script -b',
 '#sleep 5000',
 "ifconfig wlan0 | grep 'inet addr' && echo WIFI_OK"
)
$o = Q $bs 24
if ($o -notmatch 'WIFI_OK') {
    $o = Q @('#sleep 6000', "ifconfig wlan0 | grep 'inet addr' && echo WIFI_OK") 9
    if ($o -notmatch 'WIFI_OK') { Write-Host "Wi-Fi FAILED"; exit 1 }
}
Write-Host "Wi-Fi OK"

# 3) wdkeep replaces the shell feeder, offloads off, RTSP server
$o = Q @(
 "wget -q -O /tmp/wdkeep $Srv/wdkeep && chmod +x /tmp/wdkeep && kill %1 2>/dev/null; /tmp/wdkeep 60",
 '#sleep 1000',
 'cat /tmp/wdkeep.log',
 "wget -q -O /tmp/notso $Srv/notso && chmod +x /tmp/notso && /tmp/notso wlan0",
 "wget -q -O /tmp/up.sh $Srv/up.sh && SRV=$Srv K0=$K0 K1=$K1 F=$F sh /tmp/up.sh"
) 16
($o -split "`n") | Where-Object { $_ -match 'wdkeep:|notso|UP_DONE' } | ForEach-Object { Write-Host $_ }
