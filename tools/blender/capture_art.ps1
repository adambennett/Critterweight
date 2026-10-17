param(
  [ValidateSet('before','after')][string]$Phase = 'before',
  [string]$ArtRoot = 'B:\Critterweight-art',
  [string[]]$Ids = @(),
  [switch]$WallsOnly,
  [switch]$Bench,
  [switch]$Inspection,
  [switch]$Motion,
  [switch]$SilhouettesOnly
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$defaultTemp = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','User'))
if (-not $defaultTemp) { $defaultTemp = [Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','Machine')) }
. (Join-Path $PSScriptRoot 'art_env.ps1')
Set-ArtRuntimePaths
$output = Join-Path $ArtRoot "captures\$Phase"
New-Item -ItemType Directory -Path $output -Force | Out-Null
$godot = 'C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe'
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'model_manifest.json') | ConvertFrom-Json
# Share the full-suite lock while rendering so no art capture overlaps another checkout's full suite.
$lock = $null
while ($null -eq $lock) {
  try { $lock = [IO.File]::Open((Join-Path $defaultTemp 'critterweight_full_suite.lock'),'OpenOrCreate','ReadWrite','None') }
  catch { Write-Output 'Waiting for the shared full-suite lock before rendering'; Start-Sleep -Seconds 15 }
}
function Run-Capture([string]$name,[string[]]$options,[string]$resolution='1920x1080') {
  $args = @('--path',(Join-Path $repo 'game'),'--resolution',$resolution,'--windowed','--position','40,40','--max-fps','60','--log-file',(Join-Path $output "$name-engine.log")) + $options + @('--windowed','--size',$resolution)
  $args | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output "$name-command.json") -Encoding utf8
  $ErrorActionPreference = 'Continue'
  & $godot @args *> (Join-Path $output "$name.log")
  $exitCode = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($exitCode -ne 0) { throw "$name failed ($exitCode); see log" }
  if (Select-String -LiteralPath (Join-Path $output "$name-engine.log") -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { throw "$name logged an engine error" }
  $captureIndex = [Array]::IndexOf($options,'--capture')
  $captureTarget=if($captureIndex -ge 0){$options[$captureIndex+1]}else{''}
  if($options -contains '--capture-count'){$captureTarget=[IO.Path]::ChangeExtension($captureTarget,$null).TrimEnd('.')+'_00.png'}
  if ($captureIndex -ge 0 -and -not (Test-Path -LiteralPath $captureTarget)) { throw "$name did not write its capture" }
  Write-Output "Captured $name"
}
try {
  if ($Bench) {
    (Get-Process -Id $PID).PriorityClass = 'Idle'
    foreach ($preset in @('deck','high')) {
      $resolution = if ($preset -eq 'deck') {'1280x800'} else {'1920x1080'}
      Run-Capture "busy-bench-$preset" @('--','--user-root',(Join-Path $ArtRoot "tmp\bench-$Phase-$preset"),'--bench','busy','--n','8','--preset',$preset,'--warmup','5','--duration','30','--out',(Join-Path $output "busy-bench-$preset.json")) $resolution
    }
  } elseif ($Motion) {
    & $godot --headless --path (Join-Path $repo 'game') --script (Join-Path $PSScriptRoot 'configure_capture.gd') -- --user-root (Join-Path $ArtRoot 'tmp\motion') *> (Join-Path $output 'motion-profile.log')
    if($LASTEXITCODE -ne 0){throw 'Could not configure isolated motion capture profile'}
    foreach($entry in $manifest | Where-Object {$null -ne $_.creature -and (-not $Ids.Count -or $_.id -in $Ids)}) {
      $captureAt=if($entry.id -eq 'npc_blister'){'8'}else{'20'}
      $interval=if($entry.id -eq 'npc_blister'){'1'}else{'3'}
      Run-Capture ($entry.id+'-motion') @('--','--user-root',(Join-Path $ArtRoot 'tmp\motion'),'--sandbox','--autoplay','--creature',($entry.creature -replace '^game/','res://'),'--creature2','f_stoke','--capture',(Join-Path $output ($entry.id+'-motion.png')),'--capture-at',$captureAt,'--capture-count','4','--capture-every',$interval)
    }
  } elseif ($Inspection -or $SilhouettesOnly) {
    $preview=@('--script','res://src/view/model_preview.gd','--','--user-root',(Join-Path $ArtRoot 'tmp\preview'))
    foreach($entry in $manifest | Where-Object {$null -ne $_.creature -and (-not $Ids.Count -or $_.id -in $Ids)}) {
      $creaturePath=$entry.creature -replace '^game/','res://'
      foreach($mode in $(if($SilhouettesOnly){@('silhouette')}else{@('silhouette','collision')})) {
        Run-Capture ($entry.id+'-'+$mode) ($preview+@('--creatures',$creaturePath,'--yaw','25',('--'+$mode),'--capture',(Join-Path $output ($entry.id+'-'+$mode+'.png'))))
      }
      if($SilhouettesOnly){continue}
      foreach($effects in @('normal,hype,juice,hit','status,bruise,cosmetics,gore')) {
        $suffix=$effects.Split(',')[0]
        $four=(@($creaturePath,$creaturePath,$creaturePath,$creaturePath) -join ',')
        $space=if($entry.id.StartsWith('boss_')){'4.3'}elseif($entry.id -eq 'f_dredge'){'2.9'}else{'2.4'}
        Run-Capture ($entry.id+'-effects-'+$suffix) ($preview+@('--creatures',$four,'--spacing',$space,'--yaw','25','--effects',$effects,'--capture',(Join-Path $output ($entry.id+'-effects-'+$suffix+'.png'))))
      }
    }
  } else {
    $preview = @('--script','res://src/view/model_preview.gd','--','--user-root',(Join-Path $ArtRoot 'tmp\preview'),'--hype','0.5')
    if (-not $Ids.Count) {
      foreach ($group in @('fighters','bosses','minions','hub','crowd')) {
        $entries = @($manifest | Where-Object {
          $modelEntry = $_
          switch ($group) {
            'fighters' { $modelEntry.id.StartsWith('f_') }
            'bosses' { $modelEntry.id.StartsWith('boss_') }
            'minions' { $modelEntry.id.StartsWith('npc_') }
            'hub' { $modelEntry.id.StartsWith('hub_') }
            'crowd' { $modelEntry.id.StartsWith('crowd_') }
          }
        })
        $isCreature = $null -ne $entries[0].creature
        $paths = if ($isCreature) { @($entries | ForEach-Object { $_.creature -replace '^game/','res://' }) } else { @($entries | ForEach-Object { 'res://assets/models/'+$_.out }) }
        $flag = if ($isCreature) {'--creatures'} else {'--models'}
        $space = if ($group -eq 'bosses') {'4.3'} elseif ($group -eq 'fighters') {'2.4'} else {'1.7'}
        Run-Capture "wall-$group" ($preview + @($flag,($paths -join ','),'--yaw','25','--spacing',$space,'--capture',(Join-Path $output "wall-$group.png")))
      }
    }
    if (-not $WallsOnly) {
      foreach ($entry in $manifest) {
        if ($Ids.Count -and $entry.id -notin $Ids) { continue }
        $flag = if ($null -ne $entry.creature) {'--creatures'} else {'--models'}
        $modelPath = if ($null -ne $entry.creature) { $entry.creature -replace '^game/','res://' } else { 'res://assets/models/'+$entry.out }
        Run-Capture $entry.id ($preview + @($flag,$modelPath,'--yaw','25','--capture',(Join-Path $output ($entry.id+'.png'))))
      }
    }
    if (-not $Ids.Count) {
      foreach ($resolution in @('1920x1080','1280x800')) {
        Run-Capture "duel-$resolution" @('--','--user-root',(Join-Path $ArtRoot "tmp\capture-$Phase-$resolution"),'--sandbox','--autoplay','--creature','f_stoke','--creature2','f_jitters','--capture',(Join-Path $output "duel-$resolution.png"),'--capture-at','20') $resolution
        Run-Capture "busy-$resolution" @('--','--user-root',(Join-Path $ArtRoot "tmp\capture-$Phase-$resolution"),'--sandbox','--autoplay','--rules','free_for_all_lives','--n','8','--capture',(Join-Path $output "busy-$resolution.png"),'--capture-at','20') $resolution
      }
    }
  }
} finally { if ($null -ne $lock) { $lock.Close() } }
