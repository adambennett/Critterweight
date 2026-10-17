param([string]$ArtRoot='B:\Critterweight-art')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out=Join-Path $repo 'docs\evidence\art\revamp'
$verify=Join-Path $out 'verification'
New-Item -ItemType Directory -Force -Path $verify | Out-Null
$source=Join-Path $ArtRoot 'captures'
foreach($name in @('performance-summary.json','art-stats.json','model-audit-final.json','export-determinism.json','baseline-determinism.json','baseline-model-hashes.json','baseline-stats.json','retained-forge-determinism.json','retained-forge-stats.json','art-full-suite-run.json')) {
 $file=Join-Path $source $name
 if(Test-Path -LiteralPath $file){Copy-Item -LiteralPath $file -Destination (Join-Path $verify $name)}
}
foreach($name in @('baseline-forge','baseline-test_content_audit','baseline-test_content_targets','baseline-test_hub_cosmetics','art-import','art-check','art-test_content_audit','art-test_content_targets','art-test_hub_cosmetics','retained-forge','art-full-suite')) {
 $file=Join-Path $source ($name+'.log')
 if(Test-Path -LiteralPath $file){[IO.File]::WriteAllText((Join-Path $verify ($name+'.txt')),(Get-Content -Raw -LiteralPath $file),[Text.UTF8Encoding]::new($false))}
}
function Save-CaptureRecords([string]$from,[string]$dest) {
 $commands=[ordered]@{};$logs=[ordered]@{}
 Get-ChildItem -LiteralPath $from -Filter '*-command.json' | Sort-Object Name | ForEach-Object {$commands[$_.Name]=@(Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json)}
 Get-ChildItem -LiteralPath $from -Filter '*-engine.log' | Where-Object {$_.BaseName -notlike 'stoke-duel*'} | Sort-Object Name | ForEach-Object {$logs[$_.Name]=@(Get-Content -LiteralPath $_.FullName)}
 [pscustomobject]@{commands=$commands;engineLogs=$logs} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dest 'capture-records.json') -Encoding utf8
 # Replace only previously generated per-capture copies inside this exact evidence folder.
 $expected=[IO.Path]::GetFullPath((Join-Path $repo 'docs\evidence\art\revamp\verification'))+'\'
 $resolved=(Resolve-Path -LiteralPath $dest).Path
 if(-not $resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence cleanup path escaped verification folder'}
 Get-ChildItem -LiteralPath $resolved -File | Where-Object {$_.Name -like '*-command.json' -or $_.Name -like '*-engine.txt'} | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
}
foreach($phase in @('before','after')) {
 $dest=Join-Path $verify $phase
 New-Item -ItemType Directory -Force -Path $dest | Out-Null
 Save-CaptureRecords (Join-Path $source $phase) $dest
 foreach($preset in @('deck','high')) {Copy-Item -LiteralPath (Join-Path $source "$phase\busy-bench-$preset.json") -Destination (Join-Path $dest "busy-bench-$preset.json")}
}
# Paired reruns are retained in full, including slow runs and background-CPU context.
$paired=Get-ChildItem -LiteralPath $source -Directory -Filter 'paired-bench-*' | Sort-Object Name | Select-Object -Last 1
if($paired){
 $dest=Join-Path $verify 'paired-bench'
 New-Item -ItemType Directory -Force -Path $dest | Out-Null
 Get-ChildItem -LiteralPath $paired.FullName -Filter *.json | Where-Object {$_.Name -notlike '*command*'} | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dest $_.Name)}
 Save-CaptureRecords $paired.FullName $dest
}
Write-Output 'Collected art audits, reproduction commands and verification output.'
