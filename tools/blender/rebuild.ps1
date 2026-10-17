param([string]$Blender='B:\Blender\blender.exe',[string[]]$Ids=@(),[switch]$BuildSources,[string]$ReferenceRoot='B:\Critterweight-art\tmp\baseline-rebuild')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$lockTemp=[Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','User'))
if (-not $lockTemp) { $lockTemp=[Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','Machine')) }
. (Join-Path $PSScriptRoot 'art_env.ps1')
Set-ArtRuntimePaths
$diskStart=(Get-PSDrive C).Free
$lock=$null
try {
  while ($null -eq $lock) {
    try { $lock=[IO.File]::Open((Join-Path $lockTemp 'critterweight_full_suite.lock'),'OpenOrCreate','ReadWrite','None') }
    catch { Write-Output 'Waiting for the shared full-suite lock before Blender'; Start-Sleep -Seconds 15 }
  }
  if (-not $Ids.Count) { $Ids=@(Get-Content -Raw (Join-Path $PSScriptRoot 'adopted.json') | ConvertFrom-Json) }
  foreach ($id in $Ids) {
    $log=Join-Path (Split-Path $repo -Parent) "captures\$id-build.log"
    if ($BuildSources) {
      & $Blender -b -t 2 --python-exit-code 1 --python (Join-Path $PSScriptRoot 'build_creatures.py') -- $id --reference-root $ReferenceRoot *> $log
    } else {
      & $Blender -b (Join-Path $PSScriptRoot "$id.blend") -t 2 --python-exit-code 1 --python (Join-Path $PSScriptRoot 'export_creature.py') -- --out (Join-Path $repo "game\assets\models\creatures\$id.glb") --scratch (Join-Path (Split-Path $repo -Parent) 'tmp') *> $log
    }
    if ($LASTEXITCODE -ne 0) { Get-Content -LiteralPath $log | Select-Object -Last 15; throw "Blender failed for $id" }
    Select-String -LiteralPath $log -Pattern 'triangles' | ForEach-Object {$_.Line}
    $diskNow=(Get-PSDrive C).Free
    Write-Output ("C free bytes: $diskNow")
    if ($diskStart-$diskNow -gt 200MB) { throw 'C: lost over 200 MB during this job; inspect before continuing' }
  }
} finally { if ($null -ne $lock) {$lock.Close()} }
