<#
.SYNOPSIS
  Runs the Godot test suite (or a test filter) at below-normal priority. Every run, full or
  filtered, first takes a machine-wide lock, so parallel checkouts/agents run one Godot test process
  at a time instead of overloading the CPU (which slows everyone and makes timing tests fail).
.DESCRIPTION
  The lock is an exclusively opened file in %TEMP%; the OS releases it if the holder dies, so a
  crashed run never blocks the queue. Child processes (test servers/clients) inherit the lower
  priority, keeping the desktop responsive. Each checkout gets its own test user-data root (under
  %TEMP%, keyed by the checkout path) so runs in different worktrees never share files; a full
  suite starts from an empty root.
.EXAMPLE
  # from a checkout or worktree root:
  powershell -ExecutionPolicy Bypass -File C:\Users\eX_Di\git\PokemonMMA\PokeMMA\tools\dev\run_suite.ps1 -Log suite.log
  powershell -ExecutionPolicy Bypass -File <path>\run_suite.ps1 -Filter test_tutorial
#>
param(
	[string]$GamePath = "game",
	[string]$Filter = "",
	[string]$Log = "",
	[int]$WaitMinutes = 240,
	[string]$UserRoot = "",
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe",
	# refresh the import and script-class caches first (a fresh worktree has no .godot folder, and a
	# new class_name is unknown until the editor has scanned); done automatically when .godot is missing
	[switch]$Import
)
$ErrorActionPreference = "Continue"
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$lock = $null
$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
$deadline = (Get-Date).AddMinutes($WaitMinutes)
$announced = $false
# release jobs (full suites, the commentary audit, benches, captures) reserve the machine while they
# wait for and hold the lock: filtered runs hold back while the reservation is fresh (< 6 h old), so
# a stream of short runs cannot starve a long job
$reserve = Join-Path $env:TEMP "critterweight_release.reserve"
if ($Filter -eq "") {
	Set-Content -LiteralPath $reserve -Value "full suite $PID"
} else {
	$held = $false
	while ((Test-Path $reserve) -and ((Get-Date) - (Get-Item $reserve).LastWriteTime).TotalHours -lt 6) {
		if (-not $held) { Write-Host "a release job has reserved the machine; waiting"; $held = $true }
		if ((Get-Date) -gt $deadline) { Write-Host "gave up waiting for the reservation"; exit 99 }
		Start-Sleep -Seconds 10
	}
}
while ($null -eq $lock) {
	try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
	catch {
		if (-not $announced) { Write-Host "waiting for the test lock (another checkout or agent is running Godot tests)"; $announced = $true }
		if ((Get-Date) -gt $deadline) { Write-Host "gave up waiting for the test lock"; exit 99 }
		Start-Sleep -Seconds $(if ($Filter -eq "") { 15 } else { 3 })
	}
}
if ($UserRoot -eq "") {
	$abs = (Resolve-Path $GamePath).Path
	$sha = [System.Security.Cryptography.SHA1]::Create()
	$hex = [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($abs.ToLowerInvariant()))).Replace("-", "")
	$UserRoot = Join-Path $env:TEMP ("critterweight_tests_" + $hex.Substring(0, 10))
}
if ($Filter -eq "" -and (Test-Path $UserRoot)) { Remove-Item -LiteralPath $UserRoot -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force $UserRoot | Out-Null
$code = 1
try {
	if ($Import -or -not (Test-Path (Join-Path $GamePath ".godot\global_script_class_cache.cfg"))) {
		Write-Host "importing $GamePath (script classes and assets)"
		& $Godot --headless --path $GamePath --import *> (Join-Path $UserRoot 'import.log')
	}
	$a = @("--headless", "--path", $GamePath, "--log-file", (Join-Path $UserRoot 'engine.log'), "--fixed-fps", "120")
	# a filtered run that never finishes (a script that failed to parse leaves the runner idle) quits
	# after 50 simulated minutes instead of holding the machine-wide lock forever
	if ($Filter -ne "") { $a += @("--quit-after", "360000") }
	$a += @("--", "--user-root", $UserRoot, "--test")
	if ($Filter -ne "") { $a += $Filter }
	if ($Log -ne "") { & $Godot @a *> $Log } else { & $Godot @a }
	$code = $LASTEXITCODE
} finally {
	if ($null -ne $lock) { $lock.Close() }
	if ($Filter -eq "") { Remove-Item -LiteralPath $reserve -ErrorAction SilentlyContinue }
}
exit $code
