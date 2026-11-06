# sercmd.ps1 - send one command to the camera serial console and print the output
# Usage : .\sercmd.ps1 -Cmd "uname -a" [-Wait 3] [-Com COM4]
param(
    [Parameter(Mandatory=$true)][string]$Cmd,
    [double]$Wait = 3,
    [string]$Com = "COM4",
    [int]$Baud = 115200
)
$p = New-Object System.IO.Ports.SerialPort $Com, $Baud, ([System.IO.Ports.Parity]::None), 8, ([System.IO.Ports.StopBits]::One)
$p.Handshake = [System.IO.Ports.Handshake]::None
$p.DtrEnable = $false
$p.RtsEnable = $false
$p.ReadTimeout = 100
$p.Encoding = [System.Text.Encoding]::UTF8
$p.Open()
try {
    $null = $p.ReadExisting()
    $p.Write("`r")
    Start-Sleep -Milliseconds 200
    $null = $p.ReadExisting()
    $p.Write($Cmd + "`r")
    $sb = New-Object System.Text.StringBuilder
    $end = (Get-Date).AddSeconds($Wait)
    while ((Get-Date) -lt $end) {
        Start-Sleep -Milliseconds 100
        try { [void]$sb.Append($p.ReadExisting()) } catch {}
    }
    $out = $sb.ToString() -replace "`r", ""
    # drop the stock cloud app log lines
    ($out -split "`n" | Where-Object { $_ -notmatch '^\[(1970|0:00)' }) -join "`n"
}
finally { $p.Close() }
