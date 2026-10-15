<#
.SYNOPSIS
  UI-12: runs Granny Haymaker's tutorial course (test_tutorial.gd) once per fighter, in parallel,
  against the Kid the game launches for that fighter, and prints one line per fighter.
.DESCRIPTION
  Fighters: every creature in game/content/core/creatures that is not npc_only (dev_biped and the
  roster), or the ones given with -Fighters. Each run has its own user-data root. Exit code = the
  number of fighters with a failing test. See docs/design/ANNOUNCER_AND_TUTORIAL.md section 2.3.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/verify/tutorial_matrix.ps1
  powershell -ExecutionPolicy Bypass -File tools/verify/tutorial_matrix.ps1 -Fighters f_dozer -Filter test_light_string
#>
param(
	[string[]]$Fighters = @(),
	[string]$Filter = "",
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Fighters.Count -eq 0) {
	foreach ($f in Get-ChildItem (Join-Path $root "game\content\core\creatures") -Filter *.json) {
		$c = Get-Content $f.FullName -Raw | ConvertFrom-Json
		if (-not $c.npc_only) { $Fighters += [string]$c.id }
	}
}
$test = "test_tutorial.gd" + $(if ($Filter -ne "") { "::$Filter" } else { "" })
$runs = @()
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
	$runs += [pscustomobject]@{ Id = $id; P = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}
$failed = 0
foreach ($r in $runs) {
	$r.P.WaitForExit()
	$lines = $r.Out.Result -split "`r?`n"
	$summary = ($lines | Where-Object { $_ -match "^tests: " }) -join ""
	if ($r.P.ExitCode -ne 0) { $failed += 1 }
	Write-Host ("{0,-12} exit {1}  {2}" -f $r.Id, $r.P.ExitCode, $summary) -ForegroundColor $(if ($r.P.ExitCode -eq 0) { "Green" } else { "Red" })
	$lines | Where-Object { $_ -match "^    tut_|^FAIL|^\s{8}" } | ForEach-Object { Write-Host $_ }
}
exit $failed
