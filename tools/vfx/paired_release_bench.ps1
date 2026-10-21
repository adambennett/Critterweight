<#
.SYNOPSIS
  ABBA performance comparison of two checkouts (e.g. the previous release vs this one) with the
  rendered 8-fighter bench (docs/art/VFX.md §6, docs/VERIFICATION.md).
.DESCRIPTION
  Runs `--bench busy` (8 pro bots, FFA, primary cage) in the order before, after, after, before for
  each preset/resolution (deck 1280x800, high 1920x1080), plain and with every fighter using an
  ability at once every `-AbilitiesEvery` seconds. The bench script itself must be identical in both
  checkouts (copy game/src/test/bench.gd into the "before" checkout; it only uses APIs that already
  existed). Takes the machine-wide full-suite lock so no suite runs at the same time; Idle priority
  as AGENTS.md asks for long benches. Writes one JSON per run plus summary.json / summary.md.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/paired_release_bench.ps1 -Before B:\Critterweight-work\baseline-src -After B:\git\Critterweight -Out B:\Critterweight-work\v0.9.17\perf
#>
param(
	[Parameter(Mandatory = $true)][string]$Before,
	[Parameter(Mandatory = $true)][string]$After,
	[Parameter(Mandatory = $true)][string]$Out,
	[double]$AbilitiesEvery = 3.0,
	[int]$Duration = 30,
	[int]$Warmup = 5,
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
try { (Get-Process -Id $PID).PriorityClass = 'Idle' } catch {}
New-Item -ItemType Directory -Force $Out | Out-Null
$bench = @{}
foreach ($pair in @(@('before', $Before), @('after', $After))) {
	$h = (Get-FileHash -Algorithm SHA256 (Join-Path $pair[1] 'game\src\test\bench.gd')).Hash
	$bench[$pair[0]] = $h
}
if ($bench['before'] -ne $bench['after']) { throw "bench.gd differs between the checkouts; copy the same file into both first" }
$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
$lock = $null
# reserve the machine (tools/dev/run_suite.ps1): filtered test runs hold back until the bench is done
$reserve = Join-Path $env:TEMP "critterweight_release.reserve"
Set-Content -LiteralPath $reserve -Value "paired bench $PID"
while ($null -eq $lock) {
	try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
	catch { Write-Host "waiting for the full-suite lock"; Set-Content -LiteralPath $reserve -Value "paired bench $PID"; Start-Sleep -Seconds 15 }
}
$results = @()
try {
	foreach ($phase in @('before-1', 'after-1', 'after-2', 'before-2')) {
		$root = if ($phase.StartsWith('before')) { $Before } else { $After }
		foreach ($preset in @('deck', 'high')) {
			$res = if ($preset -eq 'deck') { '1280x800' } else { '1920x1080' }
			foreach ($load in @('plain', 'abilities')) {
				$name = "$phase-$preset-$load"
				$json = Join-Path $Out "$name.json"
				$a = @('--path', (Join-Path $root 'game'), '--resolution', $res, '--windowed', '--position', '40,40',
					'--log-file', (Join-Path $Out "$name-engine.log"), '--',
					'--user-root', (Join-Path $Out "user-$preset"), '--bench', 'busy', '--n', '8', '--preset', $preset,
					'--warmup', "$Warmup", '--duration', "$Duration", '--out', $json, '--windowed', '--size', $res)
				if ($load -eq 'abilities') { $a += @('--abilities-every', "$AbilitiesEvery") }
				& $Godot @a *> (Join-Path $Out "$name.log")
				if ($LASTEXITCODE -ne 0 -or -not (Test-Path $json)) { throw "$name failed (exit $LASTEXITCODE)" }
				$b = Get-Content -Raw $json | ConvertFrom-Json
				$row = [pscustomobject]@{ run = $name; phase = $phase; build = $phase.Split('-')[0]; preset = $preset; resolution = $res; load = $load;
					fps = [Math]::Round($b.fps_avg, 1); p50 = $b.frame_ms.p50; p95 = $b.frame_ms.p95; p99 = $b.frame_ms.p99; max = $b.frame_ms.max;
					over16 = [Math]::Round($b.frames_over_16_7ms_pct, 3); draws = $b.draw_calls.mean; prims = $b.primitives.mean;
					vram = [Math]::Round($b.video_mem_mb, 1); bursts = $b.ability_bursts; window = ($b.resolution -join 'x') }
				$results += $row
				Write-Host ("{0}: {1} fps, p95 {2} ms, p99 {3} ms, >16.7 ms {4}%, draws {5}, bursts {6}" -f $name, $row.fps, $row.p95, $row.p99, $row.over16, $row.draws, $row.bursts)
			}
		}
	}
} finally {
	if ($null -ne $lock) { $lock.Close() }
	Remove-Item -LiteralPath $reserve -ErrorAction SilentlyContinue
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Out 'summary.json') -Encoding utf8
$md = @("| build | preset | load | fps (2 runs) | p95 ms | p99 ms | frames > 16.7 ms | draw calls |", "|---|---|---|---|---|---|---|---|")
foreach ($g in ($results | Group-Object build, preset, load)) {
	$r = $g.Group
	$md += ("| {0} | {1} {2} | {3} | {4} | {5} | {6} | {7} | {8} |" -f $r[0].build, $r[0].preset, $r[0].resolution, $r[0].load,
		(($r | ForEach-Object { $_.fps }) -join ' / '), (($r | ForEach-Object { $_.p95 }) -join ' / '),
		(($r | ForEach-Object { $_.p99 }) -join ' / '), (($r | ForEach-Object { "$($_.over16)%" }) -join ' / '),
		(($r | ForEach-Object { [Math]::Round($_.draws, 0) }) -join ' / '))
}
$md | Set-Content -LiteralPath (Join-Path $Out 'summary.md') -Encoding utf8
Write-Host "done: $Out"
