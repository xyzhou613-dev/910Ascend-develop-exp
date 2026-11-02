param(
    [Parameter(Mandatory = $true)][string]$Command,
    [int]$TimeoutSec = 180
)
# Quick wrapper: run a bash snippet on the 910B4 box (<HOST_910>) via rs.ps1.
$ErrorActionPreference = 'Stop'
$tmp = Join-Path $env:TEMP ('r206_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.sh')
[System.IO.File]::WriteAllText($tmp, $Command, (New-Object System.Text.UTF8Encoding($false)))
try {
    & 'D:\Ascend learning\backend\remote\rs.ps1' -ScriptPath $tmp -TimeoutSec $TimeoutSec
}
finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
