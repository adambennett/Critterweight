<#
.SYNOPSIS
  Cuts a Critterweight release: version bump (optional), tag, build, smoke test, GitHub release.
.DESCRIPTION
  Versioning (docs/RELEASES.md): game/project.godot application/config/version is the single source
  of truth; every release is the commit tagged "v<version>". Preview builds are 0.9.x pre-releases;
  release candidates are 1.0.0-rc.N. The build writes game/build_info.json (version, tag, commit,
  time), which the game shows in the main menu and logs at boot.

  Steps: (1) -Bump sets the version in project.godot and the bundled example mods' game_version,
  repacks the example mods and commits "Release <version>"; (2) checks the tree is clean, on main,
  pushed, and that project.godot matches -Version; (3) creates the annotated tag (refuses a tag that
  points elsewhere); (4) runs tools/build/package.ps1 -Archive (all four targets); (5) smoke-tests the
  packaged game (script check + boot to the title screen); (6) writes SHA256SUMS.txt; (7) pushes the
  tag and creates the GitHub release with the Windows exe, the zips/tarballs and the manifest.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/build/release.ps1 -Version 0.9.0 -Bump -Prerelease -NotesFile notes.md
  powershell -ExecutionPolicy Bypass -File tools/build/release.ps1 -Version 0.9.0 -DryRun
#>
param(
	[Parameter(Mandatory = $true)][string]$Version,
	[switch]$Bump,
	[switch]$Prerelease,
	[string]$NotesFile = "",
	[switch]$DryRun,
	[string]$Repo = "adambennett/PokeMMA",
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe",
	[string]$Gh = "C:\Program Files\GitHub CLI\gh.exe"
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $root
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
function Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Fail($m) { Write-Host "release: $m" -ForegroundColor Red; exit 1 }

if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$') { Fail "version '$Version' is not X.Y.Z or X.Y.Z-label.N" }
$tag = "v$Version"
$proj = Join-Path $root "game\project.godot"

if ($Bump) {
	Step "Setting version $Version"
	if ((git status --porcelain).Length -gt 0) { Fail "working tree not clean; commit or stash first" }
	$txt = Get-Content $proj -Raw
	$txt = [regex]::Replace($txt, 'config/version="[^"]*"', "config/version=""$Version""")
	[System.IO.File]::WriteAllText($proj, $txt)
	# example mods target this game version (0.x: same minor; 1.x+: same major)
	$base = ($Version -split '-')[0]
	foreach ($m in Get-ChildItem (Join-Path $root "mods\examples") -Directory) {
		$mf = Join-Path $m.FullName "manifest.json"
		if (Test-Path $mf) {
			$mt = Get-Content $mf -Raw
			$mt = [regex]::Replace($mt, '"game_version"\s*:\s*"[^"]*"', """game_version"": ""$base""")
			[System.IO.File]::WriteAllText($mf, $mt)
		}
	}
	python (Join-Path $root "tools\mods\pack_mod.py") --examples
	if ($LASTEXITCODE -ne 0) { Fail "repacking the example mods failed" }
	git add -A game/project.godot mods/examples game/mods_examples
	git commit -q -m "Release $Version`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
	if ($LASTEXITCODE -ne 0) { Fail "commit failed" }
}

Step "Checking the repository"
if ((git status --porcelain).Length -gt 0) { Fail "working tree not clean" }
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne "main") { Fail "releases are cut from main (on '$branch')" }
$have = [regex]::Match((Get-Content $proj -Raw), 'config/version="([^"]*)"').Groups[1].Value
if ($have -ne $Version) { Fail "project.godot says '$have', not '$Version' (use -Bump)" }
$head = (git rev-parse HEAD).Trim()
$existing = (git rev-parse -q --verify "refs/tags/$tag" 2>$null)
if ($existing) {
	$tagged = (git rev-list -n 1 $tag).Trim()
	if ($tagged -ne $head) { Fail "tag $tag already points at $tagged, not HEAD $head" }
} elseif (-not $DryRun) {
	git tag -a $tag -m "Critterweight $Version"
}

Step "Building all targets"
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tools\build\package.ps1") -Archive
if ($LASTEXITCODE -ne 0) { Fail "package.ps1 failed" }
$dist = Join-Path $root "dist"
$exe = Join-Path $dist "Critterweight-windows-x64\Critterweight.exe"
if (-not (Test-Path $exe)) { Fail "no Windows executable in dist" }

Step "Smoke-testing the packaged game"
$smoke = Join-Path $env:TEMP "critterweight-release-$Version"
if (Test-Path $smoke) { Remove-Item -Recurse -Force $smoke }
New-Item -ItemType Directory -Force $smoke | Out-Null
$p = Start-Process -FilePath $exe -ArgumentList @("--headless", "--", "--user-root", $smoke, "--check") -PassThru -Wait -NoNewWindow -RedirectStandardOutput (Join-Path $smoke "check.log") -RedirectStandardError (Join-Path $smoke "check.err")
if ($p.ExitCode -ne 0) { Fail "packaged script check failed (exit $($p.ExitCode))" }
$boot = Join-Path $smoke "boot.json"
$p = Start-Process -FilePath $exe -ArgumentList @("--", "--user-root", $smoke, "--windowed", "--size", "1280x720", "--boot-report", $boot) -PassThru -Wait
if ($p.ExitCode -ne 0 -or -not (Test-Path $boot)) { Fail "packaged game did not boot to a menu (exit $($p.ExitCode))" }
$br = Get-Content $boot | ConvertFrom-Json
Write-Host ("   booted to '{0}' in {1} ms" -f $br.screen, $br.ms_since_start)

Step "Collecting assets"
$assets = @()
$namedExe = Join-Path $dist "Critterweight-$Version-windows-x64.exe"
Copy-Item $exe $namedExe -Force
$assets += $namedExe
foreach ($a in @("Critterweight-windows-x64.zip", "Critterweight-server-windows-x64.zip", "Critterweight-linux-x86_64.tar.gz", "Critterweight-server-linux-x86_64.tar.gz", "BUILD_MANIFEST.json")) {
	$f = Join-Path $dist $a
	if (Test-Path $f) {
		$renamed = Join-Path $dist ($a -replace '^Critterweight-', "Critterweight-$Version-")
		if ($a -ne "BUILD_MANIFEST.json") { Copy-Item $f $renamed -Force; $assets += $renamed } else { $assets += $f }
	}
}
$sums = Join-Path $dist "SHA256SUMS.txt"
($assets | ForEach-Object { "{0}  {1}" -f (Get-FileHash -Algorithm SHA256 $_).Hash.ToLower(), (Split-Path $_ -Leaf) }) | Set-Content -Encoding ascii $sums
$assets += $sums
$assets | ForEach-Object { Write-Host ("   {0}  {1:N0} MB" -f (Split-Path $_ -Leaf), ((Get-Item $_).Length / 1MB)) }

if ($DryRun) { Step "Dry run: not pushing the tag or creating the release"; exit 0 }

Step "Publishing $tag"
git push -q origin main
git push -q origin $tag
if ($LASTEXITCODE -ne 0) { Fail "pushing the tag failed" }
$args2 = @("release", "create", $tag) + $assets + @("-R", $Repo, "--title", "Critterweight $Version", "--verify-tag")
if ($NotesFile -ne "") { $args2 += @("--notes-file", $NotesFile) } else { $args2 += @("--notes", "Critterweight $Version ($head)") }
if ($Prerelease) { $args2 += "--prerelease" }
& $Gh @args2
if ($LASTEXITCODE -ne 0) { Fail "gh release create failed" }
Step "Done: https://github.com/$Repo/releases/tag/$tag"
