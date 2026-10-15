<#
.SYNOPSIS
  End-to-end verification of the PACKAGED Windows build: builds (optional), runs the full test
  suite inside the exported executable, captures runtime screenshots of real screens/modes from
  the packaged game, runs the performance benches, and writes a machine-readable summary.
.DESCRIPTION
  Output: docs/evidence/verification/<timestamp>/ with summary.json, summary.md, logs and PNGs.
  Every run uses an isolated user-data root (--user-root) so the player's own profile is never
  touched. Steps that need features not present in the build are reported as "skipped" with the
  reason (never as passed).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/verify/run_verification.ps1 -Build
#>
param(
	[switch]$Build,
	[switch]$SkipBench,
	[int]$BenchSeconds = 30,
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$out = Join-Path $root "docs\evidence\verification\$stamp"
New-Item -ItemType Directory -Force $out | Out-Null
$userRoot = Join-Path $env:TEMP "critterweight-verify-$stamp"
New-Item -ItemType Directory -Force $userRoot | Out-Null
$results = [ordered]@{ started = (Get-Date).ToString("s"); steps = @() }

function Record($name, $status, $detail) {
	$script:results.steps += [ordered]@{ name = $name; status = $status; detail = $detail }
	$color = @{ pass = "Green"; fail = "Red"; skipped = "Yellow" }[$status]
	Write-Host ("[{0}] {1} - {2}" -f $status.ToUpper(), $name, $detail) -ForegroundColor $color
}

if ($Build) {
	& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tools\build\package.ps1") -RunTests 2>&1 | Tee-Object -FilePath (Join-Path $out "build.log") | Out-Null
	if ($LASTEXITCODE -eq 0) { Record "package build (+ source tests)" "pass" "tools/build/package.ps1 -RunTests" } else { Record "package build" "fail" "exit $LASTEXITCODE (see build.log)" }
}

$exe = Join-Path $root "dist\Critterweight-windows-x64\Critterweight.exe"
if (-not (Test-Path $exe)) { Record "packaged executable" "fail" "missing $exe (run with -Build)"; $results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "summary.json"); exit 1 }
$manifest = Join-Path $root "dist\BUILD_MANIFEST.json"
if (Test-Path $manifest) { Copy-Item $manifest $out }

# 1. scripts + full test suite inside the packaged build (GUI-subsystem exe: run via Start-Process
#    so PowerShell waits and the exit code is real)
function RunExe($argList, $logName) {
	$log = Join-Path $out $logName
	$p = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -Wait -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError ($log + ".err")
	return @{ code = $p.ExitCode; text = (Get-Content $log -ErrorAction SilentlyContinue) }
}
$chk = RunExe @("--headless", "--", "--user-root", $userRoot, "--check") "packaged_check.log"
$line = ($chk.text | Select-String "checked \d+ scripts").Line
if ($chk.code -eq 0) { Record "packaged script check" "pass" $line } else { Record "packaged script check" "fail" "$line (exit $($chk.code))" }
$t = RunExe @("--headless", "--fixed-fps", "120", "--", "--user-root", $userRoot, "--test") "packaged_tests.log"
$sum = ($t.text | Select-String "^tests: ").Line
if ($t.code -eq 0) { Record "packaged test suite" "pass" $sum } else { Record "packaged test suite" "fail" "$sum (exit $($t.code))" }

# Runs the packaged game and samples its working set until it exits (release builds do not track
# their own static memory, so process memory is measured from outside).
function RunPeak($argList, $outName) {
	$o = Join-Path $out $outName
	$p = Start-Process -FilePath $exe -ArgumentList $argList -PassThru -RedirectStandardOutput $o -RedirectStandardError ($o + ".err")
	$peak = 0
	while (-not $p.HasExited) {
		try { $p.Refresh(); if ($p.WorkingSet64 -gt $peak) { $peak = $p.WorkingSet64 } } catch {}
		Start-Sleep -Milliseconds 250
	}
	return @{ code = $p.ExitCode; peak_mb = [math]::Round($peak / 1MB) }
}

# 1b. cold-ish boot time to the first menu screen + memory (PERF-03)
$boot = Join-Path $out "boot_report.json"
$bp = RunPeak @("--", "--user-root", $userRoot, "--windowed", "--size", "1600x900", "--boot-report", $boot) "boot.out"
if (Test-Path $boot) {
	$br = Get-Content $boot | ConvertFrom-Json
	$st = if ($br.ms_since_start -lt 10000) { "pass" } else { "fail" }
	Record "boot to first menu (< 10 s)" $st ("{0} ms to '{1}', peak working set {2} MB" -f $br.ms_since_start, $br.screen, $bp.peak_mb)
} else { Record "boot to first menu" "fail" "no report (exit $($bp.code))" }
$mem = RunPeak @("--", "--user-root", $userRoot, "--windowed", "--size", "1920x1080", "--sandbox", "--autoplay", "--rules", "free_for_all", "--n", "8", "--capture", (Join-Path $out "mem_ffa8.png"), "--capture-at", "25") "mem_ffa8.out"
$mst = if ($mem.peak_mb -gt 0 -and $mem.peak_mb -lt 4096) { "pass" } else { "fail" }
Record "memory: 8-fighter match, 25 s (< 4 GB)" $mst ("peak working set {0} MB" -f $mem.peak_mb)

# 2. runtime captures from the packaged game (real rendering, isolated user data)
$captures = @(
	@{ name = "title"; args = @("--ui-screen", "title"); at = 4 },
	@{ name = "main_menu"; args = @("--ui-screen", "main_menu"); at = 4 },
	@{ name = "settings"; args = @("--ui-screen", "settings"); at = 4 },
	@{ name = "mods"; args = @("--screen", "mods"); at = 3 },
	@{ name = "rules_editor"; args = @("--screen", "rules_editor", "--screen-arg", "edit=duel"); at = 3 },
	@{ name = "tutorial"; args = @("--tutorial", "0"); at = 6 },
	@{ name = "duel"; args = @("--sandbox", "--autoplay", "--rules", "duel", "--creature", "f_stoke", "--creature2", "f_dredge"); at = 8 },
	@{ name = "ffa8"; args = @("--sandbox", "--autoplay", "--rules", "free_for_all", "--n", "8"); at = 8 },
	@{ name = "spectate"; args = @("--sandbox", "--autoplay", "--spectate", "--rules", "teams_2v2", "--n", "4"); at = 9 },
	@{ name = "spotlight_hog"; args = @("--sandbox", "--autoplay", "--rules", "spotlight_hog", "--n", "4"); at = 10 },
	@{ name = "chumball"; args = @("--sandbox", "--autoplay", "--rules", "chumball", "--n", "4"); at = 10 },
	@{ name = "absolute_unit"; args = @("--sandbox", "--autoplay", "--rules", "absolute_unit", "--n", "3"); at = 10 },
	@{ name = "chum_rush"; args = @("--sandbox", "--autoplay", "--rules", "chum_rush", "--n", "2"); at = 20 },
	@{ name = "tag_team"; args = @("--sandbox", "--autoplay", "--rules", "tag_2v2", "--n", "4"); at = 10 },
	@{ name = "arena_drydock"; args = @("--sandbox", "--autoplay", "--rules", "duel", "--arena", "arena_drydock", "--creature", "f_dredge", "--creature2", "f_dozer"); at = 8 },
	@{ name = "arena_crusher"; args = @("--sandbox", "--autoplay", "--rules", "duel", "--arena", "arena_crusher", "--creature", "f_gusto", "--creature2", "f_slurry"); at = 8 },
	@{ name = "arena_rooftop"; args = @("--sandbox", "--autoplay", "--rules", "duel", "--arena", "arena_rooftop", "--creature", "f_jitters", "--creature2", "f_stoke"); at = 8 },
	@{ name = "character_select"; args = @("--screen", "character_select"); at = 3 },
	@{ name = "versus_setup"; args = @("--screen", "versus_setup"); at = 3 },
	@{ name = "arena_editor"; args = @("--screen", "arena_editor"); at = 5 },
	@{ name = "lab"; args = @("--screen", "lab"); at = 4 },
	@{ name = "online"; args = @("--screen", "online"); at = 3 },
	@{ name = "campaign_menu"; args = @("--screen", "campaign_menu"); at = 3 },
	@{ name = "spectate_setup"; args = @("--screen", "spectate"); at = 3 },
	@{ name = "profile"; args = @("--screen", "profile"); at = 3 }
)
foreach ($c in $captures) {
	$png = Join-Path $out ("capture_" + $c.name + ".png")
	$a = @("--", "--user-root", $userRoot, "--windowed", "--size", "1600x900") + $c.args + @("--capture", $png, "--capture-at", "$($c.at)")
	$p = Start-Process -FilePath $exe -ArgumentList $a -PassThru -Wait -RedirectStandardOutput (Join-Path $out "cap_$($c.name).out") -RedirectStandardError (Join-Path $out "cap_$($c.name).err")
	$errs = Select-String -Path (Join-Path $out "cap_$($c.name).err") -Pattern "SCRIPT ERROR" -ErrorAction SilentlyContinue
	if ((Test-Path $png) -and -not $errs) { Record "capture $($c.name)" "pass" (Split-Path $png -Leaf) }
	elseif (Test-Path $png) { Record "capture $($c.name)" "fail" "rendered but script errors: $($errs[0].Line)" }
	else { Record "capture $($c.name)" "fail" "no frame captured (exit $($p.ExitCode))" }
}

# 3. performance (packaged build, uncapped, 1080p High)
if (-not $SkipBench) {
	foreach ($b in @(@{ n = "busy8"; args = @("--bench", "busy", "--n", "8") }, @{ n = "duel"; args = @("--bench", "duel") })) {
		$json = Join-Path $out ("bench_" + $b.n + ".json")
		$a = @("--", "--user-root", $userRoot, "--windowed", "--size", "1920x1080") + $b.args + @("--duration", "$BenchSeconds", "--warmup", "5", "--preset", "high", "--out", $json)
		Start-Process -FilePath $exe -ArgumentList $a -PassThru -Wait | Out-Null
		if (Test-Path $json) {
			$r = Get-Content $json | ConvertFrom-Json
			Record "bench $($b.n)" "pass" ("avg {0:N1} fps, p95 {1} ms, p99 {2} ms, >16.7 ms {3:N1}%" -f $r.fps_avg, $r.frame_ms.p95, $r.frame_ms.p99, $r.frames_over_16_7ms_pct)
		} else { Record "bench $($b.n)" "fail" "no report" }
	}
	$json2 = Join-Path $out "bench_sim8.json"
	RunExe @("--headless", "--fixed-fps", "120", "--", "--user-root", $userRoot, "--bench", "sim", "--n", "8", "--duration", "60", "--out", $json2) "bench_sim8.log" | Out-Null
	if (Test-Path $json2) {
		$r2 = Get-Content $json2 | ConvertFrom-Json
		Record "bench server sim (8 fighters)" "pass" ("{0:N2} ms/tick wall, ~{1:N0}% of one core at 120 Hz" -f $r2.wall_ms_per_tick, $r2.estimated_core_share_at_120hz_pct)
	} else { Record "bench server sim" "fail" "no report" }
} else { Record "benchmarks" "skipped" "-SkipBench" }

$results.finished = (Get-Date).ToString("s")
$results.output = $out
$results | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $out "summary.json")
$md = @("# Verification run $stamp", "", "| Step | Status | Detail |", "|---|---|---|")
foreach ($s in $results.steps) { $md += "| $($s.name) | $($s.status) | $($s.detail) |" }
$md | Set-Content (Join-Path $out "summary.md")
Write-Host "Summary: $out\summary.md"
$fails = @($results.steps | Where-Object { $_.status -eq "fail" }).Count
exit $fails
