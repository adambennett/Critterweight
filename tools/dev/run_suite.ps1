<#
.SYNOPSIS
  Runs the Godot test suite (or a test filter) at below-normal priority. A FULL suite (no -Filter)
  first takes a machine-wide lock, so parallel checkouts/agents run full suites one at a time
  instead of overloading the CPU (which slows everyone and makes timing tests fail).
.DESCRIPTION
  The lock is an exclusively opened file in %TEMP%; the OS releases it if the holder dies, so a
  crashed run never blocks the queue. Child processes (test servers/clients) inherit the lower
  priority, keeping the desktop responsive.
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
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Continue"
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$lock = $null
if ($Filter -eq "") {
	$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
	$deadline = (Get-Date).AddMinutes($WaitMinutes)
	$announced = $false
	while ($null -eq $lock) {
		try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
		catch {
			if (-not $announced) { Write-Host "waiting for the full-suite lock (another checkout is running its suite)"; $announced = $true }
			if ((Get-Date) -gt $deadline) { Write-Host "gave up waiting for the full-suite lock"; exit 99 }
			Start-Sleep -Seconds 15
		}
	}
}
$code = 1
try {
	$a = @("--headless", "--path", $GamePath, "--fixed-fps", "120", "--", "--test")
	if ($Filter -ne "") { $a += $Filter }
	if ($Log -ne "") { & $Godot @a *> $Log } else { & $Godot @a }
	$code = $LASTEXITCODE
} finally {
	if ($null -ne $lock) { $lock.Close() }
}
exit $code
