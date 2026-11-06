# serlog.ps1 - persistent serial relay: logs COM port to serial.log (with PC timestamps every 5 s)
# and sends the lines dropped into cmdqueue.txt (one command per line, "#sleep N" = wait N ms).
# Special line "^C" = send Ctrl-C.
param([string]$Com = "COM4", [int]$Baud = 115200)
$dir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$log   = Join-Path $dir "serial.log"
$queue = Join-Path $dir "cmdqueue.txt"
$p = New-Object System.IO.Ports.SerialPort $Com, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$p.Handshake = [System.IO.Ports.Handshake]::None
$p.DtrEnable = $false; $p.RtsEnable = $false
$p.ReadTimeout = 50
$p.Open()
$enc = New-Object System.Text.UTF8Encoding($false)
$nextMark = (Get-Date).AddSeconds(5)
try {
    while ($true) {
        try { $d = $p.ReadExisting() } catch { $d = "" }
        if ($d) { [System.IO.File]::AppendAllText($log, $d, $enc) }
        if ((Get-Date) -ge $nextMark) {
            [System.IO.File]::AppendAllText($log, "`n[PC " + (Get-Date -Format 'HH:mm:ss') + "]`n", $enc)
            $nextMark = (Get-Date).AddSeconds(5)
        }
        if (Test-Path $queue) {
            $lines = @()
            try { $lines = [System.IO.File]::ReadAllLines($queue); Remove-Item $queue -Force } catch {}
            foreach ($l in $lines) {
                if ($l -eq '^C') { $p.Write([byte[]](3), 0, 1) }
                elseif ($l -match '^#sleep (\d+)$') { Start-Sleep -Milliseconds ([int]$Matches[1]) }
                else { $p.Write($l + "`r") }
                Start-Sleep -Milliseconds 250
            }
        }
        Start-Sleep -Milliseconds 40
    }
} finally { $p.Close() }
