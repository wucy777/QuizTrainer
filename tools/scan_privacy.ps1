<#
.SYNOPSIS
  开源前自检：扫描会被提交的源码，确认不含个人信息、绝对路径、旧项目名。

.DESCRIPTION
  跳过构建产物与本地临时目录（与 .gitignore 保持一致），
  只检查真正会进版本库的文本文件。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools/scan_privacy.ps1
#>
[CmdletBinding()]
param(
  [string]$Root
)

$ErrorActionPreference = 'Stop'

if (-not $Root) {
  # tools/ 的上一级就是项目根
  $Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
}
$Root = (Resolve-Path -LiteralPath $Root).Path

# 与 .gitignore 对应的跳过项
$SkipDirs = @(
  '\build\', '.dart_tool', 'ephemeral', '.gradle', '_cache', '_build',
  '_backup', '.idea', '__pycache__', '.cxx', '\output\', '.flutter-plugins'
)
$SkipExt = @('.png', '.jpg', '.jpeg', '.ico', '.so', '.dll', '.exe', '.zip',
             '.apk', '.pdf', '.otf', '.ttf', '.dat', '.bin', '.jar', '.pdb')

$Patterns = [ordered]@{
  '个人信息 / 私人用途' = '英语补考|补考|挂科|四级|CET-?4|LMYX|真题|Model Test|Further Listening|背答案'
  '本机绝对路径'       = '[A-Za-z]:[\\/]{1,2}(AAA|LMYX|Users)[\\/]'
  '旧项目名'           = 'QuizDrill|quiz_drill'
}

$files = Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object {
  $rel = $_.FullName.Substring($Root.Length)
  ($SkipExt -notcontains $_.Extension.ToLower()) -and
  ($rel -notlike '*scan_privacy.ps1*') -and          # 跳过本脚本自身（含匹配模式字面量）
  -not ($SkipDirs | Where-Object { $rel -like "*$_*" })
}

$scanned = 0
$total = 0
foreach ($name in $Patterns.Keys) {
  $rx = [regex]$Patterns[$name]
  $hits = @()
  foreach ($f in $files) {
    try { $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop }
    catch { continue }
    $m = $rx.Match($text)
    if ($m.Success) {
      $line = ($text.Substring(0, $m.Index) -split "`n").Count
      $hits += [pscustomobject]@{
        File  = $f.FullName.Substring($Root.Length)
        Line  = $line
        Match = $m.Value
      }
    }
  }
  Write-Host ("{0}：{1} 处" -f $name, $hits.Count)
  foreach ($h in $hits) { Write-Host ("   {0}:{1}  {2}" -f $h.File, $h.Line, $h.Match) }
  $total += $hits.Count
}
$scanned = $files.Count

Write-Host ''
Write-Host ("扫描 {0} 个文件，命中 {1} 处" -f $scanned, $total)
if ($total -gt 0) {
  Write-Host '>>> 仍有需要处理的地方'
  exit 1
}
Write-Host '>>> 源码干净，可以开源'
exit 0
