param(
    [Parameter(Mandatory = $true)][string]$Put,
    [Parameter(Mandatory = $true)][string]$Remote,
    [string]$HostIP = '<HOST_910>',
    [string]$User = 'root',
    [string]$Pass = '<PASSWORD>',
    [int]$Port = 22
)
$ErrorActionPreference = 'Stop'
$asm = 'C:\Users\Bjitec\AppData\Local\Temp\posh-ssh\extracted\Assembly'
[void][System.Reflection.Assembly]::LoadFrom((Join-Path $asm 'SshNet.Security.Cryptography.dll'))
[void][System.Reflection.Assembly]::LoadFrom((Join-Path $asm 'Renci.SshNet.dll'))

$ci = New-Object Renci.SshNet.PasswordConnectionInfo($HostIP, $Port, $User, $Pass)
$ci.Timeout = [TimeSpan]::FromSeconds(25)
$ssh = New-Object Renci.SshNet.SshClient($ci)
$ssh.Connect()
try {
    $sftp = New-Object Renci.SshNet.SftpClient($ci)
    $sftp.Connect()
    $items = if ((Get-Item $Put) -is [System.IO.DirectoryInfo]) { Get-ChildItem -Path $Put -Recurse -File } else { @(Get-Item $Put) }
    foreach ($i in $items) {
        $rel = if ((Get-Item $Put) -is [System.IO.DirectoryInfo]) { $i.FullName.Substring((Resolve-Path $Put).Path.Length).TrimStart('\','/') -replace '\\','/' } else { $i.Name }
        $tgt = if ((Get-Item $Put) -is [System.IO.DirectoryInfo]) { ($Remote.TrimEnd('/') + '/' + $rel) } else { $Remote }
        $dir = ($tgt -split '/')[0..(($tgt -split '/').Length - 2)] -join '/'
        try { $sftp.ChangeDirectory($dir) } catch {
            $parts = ($tgt -split '/')
            $acc = ''
            for ($k = 1; $k -lt $parts.Length - 1; $k++) {
                $acc += '/' + $parts[$k]
                try { $sftp.ChangeDirectory($acc) } catch { $sftp.CreateDirectory($acc) | Out-Null }
            }
        }
        $fs = [System.IO.File]::OpenRead($i.FullName)
        try { $sftp.UploadFile($fs, $tgt) } finally { $fs.Dispose() }
        [Console]::Out.WriteLine("PUT $($i.Name) -> $tgt ($($i.Length) B)")
    }
    $sftp.Disconnect()
    $sftp.Dispose()
}
finally { $ssh.Disconnect(); $ssh.Dispose() }
