param([switch]$ImportOnly,[switch]$CheckOnly,[string[]]$Filters=@('test_content_audit','test_content_targets','test_hub_cosmetics'))
$ErrorActionPreference='Stop'
$lockTemp=[Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','User'))
. (Join-Path $PSScriptRoot 'art_env.ps1')
Set-ArtRuntimePaths
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$g='C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe'
$lock=$null
try {
 while($null -eq $lock) {
  try {$lock=[IO.File]::Open((Join-Path $lockTemp 'critterweight_full_suite.lock'),'OpenOrCreate','ReadWrite','None')}
  catch {Write-Output 'Waiting for shared suite lock before art checks';Start-Sleep -Seconds 15}
 }
 $log=Join-Path $ArtRoot 'captures\art-import.log'
 & $g --headless --path (Join-Path $repo 'game') --import *> $log
 if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)){Get-Content $log -Tail 30;throw 'Import failed'}
 Write-Output 'Art import passed'
 if($ImportOnly){return}
 $log=Join-Path $ArtRoot 'captures\art-check.log'
 & $g --headless --path (Join-Path $repo 'game') -- --user-root (Join-Path $ArtRoot 'test_root') --check *> $log
 if($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet)){Get-Content $log -Tail 30;throw 'Compile check failed'}
 Write-Output 'Script compile check passed'
 if($CheckOnly){return}
 foreach($filter in $Filters) {
  $log=Join-Path $ArtRoot "captures\art-$filter.log"
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\run_suite.ps1') -GamePath (Join-Path $repo 'game') -Filter $filter -UserRoot (Join-Path $ArtRoot 'test_root') -Log $log
  if($LASTEXITCODE -ne 0){Get-Content $log -Tail 30;throw "Targeted test failed: $filter"}
  Get-Content $log -Tail 4
 }
} finally {if($null -ne $lock){$lock.Close()}}
