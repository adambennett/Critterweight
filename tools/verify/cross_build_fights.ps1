<#
.SYNOPSIS
  Gameplay identity between two checkouts (e.g. the previous release and this one): the same seeded
  pro-bot fights, stepped headless at the fixed tick (game/src/test/core/test_cross_build_fights.gd,
  which must be byte-identical in both), compared event by event. Takes the machine-wide test lock and
  the release reservation (tools/dev/run_suite.ps1). Writes before.json, after.json and compare.md.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/verify/cross_build_fights.ps1 -Before B:\Critterweight-work\baseline-src -After B:\git\Critterweight -Out B:\Critterweight-work\v0.9.17\cross_build
#>
param(
	[Parameter(Mandatory = $true)][string]$Before,
	[Parameter(Mandatory = $true)][string]$After,
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
$rel = "game\src\test\core\test_cross_build_fights.gd"
$h1 = (Get-FileHash -Algorithm SHA256 (Join-Path $Before $rel)).Hash
$h2 = (Get-FileHash -Algorithm SHA256 (Join-Path $After $rel)).Hash
if ($h1 -ne $h2) { throw "test_cross_build_fights.gd differs between the checkouts; copy the same file into both first" }
New-Item -ItemType Directory -Force $Out | Out-Null
$reserve = Join-Path $env:TEMP "critterweight_release.reserve"
Set-Content -LiteralPath $reserve -Value "cross-build fights $PID"
$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
$lock = $null
while ($null -eq $lock) {
	try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
	catch { Write-Host "waiting for the test lock"; Set-Content -LiteralPath $reserve -Value "cross-build fights $PID"; Start-Sleep -Seconds 10 }
}
try {
	foreach ($pair in @(@('before', $Before), @('after', $After))) {
		$json = Join-Path $Out ($pair[0] + ".json")
		$user = Join-Path $Out ("user_" + $pair[0])
		Write-Host "==> $($pair[0])"
		& $Godot --headless --path (Join-Path $pair[1] "game") --fixed-fps 120 -- --user-root $user --test test_cross_build_fights --fights-out $json *> (Join-Path $Out ($pair[0] + ".log"))
		Write-Host ("    exit {0}" -f $LASTEXITCODE)
	}
} finally {
	$lock.Close()
	Remove-Item -LiteralPath $reserve -ErrorAction SilentlyContinue
}
# compare: gameplay events only (presentation-only event types added by a release are listed apart)
$py = @'
import json, sys
GAME = {"hit", "knockdown", "getup", "ko", "downed", "dodge", "parry", "guard_break", "ability", "juice", "juice_end", "throw",
        "grab", "reaction", "status", "ringout", "slam", "counter", "round_start", "round_end", "timeout", "match_end", "taunt"}
a = json.load(open(sys.argv[1], encoding="utf-8")); b = json.load(open(sys.argv[2], encoding="utf-8"))
rows, same = [], 0
for fa, fb in zip(a["fights"], b["fights"]):
    ea = [e for e in fa["events"] if e.get("type") in GAME]; eb = [e for e in fb["events"] if e.get("type") in GAME]
    n = 0
    while n < min(len(ea), len(eb)) and ea[n] == eb[n]:
        n += 1
    ok = n == len(ea) == len(eb) and fa["winner_team"] == fb["winner_team"] and fa["health"] == fb["health"] and fa["ticks"] == fb["ticks"]
    same += ok
    first = "" if ok else "first difference at event %d: %s / %s" % (n, json.dumps(ea[n] if n < len(ea) else None), json.dumps(eb[n] if n < len(eb) else None))
    rows.append("| %s | %d | %d | %s | %s |" % (" vs ".join(f.replace("f_", "") for f in fa["fighters"]), len(ea), fa["ticks"], "identical" if ok else "DIFFERENT", first))
out = ["# Cross-build fights: %s vs %s" % (a["version"], b["version"]), "",
       "%d of %d seeded fights identical (gameplay events, tick by tick; final health; winner)." % (same, len(rows)), "",
       "| Fight | Events | Ticks | Result | Detail |", "|---|---:|---:|---|---|"] + rows
open(sys.argv[3], "w", encoding="utf-8").write("\n".join(out) + "\n")
print(out[2])
'@
$pyPath = Join-Path $Out "compare.py"
Set-Content -LiteralPath $pyPath -Value $py -Encoding UTF8
& python $pyPath (Join-Path $Out "before.json") (Join-Path $Out "after.json") (Join-Path $Out "compare.md")
