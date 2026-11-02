param(
    [Parameter(Mandatory = $true)][string]$Command,
    [int]$TimeoutSec = 180
)
# 在 <HOST_GPU>（RTX PRO 6000）上执行 bash 片段。
$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:TEMP ('r201_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.sh')
[System.IO.File]::WriteAllText($tmp, $Command, (New-Object System.Text.UTF8Encoding($false)))
try {
    & 'D:\Ascend learning\backend\remote\rs.ps1' -ScriptPath $tmp -TimeoutSec $TimeoutSec `
        -HostIP '<HOST_GPU>' -User 'server' -Pass '<PASSWORD>'
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
