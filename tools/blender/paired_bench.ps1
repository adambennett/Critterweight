param([string]$ArtRoot='B:\Critterweight-art',[string]$ReferenceRoot='B:\Critterweight-art\tmp\baseline-rebuild')
# ABBA comparison: one shared lock, unchanged benchmark code/settings, two runs per model set/preset.
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultTemp=[Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','User'))
. (Join-Path $PSScriptRoot 'art_env.ps1')
Set-ArtRuntimePaths
(Get-Process -Id $PID).PriorityClass='Idle'
$godot='C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe'
$out=Join-Path $ArtRoot ('captures\paired-bench-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$snapshot=Join-Path $out 'new-models'
New-Item -ItemType Directory -Force -Path $snapshot | Out-Null
$entries=Get-Content -Raw (Join-Path $PSScriptRoot 'model_manifest.json') | ConvertFrom-Json | Where-Object {$_.creature}
foreach($entry in $entries){
 if(-not(Test-Path -LiteralPath (Join-Path $ReferenceRoot $entry.out))){throw "Missing original $($entry.id)"}
 Copy-Item -LiteralPath (Join-Path $repo ('game/assets/models/'+$entry.out)) -Destination (Join-Path $snapshot ($entry.id+'.glb'))
}
function Import-Models([string]$tag){
 & $godot --headless --path (Join-Path $repo 'game') --import --log-file (Join-Path $out ($tag+'-import-engine.log')) *> (Join-Path $out ($tag+'-import.log'))
 if($LASTEXITCODE -ne 0){throw 'Model import failed during paired benchmark'}
}
function Snapshot-CPU {
 $values=@{}
 Get-Process | ForEach-Object {try{if($_.TotalProcessorTime){$values[$_.Id]=$_.TotalProcessorTime.TotalSeconds}}catch{}}
 return $values
}
$lock=$null
$diskStart=(Get-PSDrive C).Free
while($null -eq $lock){
 try{$lock=[IO.File]::Open((Join-Path $defaultTemp 'critterweight_full_suite.lock'),'OpenOrCreate','ReadWrite','None')}
 catch{Write-Output 'Waiting for the shared full-suite lock before paired benchmark';Start-Sleep -Seconds 15}
}
$context=@()
try {
 foreach($phase in @('before-1','after-1','after-2','before-2')){
  foreach($entry in $entries){
   $source=if($phase.StartsWith('before')){Join-Path $ReferenceRoot $entry.out}else{Join-Path $snapshot ($entry.id+'.glb')}
   Copy-Item -LiteralPath $source -Destination (Join-Path $repo ('game/assets/models/'+$entry.out)) -Force
  }
  Import-Models $phase
  foreach($preset in @('deck','high')){
   $resolution=if($preset -eq 'deck'){'1280x800'}else{'1920x1080'}
   $name="$phase-$preset"
   $options=@('--path',(Join-Path $repo 'game'),'--resolution',$resolution,'--windowed','--position','40,40','--log-file',(Join-Path $out ($name+'-engine.log')),'--','--user-root',(Join-Path $ArtRoot ('tmp\paired-'+$preset)),'--bench','busy','--n','8','--preset',$preset,'--warmup','5','--duration','30','--out',(Join-Path $out ($name+'.json')),'--windowed','--size',$resolution)
   $options | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out ($name+'-command.json')) -Encoding utf8
   $cpu=Snapshot-CPU;$started=Get-Date
   & $godot @options *> (Join-Path $out ($name+'.log'))
   if($LASTEXITCODE -ne 0){throw "$name failed"}
   if(Select-String -LiteralPath (Join-Path $out ($name+'-engine.log')) -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet){throw "$name engine error"}
   $elapsed=((Get-Date)-$started).TotalSeconds;$delta=0.0
   $end=Snapshot-CPU
   foreach($pidKey in $cpu.Keys){if($end.ContainsKey($pidKey)){$delta += [Math]::Max(0,$end[$pidKey]-$cpu[$pidKey])}}
   $context += [pscustomobject]@{run=$name;started=$started.ToString('o');elapsedSeconds=$elapsed;survivingOtherProcessesCPUSeconds=$delta;note='CPU context omits processes that started or exited during the run; no process names recorded.'}
   $b=Get-Content -Raw -LiteralPath (Join-Path $out ($name+'.json')) | ConvertFrom-Json
   Write-Output "$name : $([Math]::Round($b.fps_avg,2)) fps; p95 $($b.frame_ms.p95) ms; >16.7 ms $([Math]::Round($b.frames_over_16_7ms_pct,3))%"
   if($diskStart-(Get-PSDrive C).Free -gt 200MB){throw 'C: fell over 200 MB during paired benchmark; investigate'}
  }
 }
} finally {
 foreach($entry in $entries){Copy-Item -LiteralPath (Join-Path $snapshot ($entry.id+'.glb')) -Destination (Join-Path $repo ('game/assets/models/'+$entry.out)) -Force}
 Import-Models 'restored-after'
 $context | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'run-context.json') -Encoding utf8
 if($null -ne $lock){$lock.Close()}
 Write-Output "Paired benchmark evidence: $out; new models restored."
}
