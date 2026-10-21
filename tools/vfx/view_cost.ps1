<#
.SYNOPSIS
  Per-frame cost of the eight fighter views (game/src/test/core/test_view_cost.gd) in several
  checkouts, one after another, each twice, windowed at 1280x800. The test file must be identical in
  every checkout. Takes the machine-wide test lock and the release reservation
  (tools/dev/run_suite.ps1). Writes <label>-<n>.json per run and prints a summary.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/view_cost.ps1 -Checkouts "v0.9.16=B:\Critterweight-work\baseline-src,v0.9.17=B:\git\Critterweight" -Out B:\Critterweight-work\v0.9.17\view_cost
#>
param(
	[Parameter(Mandatory = $true)][string]$Checkouts,
	[Parameter(Mandatory = $true)][string]$Out,
	[int]$Runs = 2,
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
New-Item -ItemType Directory -Force $Out | Out-Null
$pairs = @()
foreach ($kv in $Checkouts.Split(",")) { $p = $kv.Split("=", 2); $pairs += ,@($p[0], $p[1]) }
$hashes = $pairs | ForEach-Object { (Get-FileHash -Algorithm SHA256 (Join-Path $_[1] "game\src\test\core\test_view_cost.gd")).Hash } | Select-Object -Unique
if (@($hashes).Count -ne 1) { throw "test_view_cost.gd differs between the checkouts; copy the same file into each first" }
$reserve = Join-Path $env:TEMP "critterweight_release.reserve"
Set-Content -LiteralPath $reserve -Value "view cost $PID"
$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
$lock = $null
while ($null -eq $lock) {
	try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
	catch { Write-Host "waiting for the test lock"; Set-Content -LiteralPath $reserve -Value "view cost $PID"; Start-Sleep -Seconds 10 }
}
try {
	for ($r = 1; $r -le $Runs; $r++) {
		foreach ($pair in $pairs) {
			$json = Join-Path $Out ("{0}-{1}.json" -f $pair[0], $r)
			& $Godot --path (Join-Path $pair[1] "game") --resolution 1280x800 --windowed -- --user-root (Join-Path $Out ("user_" + $pair[0])) --test test_view_cost --view-cost $json *> (Join-Path $Out ("{0}-{1}.log" -f $pair[0], $r))
			if (Test-Path $json) {
				$j = Get-Content -Raw $json | ConvertFrom-Json
				Write-Host ("{0} run {1}: render all 8 = {2} ms/frame (materials {3} ms), frame {4} ms" -f $pair[0], $r, $j.render_ms_per_frame_all8, $j.materials_ms_per_frame_all8, $j.frame_ms)
			} else { Write-Host ("{0} run {1}: no result (see log)" -f $pair[0], $r) }
		}
	}
} finally {
	$lock.Close()
	Remove-Item -LiteralPath $reserve -ErrorAction SilentlyContinue
}
