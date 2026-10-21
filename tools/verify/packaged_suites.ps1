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
	[int]$TimeoutMinutes = 30
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
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
		$user = Join-Path $env:TEMP ("critterweight-packaged-{0}-{1}" -f $suite, (Get-Date -Format "HHmmssfff"))
		New-Item -ItemType Directory -Force $user | Out-Null
		$res = Join-Path $Out ("packaged-{0}-{1}-results.json" -f $mode, $suite)
		$log = Join-Path $Out ("packaged-{0}-{1}.log" -f $mode, $suite)
		$a = @()
		if ($mode -eq "headless") { $a += "--headless" }
		$a += @("--", "--user-root", $user, "--test", $suite, "--test-out", $res)
		Write-Host "==> $mode $suite"
		$p = Start-Process -FilePath $Exe -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + ".err")
		try { $p.PriorityClass = 'BelowNormal' } catch {}
		if (-not $p.WaitForExit($TimeoutMinutes * 60 * 1000)) { $p.Kill(); Write-Host "    timed out"; $failed++; $summary += "$mode $suite TIMEOUT"; continue }
		$code = $p.ExitCode
		$line = "$mode $suite exit $code"
		if (Test-Path $res) {
			$j2 = Get-Content $res -Raw | ConvertFrom-Json
			$line = "{0} {1}: {2} run, {3} failed, {4} skipped" -f $mode, $suite, $j2.total, $j2.failed, $j2.skipped
			if ([int]$j2.failed -gt 0 -or [int]$j2.total -eq 0) { $failed++ }
		} else { $failed++; $line += " (no results file)" }
		$errs = Select-String -Path $log -Pattern "SCRIPT ERROR|Parse Error" -SimpleMatch:$false -ErrorAction SilentlyContinue
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
