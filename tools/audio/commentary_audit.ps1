<#
.SYNOPSIS
  Runs the commentary audit (docs/audio/COMMENTARY.md) as two consecutive game processes sharing one
  user-data root: session A = the scripted event sequences + bouts 0-5, session B = bouts 6-11 (a
  game restart in between). Headless, REAL TIME (the announcer's clock is wall time), BelowNormal.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/audio/commentary_audit.ps1 -GamePath game -Out B:\Critterweight-work\v0.9.17\audit\revised -Label revised
#>
param(
	[string]$GamePath = "game",
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Label = "run",
	[int]$Split = 6,
	[int]$Total = 12,
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
# the machine-wide test lock (tools/dev/run_suite.ps1): a real-time audit must not share the CPU
# with test runs (its timings are what it measures)
$lock = $null
$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
while ($null -eq $lock) {
	try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
	catch { Write-Host "waiting for the test lock"; Start-Sleep -Seconds 10 }
}
New-Item -ItemType Directory -Force $Out | Out-Null
$root = Join-Path $Out "user_root"
if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
New-Item -ItemType Directory -Force $root | Out-Null
$sessions = @(
	@{ name = "A"; args = @("--sequence", "1", "--start-bout", "0", "--bouts", "$Split") },
	@{ name = "B"; args = @("--sequence", "0", "--start-bout", "$Split", "--bouts", "$($Total - $Split)") }
)
foreach ($s in $sessions) {
	$json = Join-Path $Out ("session_{0}.json" -f $s.name)
	$log = Join-Path $Out ("session_{0}.log" -f $s.name)
	$a = @("--headless", "--path", $GamePath, "--log-file", (Join-Path $Out ("engine_{0}.log" -f $s.name)), "--", "--user-root", $root,
		"--bench", "commentary", "--out", $json, "--label", "$Label/$($s.name)") + $s.args
	Write-Host ("==> session {0}: {1}" -f $s.name, ($s.args -join " "))
	& $Godot @a *> $log
	if ($LASTEXITCODE -ne 0 -or -not (Test-Path $json)) { Write-Host "session $($s.name) failed (exit $LASTEXITCODE); see $log"; $lock.Close(); exit 1 }
}
$lock.Close()
Write-Host "done: $Out"
