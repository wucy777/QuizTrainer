<#
.SYNOPSIS
  把 QuizTrainer 的 Flutter Windows 产物打成单文件 exe（自解压）。

.DESCRIPTION
  流程：
    1. csc 编译 launcher.cs（窗口程序）与 packer.cs（控制台程序）
    2. packer 把 Release 文件夹压成 payload.bin（Deflate）
    3. 合成：launcher.exe + payload + [Int64 长度][QDRILLPK]

  运行时启动器把载荷解压到 %TEMP%\QuizTrainer_<PID>，程序退出后自动删除。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File packaging/build_single_exe.ps1
  # 或在 PowerShell 里直接： .\packaging\build_single_exe.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root       = Split-Path -Parent $Here
$FlutterRel = Join-Path $Root 'flutter_app\build\windows\x64\runner\Release'
$OutDir     = Join-Path $Root 'output'
$Build      = Join-Path $Here '_build'
$Stage      = Join-Path $Build 'stage'
$OutExe     = Join-Path $OutDir 'QuizTrainer_单文件版.exe'
$Payload    = Join-Path $Build 'payload.bin'
$Magic      = 'QDRILLPK'

function Find-Csc {
  $candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe'),
    (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
  )
  foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
  throw '找不到 csc.exe（需要 .NET Framework 或 Visual Studio 生成工具）'
}

$Csc = Find-Csc
Write-Host "csc: $Csc"

if (-not (Test-Path -LiteralPath $FlutterRel)) {
  throw "找不到 Flutter 产物目录：$FlutterRel`n请先运行：cd flutter_app; flutter build windows --release"
}

# ── 1. 暂存：复制产物并把 exe 改名 ──
if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
New-Item -ItemType Directory -Path $Stage -Force | Out-Null
Copy-Item -Path (Join-Path $FlutterRel '*') -Destination $Stage -Recurse -Force

$srcExe = Join-Path $Stage 'quiz_trainer.exe'
if (Test-Path -LiteralPath $srcExe) {
  Move-Item -LiteralPath $srcExe -Destination (Join-Path $Stage 'QuizTrainer.exe') -Force
} elseif (-not (Test-Path -LiteralPath (Join-Path $Stage 'QuizTrainer.exe'))) {
  throw "暂存目录里找不到 quiz_trainer.exe"
}
$fileCount = (Get-ChildItem -LiteralPath $Stage -Recurse -File).Count
Write-Host "暂存完成：$fileCount 个文件"

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path $Build  -Force | Out-Null

# ── 2. 编译 ──
$LauncherExe = Join-Path $Build 'launcher.exe'
$PackerExe   = Join-Path $Build 'packer.exe'

& $Csc /nologo /target:winexe /optimize+ "/out:$LauncherExe" /reference:System.Windows.Forms.dll (Join-Path $Here 'launcher.cs')
if ($LASTEXITCODE -ne 0) { throw "编译 launcher.cs 失败" }
Write-Host '已编译 launcher.exe'

& $Csc /nologo /target:exe /optimize+ "/out:$PackerExe" (Join-Path $Here 'packer.cs')
if ($LASTEXITCODE -ne 0) { throw "编译 packer.cs 失败" }
Write-Host '已编译 packer.exe'

# ── 3. 打包载荷 ──
& $PackerExe $Stage $Payload
if ($LASTEXITCODE -ne 0) { throw "打包载荷失败" }

# ── 4. 合成单文件 ──
$launcher = [System.IO.File]::ReadAllBytes($LauncherExe)
$data     = [System.IO.File]::ReadAllBytes($Payload)
$lenBytes = [BitConverter]::GetBytes([Int64]$data.Length)
$magic    = [System.Text.Encoding]::ASCII.GetBytes($Magic)

$fs = [System.IO.File]::Create($OutExe)
try {
  $fs.Write($launcher, 0, $launcher.Length)
  $fs.Write($data, 0, $data.Length)
  $fs.Write($lenBytes, 0, $lenBytes.Length)
  $fs.Write($magic, 0, $magic.Length)
} finally { $fs.Dispose() }

$size = (Get-Item -LiteralPath $OutExe).Length
Write-Host ''
Write-Host "单文件 exe 生成：$OutExe"
Write-Host ("  启动器 {0} KB + 数据 {1} KB => 合计 {2:N1} MB" -f `
  ($launcher.Length / 1KB), ($data.Length / 1KB), ($size / 1MB))

# ── 5. 结构自检 ──
$all = [System.IO.File]::ReadAllBytes($OutExe)
$tailOk = $true
for ($i = 0; $i -lt 8; $i++) {
  if ($all[$all.Length - 8 + $i] -ne $magic[$i]) { $tailOk = $false; break }
}
if (-not $tailOk) { throw '尾部标记错误' }
$lenFromFile = [BitConverter]::ToInt64($all, $all.Length - 16)
if ($lenFromFile -ne $data.Length) { throw '长度字段不符' }
if ($all.Length -ne ($launcher.Length + $data.Length + 16)) { throw '文件大小不符' }
Write-Host '  结构自检通过'
