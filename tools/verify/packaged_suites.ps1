<#
.SYNOPSIS
  Runs chosen test suites inside the EXPORTED game (the release's packaged checks): each suite gets
  its own fresh user-data root and writes packaged-<mode>-<suite>-results.json into -Out, with the
  engine log beside it. Headless suites run with --headless; windowed suites render (they need a
  desktop session). Takes the machine-wide test lock and the release reservation like every release
  job (tools/dev/run_suite.ps1), so no other Godot test process shares the machine.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/verify/packaged_suites.ps1 -Out docs\evidence\verification\v0.9.17 `
    -Headless test_commentary,test_recorded_speech -Windowed test_varga_skins
#>
param(
	[Parameter(Mandatory = $true)][string]$Out,
	[string[]]$Headless = @(),
	[string[]]$Windowed = @(),
	[string]$Exe = "",
	[int]$TimeoutMinutes = 30,
	# Optional engine clock for simulation-heavy headless checks; rendered checks keep real timing.
	# Leave zero for natural timing, including regressions that specifically compare VFX lifetimes.
	[ValidateRange(0, 240)][int]$HeadlessFixedFps = 0
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Out = [System.IO.Path]::GetFullPath($Out)
if ($Exe -eq "") { $Exe = Join-Path $root "dist\Critterweight-windows-x64\Critterweight.exe" }
if (-not (Test-Path $Exe)) { Write-Host "packaged_suites: no exported game at $Exe"; exit 2 }
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
New-Item -ItemType Directory -Force $Out | Out-Null
$reserve = Join-Path $env:TEMP "critterweight_release.reserve"
Set-Content -LiteralPath $reserve -Value "packaged suites $PID"
$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
$lock = $null
while ($null -eq $lock) {
	try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
	catch { Write-Host "waiting for the test lock"; Set-Content -LiteralPath $reserve -Value "packaged suites $PID"; Start-Sleep -Seconds 10 }
}
$failed = 0
$summary = @()
try {
	$jobs = @()
	foreach ($s in ($Headless | ForEach-Object { $_.Split(",") } | Where-Object { $_ -ne "" })) { $jobs += ,@("headless", $s) }
	foreach ($s in ($Windowed | ForEach-Object { $_.Split(",") } | Where-Object { $_ -ne "" })) { $jobs += ,@("windowed", $s) }
	foreach ($j in $jobs) {
		$mode = $j[0]; $suite = $j[1]
		# Keep captures and test data beside the evidence (on B: for release work).
		$user = Join-Path $Out ("users\{0}-{1}" -f $suite, (Get-Date -Format "HHmmssfff"))
		New-Item -ItemType Directory -Force $user | Out-Null
		$res = Join-Path $Out ("packaged-{0}-{1}-results.json" -f $mode, $suite)
		$log = Join-Path $Out ("packaged-{0}-{1}.log" -f $mode, $suite)
		$a = @()
		if ($mode -eq "headless") {
			$a += "--headless"
			if ($HeadlessFixedFps -gt 0) { $a += @("--fixed-fps", "$HeadlessFixedFps") }
		}
		$a += @("--", "--user-root", $user, "--test", $suite, "--test-out", $res)
		$quoted = $a | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
		# Each result belongs to this invocation; a crashed run must not inherit an earlier pass.
		if (Test-Path -LiteralPath $res) { Remove-Item -LiteralPath $res }
		Write-Host "==> $mode $suite"
		$p = Start-Process -FilePath $Exe -ArgumentList $quoted -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + ".err")
		$null = $p.Handle # Keep the native handle alive so .ExitCode remains available after WaitForExit.
		try { $p.PriorityClass = 'BelowNormal' } catch {}
		if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) { $p.Kill(); Write-Host "    timed out"; $failed++; $summary += "$mode $suite TIMEOUT"; continue }
		$code = $p.ExitCode
		if ($code -ne 0) { $failed++ }
		$line = "$mode $suite exit $code"
		if (Test-Path $res) {
			$j2 = Get-Content $res -Raw | ConvertFrom-Json
			$line = "{0} {1}: {2} run, {3} failed, {4} skipped (exit {5})" -f $mode, $suite, $j2.total, $j2.failed, $j2.skipped, $code
			if ([int]$j2.failed -gt 0 -or [int]$j2.total -eq 0) { $failed++ }
		} else { $failed++; $line += " (no results file)" }
		# Godot writes many parse/runtime errors to stderr, including after a results file was saved.
		$errs = Select-String -Path @($log, ($log + ".err")) -Pattern "SCRIPT ERROR|Parse Error" -SimpleMatch:$false -ErrorAction SilentlyContinue
		if ($errs) { $line += " ; script errors in the log: $($errs.Count)"; $failed++ }
		Write-Host "    $line"
		$summary += $line
	}
}
finally {
	$lock.Close()
	Remove-Item -LiteralPath $reserve -ErrorAction SilentlyContinue
}
$summary | Set-Content -LiteralPath (Join-Path $Out "packaged-suites-summary.txt")
exit $failed
