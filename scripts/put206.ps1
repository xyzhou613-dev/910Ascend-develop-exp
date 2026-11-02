param(
    [Parameter(Mandatory = $true)][string]$Local,
    [Parameter(Mandatory = $true)][string]$Remote,
    [int]$ChunkChars = 30000
)
# Upload a file to the 910B4 box in base64 chunks.
# rs.ps1 base64-wraps the *whole* bash script, so each SSH call must stay well under ~68 KB.
$ErrorActionPreference = 'Stop'
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Local))
$n = [math]::Ceiling($b64.Length / $ChunkChars)
$tag = [guid]::NewGuid().ToString('N').Substring(0, 8)
$width = ([string]($n - 1)).Length     # ★ 必须零填充：否则 cat /tmp/x_*.b64 会把 _10 排在 _2 前面
for ($i = 0; $i -lt $n; $i++) {
    $start = $i * $ChunkChars
    $len = [math]::Min($ChunkChars, $b64.Length - $start)
    $piece = $b64.Substring($start, $len)
    $cmd = "echo $piece > /tmp/${tag}_$($i.ToString().PadLeft($width, '0')).b64"
    & 'D:\Ascend learning\_work\r206.ps1' -Command $cmd -TimeoutSec 180 | Out-Null
}
$fin = "cat /tmp/${tag}_*.b64 | base64 -d > '$Remote'`nrm -f /tmp/${tag}_*.b64`nwc -c < '$Remote'"
$out = & 'D:\Ascend learning\_work\r206.ps1' -Command $fin -TimeoutSec 300
Write-Output "uploaded $Local -> $Remote  size=$($out -join '' | ForEach-Object { $_.Trim() })  chunks=$n"
