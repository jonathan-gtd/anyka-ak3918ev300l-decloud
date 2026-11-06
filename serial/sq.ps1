# sq.ps1 - queue commands for serlog.ps1, then print the new console output
# Usage : .\sq.ps1 -Cmds 'cmd1','cmd2' [-Wait 4]
param([string[]]$Cmds, [double]$Wait = 3)
$dir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$log   = Join-Path $dir "serial.log"
$queue = Join-Path $dir "cmdqueue.txt"
$start = 0; if (Test-Path $log) { $start = (Get-Item $log).Length }
[System.IO.File]::WriteAllLines($queue, $Cmds, (New-Object System.Text.UTF8Encoding($false)))
Start-Sleep -Seconds $Wait
$fs = [System.IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
try {
    $null = $fs.Seek($start, 'Begin')
    $sr = New-Object System.IO.StreamReader($fs)
    ($sr.ReadToEnd() -replace "`r", "")
} finally { $fs.Close() }
