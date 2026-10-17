param([string]$ReferenceRoot='B:\Critterweight-art\tmp\baseline-rebuild')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$artRoot=Split-Path $repo -Parent
$snapshot=Join-Path $artRoot ('tmp\before-swap-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
$entries=Get-Content -Raw (Join-Path $PSScriptRoot 'model_manifest.json') | ConvertFrom-Json | Where-Object {$null -ne $_.creature}
foreach($entry in $entries){
 $model=Join-Path $repo ('game/assets/models/'+$entry.out)
 $original=Join-Path $ReferenceRoot $entry.out
 if(-not (Test-Path -LiteralPath $original)){throw "Missing original $original"}
 Copy-Item -LiteralPath $model -Destination (Join-Path $snapshot ($entry.id+'.glb'))
}
try {
 foreach($entry in $entries){Copy-Item -LiteralPath (Join-Path $ReferenceRoot $entry.out) -Destination (Join-Path $repo ('game/assets/models/'+$entry.out)) -Force}
 & (Join-Path $PSScriptRoot 'check_art.ps1') -ImportOnly
 & (Join-Path $PSScriptRoot 'capture_art.ps1') -Phase before
 & (Join-Path $PSScriptRoot 'capture_art.ps1') -Phase before -SilhouettesOnly
} finally {
 foreach($entry in $entries){Copy-Item -LiteralPath (Join-Path $snapshot ($entry.id+'.glb')) -Destination (Join-Path $repo ('game/assets/models/'+$entry.out)) -Force}
 & (Join-Path $PSScriptRoot 'check_art.ps1') -ImportOnly
}
