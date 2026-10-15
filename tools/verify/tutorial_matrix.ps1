<#
.SYNOPSIS
  UI-12: runs Granny Haymaker's tutorial course (test_tutorial.gd) once per fighter against the Kid
  the game launches for that fighter, and prints one line per fighter.
.DESCRIPTION
  Fighters: the Test Dummy (dev_biped, npc_only since the roster is complete; test_tutorial's own
  default) and every creature in game/content/core/creatures that is not npc_only (the roster), or
  the ones given with -Fighters (an unknown id stops the script). Each run has its own
  user-data root under %TEMP%, deleted when it ends. One Godot process at a time, at below-normal
  priority (AGENTS.md machine-load rule): about five minutes for all seven. Exit code = the number of
  fighters with a failing test. See docs/design/ANNOUNCER_AND_TUTORIAL.md section 2.3.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/verify/tutorial_matrix.ps1
  powershell -ExecutionPolicy Bypass -File tools/verify/tutorial_matrix.ps1 -Fighters f_dozer,f_slurry -Filter test_light_string
#>
param(
	[string[]]$Fighters = @(),
	[string]$Filter = "",
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$known = @{}
foreach ($f in Get-ChildItem (Join-Path $root "game\content\core\creatures") -Filter *.json) {
	$c = Get-Content $f.FullName -Raw | ConvertFrom-Json
	$known[[string]$c.id] = -not $c.npc_only
}
# "-Fighters a,b" arrives as one string through "powershell -File".
$Fighters = @($Fighters | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
if ($Fighters.Count -eq 0) {
	$Fighters = @($known.Keys | Where-Object { $known[$_] -or $_ -eq "dev_biped" } | Sort-Object)
}
$unknown = @($Fighters | Where-Object { -not $known.ContainsKey($_) })
if ($unknown.Count -gt 0) {
	Write-Host ("unknown creature id(s): " + ($unknown -join ", ")) -ForegroundColor Red
	exit 100
}
$test = "test_tutorial.gd" + $(if ($Filter -ne "") { "::$Filter" } else { "" })
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}   # Godot inherits it
$failed = 0
foreach ($id in $Fighters) {
	$userRoot = Join-Path $env:TEMP "critterweight-tutorial-$id-$PID"
	New-Item -ItemType Directory -Force $userRoot | Out-Null
	$psi = New-Object System.Diagnostics.ProcessStartInfo
	$psi.FileName = $Godot
	$psi.Arguments = "--headless --path game --fixed-fps 120 -- --test $test --user-root `"$userRoot`""
	$psi.WorkingDirectory = $root
	$psi.UseShellExecute = $false
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.EnvironmentVariables["TUTORIAL_CREATURE"] = $id
	$p = [System.Diagnostics.Process]::Start($psi)
	$out = $p.StandardOutput.ReadToEndAsync()
	$err = $p.StandardError.ReadToEndAsync()
	$p.WaitForExit()
	Remove-Item -Recurse -Force -LiteralPath $userRoot -ErrorAction SilentlyContinue
	$lines = $out.Result -split "`r?`n"
	$summary = ($lines | Where-Object { $_ -match "^tests: " }) -join ""
	if ($p.ExitCode -ne 0) { $failed += 1 }
	Write-Host ("{0,-12} exit {1}  {2}" -f $id, $p.ExitCode, $summary) -ForegroundColor $(if ($p.ExitCode -eq 0) { "Green" } else { "Red" })
	$lines | Where-Object { $_ -match "^    tut_|^FAIL|^\s{8}" } | ForEach-Object { Write-Host $_ }
}
exit $failed
