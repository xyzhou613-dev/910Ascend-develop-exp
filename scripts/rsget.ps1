param(
    [Parameter(Mandatory = $true)][string]$Remote,
    [string]$Out = '',
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
    $fs = New-Object System.IO.FileStream($Out, [System.IO.FileMode]::Create)
    try { $sftp.DownloadFile($Remote, $fs) } finally { $fs.Dispose() }
    $sftp.Disconnect(); $sftp.Dispose()
    [Console]::Out.WriteLine("GOT $Remote -> $Out ($((Get-Item $Out).Length) B)")
}
finally { $ssh.Disconnect(); $ssh.Dispose() }
