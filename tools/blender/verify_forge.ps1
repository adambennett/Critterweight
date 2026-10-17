param([string]$ArtRoot='B:\Critterweight-art')
# Rebuild only forge-owned models; all shipped GLB hashes must remain unchanged.
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultTemp=[Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','User'))
. (Join-Path $PSScriptRoot 'art_env.ps1')
$models=Join-Path $repo 'game\assets\models'
$before=@{}
Get-ChildItem -LiteralPath $models -Filter *.glb -Recurse | ForEach-Object {$before[$_.FullName]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
$lock=$null
while($null -eq $lock){
 try{$lock=[IO.File]::Open((Join-Path $defaultTemp 'critterweight_full_suite.lock'),'OpenOrCreate','ReadWrite','None')}
 catch{Write-Output 'Waiting for the shared full-suite lock before forge';Start-Sleep -Seconds 15}
}
$started=Get-Date
$free=(Get-PSDrive C).Free
try {
 $log=Join-Path $ArtRoot 'captures\retained-forge.log'
 & node (Join-Path $repo 'tools\forge\forge.js') --stats (Join-Path $ArtRoot 'captures\retained-forge-stats.json') *> $log
 if($LASTEXITCODE -ne 0){throw 'Default forge rebuild failed'}
 $stats=Get-Content -Raw -LiteralPath (Join-Path $ArtRoot 'captures\retained-forge-stats.json') | ConvertFrom-Json
 if(@($stats).Count -ne 10){throw 'Expected exactly ten retained forge outputs'}
 $results=@(Get-ChildItem -LiteralPath $models -Filter *.glb -Recurse | ForEach-Object {
  $hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
  [pscustomobject]@{file=$_.FullName.Substring($repo.Length+1).Replace('\','/');sha256=$hash;unchanged=($before[$_.FullName] -eq $hash)}
 })
 if(@($results | Where-Object {-not $_.unchanged}).Count -or $results.Count -ne $before.Count){throw 'Default forge rebuild changed shipped model bytes'}
 [pscustomobject]@{started=$started.ToString('o');finished=(Get-Date).ToString('o');rebuilt=10;preservedBlender=12;models=$results;cFreeBefore=$free;cFreeAfter=(Get-PSDrive C).Free} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ArtRoot 'captures\retained-forge-determinism.json') -Encoding utf8
 Write-Output 'PASS: ten retained models rebuilt; all 22 shipped GLBs unchanged'
 if($free-(Get-PSDrive C).Free -gt 200MB){throw 'C: free space fell more than 200 MB; investigate before further heavy jobs'}
} finally {if($null -ne $lock){$lock.Close()}}
