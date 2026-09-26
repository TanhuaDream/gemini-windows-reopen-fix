param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'

function Get-Sha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$installRoot = Join-Path $env:LOCALAPPDATA 'Google\Gemini'
$versionDir = Get-ChildItem -LiteralPath $installRoot -Directory |
    Where-Object { $_.Name -match '^app-\d+\.\d+\.\d+$' } |
    Sort-Object { [version]$_.Name.Substring(4) } -Descending | Select-Object -First 1
if (!$versionDir) { throw '没有找到 Gemini 客户端。' }
$signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $versionDir.FullName 'Gemini.exe')
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Google LLC') {
    throw '程序签名与已确认的 Google Gemini 不一致，未做修改。'
}
$package = Join-Path $versionDir.FullName 'resources\app.asar'
$bytes = [IO.File]::ReadAllBytes($package)
$headerSize = [BitConverter]::ToInt32($bytes,4)
$jsonSize = [BitConverter]::ToInt32($bytes,12)
if ($jsonSize -le 0 -or $jsonSize -gt $bytes.Length - 16) { throw '程序包格式未知，未做修改。' }
$headerText = [Text.Encoding]::UTF8.GetString($bytes,16,$jsonSize)
$header = $headerText | ConvertFrom-Json
$entry = $header.files.src.files.'main.js'
$start = 8 + $headerSize + [int]$entry.offset
$size = [int]$entry.size
if ($size -le 0 -or $start -lt 0 -or $start + $size -gt $bytes.Length) { throw '主程序位置未知，未做修改。' }
$mainBytes = New-Object byte[] $size
[Array]::Copy($bytes,$start,$mainBytes,0,$size)
$digest = Get-Sha256 $mainBytes
if ($digest -ne $entry.integrity.hash -or $entry.integrity.blocks.Count -ne 1 -or $entry.integrity.blocks[0] -ne $digest) {
    throw '程序包校验失败，未做修改。'
}
$knownOriginal = 'c212c4d025dcff40209f80d48d9a8f11e87748b4024980f5443bf99c0015dd2c'
$knownFixed = '67af484760f62b23a67bed3db4a689d143638127af94accf721717366dcff309'
if ($digest -eq $knownFixed) { Write-Output ('Gemini {0} 已包含此修复。' -f $versionDir.Name.Substring(4)); return }
if ($digest -ne $knownOriginal) { throw '新版程序代码已变化，无法确认适用性，未做修改。请重新检查问题。' }
$before = 'if(c)return;if(s.preventDefault(),c=!0,u.info("main","Application will quit; cleaning up helper IPC"),Kr(),!V("diagnosticConsent",!1)){g.app.quit();return}'
$after = $before.Replace('g.app.quit()','g.app.exit()')
$mainText = [Text.Encoding]::UTF8.GetString($mainBytes)
if ([regex]::Matches($mainText,[regex]::Escape($before)).Count -ne 1) { throw '目标退出代码不匹配，未做修改。' }
if ($CheckOnly) { Write-Output ('Gemini {0} 包含已确认的退出问题，适用此修复。' -f $versionDir.Name.Substring(4)); return }

$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -like 'Gemini*' -and $_.Path -and
    [IO.Path]::GetDirectoryName($_.Path) -eq $versionDir.FullName
})
if ($running.Count) {
    $geminiMain = @($running | Where-Object { $_.ProcessName -eq 'Gemini' })
    $logPath = Join-Path $installRoot 'logs\gemini.log'
    $lastLifecycle = Select-String -LiteralPath $logPath -Pattern 'Creating primary application window|Application will quit; cleaning up helper IPC' | Select-Object -Last 1
    if (@($geminiMain | Where-Object { $_.MainWindowHandle -ne 0 }).Count -or !$lastLifecycle -or
        $lastLifecycle.Line -notmatch 'Application will quit; cleaning up helper IPC') {
        throw 'Gemini 正在使用中。请先关闭 Gemini 窗口，再运行修复工具。'
    }
    $running | Stop-Process -Force
    Start-Sleep -Seconds 2
}
$backupDir = Join-Path $PSScriptRoot 'backups'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$packageHash = Get-Sha256 $bytes
$backupPath = Join-Path $backupDir ($versionDir.Name + '-' + $packageHash + '.original.asar')
if (Test-Path -LiteralPath $backupPath) {
    if ((Get-Sha256 ([IO.File]::ReadAllBytes($backupPath))) -ne $packageHash) { throw '已有备份校验失败，未做修改。' }
} else { [IO.File]::WriteAllBytes($backupPath,$bytes) }
$updatedMain = [Text.Encoding]::UTF8.GetBytes($mainText.Replace($before,$after))
if ($updatedMain.Length -ne $size -or (Get-Sha256 $updatedMain) -ne $knownFixed) { throw '修复结果不匹配，未做修改。' }
if ([regex]::Matches($headerText,$digest).Count -ne 2) { throw '程序包校验字段未知，未做修改。' }
$updatedHeader = [Text.Encoding]::UTF8.GetBytes($headerText.Replace($digest,$knownFixed))
if ($updatedHeader.Length -ne $jsonSize) { throw '程序包头长度变化，未做修改。' }
[Array]::Copy($updatedHeader,0,$bytes,16,$jsonSize)
[Array]::Copy($updatedMain,0,$bytes,$start,$size)
$tempPath = $package + '.codex-repair-tmp'
try {
    [IO.File]::WriteAllBytes($tempPath,$bytes)
    if ((Get-Sha256 ([IO.File]::ReadAllBytes($tempPath))) -ne (Get-Sha256 $bytes)) { throw '临时文件校验失败。' }
    if ((Get-Sha256 ([IO.File]::ReadAllBytes($package))) -ne $packageHash) { throw '客户端更新了程序包，已停止，未覆盖新版。' }
    Move-Item -LiteralPath $tempPath -Destination $package -Force
} finally { if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath } }
Write-Output ('Gemini {0} 退出流程修复已写入。请重新打开 Gemini。' -f $versionDir.Name.Substring(4))
Write-Output ('原始程序包备份：' + $backupPath)
