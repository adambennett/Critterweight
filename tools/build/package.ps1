<#
.SYNOPSIS
  Builds the Critterweight release packages (Windows/Linux game, Windows/Linux dedicated server).
.DESCRIPTION
  1. Re-imports assets (refreshes the class cache), 2. checks every script compiles,
  3. optionally runs the automated test suite, 4. exports each target with the official
  Godot 4.5.1 export templates, 5. copies player/server docs and licences, 6. writes
  dist/BUILD_MANIFEST.json (version, git revision, file sizes, SHA-256), 7. optionally archives
  (Windows: .zip, Linux: .tar.gz with executable permissions preserved).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/build/package.ps1 -Archive
#>
param(
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe",
	[string[]]$Targets = @("Windows Desktop", "Linux", "Windows Server", "Linux Server"),
	[switch]$RunTests,
	[switch]$Archive,
	[string]$OutDir = ""
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$game = Join-Path $root "game"
if ($OutDir -eq "") { $OutDir = Join-Path $root "dist" }
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force $OutDir | Out-Null
$buildLogs = Join-Path $OutDir "build-logs"
New-Item -ItemType Directory -Force $buildLogs | Out-Null
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

$layout = @{
	"Windows Desktop" = @{ dir = "Critterweight-windows-x64"; file = "Critterweight.exe"; kind = "game"; os = "windows" }
	"Linux" = @{ dir = "Critterweight-linux-x86_64"; file = "Critterweight.x86_64"; kind = "game"; os = "linux" }
	"Windows Server" = @{ dir = "Critterweight-server-windows-x64"; file = "CritterweightServer.exe"; kind = "server"; os = "windows" }
	"Linux Server" = @{ dir = "Critterweight-server-linux-x86_64"; file = "CritterweightServer.x86_64"; kind = "server"; os = "linux" }
}

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

Step "Importing assets"
& $Godot --headless --path $game --log-file (Join-Path $buildLogs "import.log") --import 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Asset import failed ($LASTEXITCODE)" }

Step "Checking scripts"
& $Godot --headless --path $game --log-file (Join-Path $buildLogs "check.log") -- --user-root (Join-Path $buildLogs "check-user") --check
if ($LASTEXITCODE -ne 0) { throw "Script check failed ($LASTEXITCODE scripts)" }

if ($RunTests) {
	Step "Running automated tests"
	& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tools/dev/run_suite.ps1") -Godot $Godot
	if ($LASTEXITCODE -ne 0) { throw "$LASTEXITCODE test(s) failed" }
}

$version = (Select-String -Path (Join-Path $game "project.godot") -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
$rev = (git -C $root rev-parse --short HEAD).Trim()
$dirty = (git -C $root status --porcelain).Length -gt 0
$tagAtHead = (git -C $root tag --points-at HEAD | Where-Object { $_ -eq "v$version" } | Select-Object -First 1)
# build stamp the game shows (main menu, logs): written for the export only, removed afterwards
$buildInfo = Join-Path $game "build_info.json"
[ordered]@{ version = $version; tag = "$tagAtHead"; commit = $rev; dirty = $dirty; built_at = (Get-Date).ToString("s") } |
	ConvertTo-Json | Set-Content -Encoding ascii $buildInfo
$manifest = [ordered]@{ product = "Critterweight"; version = $version; git_revision = $rev; working_tree_dirty = $dirty;
	built_at = (Get-Date).ToString("s"); godot = (& $Godot --version).Trim(); targets = @() }

foreach ($t in $Targets) {
	$l = $layout[$t]
	if ($null -eq $l) { throw "Unknown export target '$t'" }
	$dest = [System.IO.Path]::GetFullPath((Join-Path $OutDir $l.dir))
	if (-not $dest.StartsWith($OutDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Export directory escapes output root: $dest" }
	if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
	New-Item -ItemType Directory -Force $dest | Out-Null
	$exe = Join-Path $dest $l.file
	Step "Exporting $t -> $exe"
	& $Godot --headless --path $game --log-file (Join-Path $buildLogs ($l.dir + ".log")) --export-release $t $exe 2>&1 | Where-Object { $_ -match "ERROR|error|WARNING" } | ForEach-Object { Write-Host "   $_" }
	if ($LASTEXITCODE -ne 0) { throw "Export of '$t' failed ($LASTEXITCODE)" }
	if (-not (Test-Path $exe)) { throw "Export of '$t' produced no binary" }
	# documentation and licences shipped with every package
	foreach ($doc in @("README.md", "docs/THIRD_PARTY.md", "docs/CREDITS.md")) {
		$src = Join-Path $root $doc
		if (Test-Path $src) { Copy-Item $src $dest }
	}
	Copy-Item (Join-Path $game "assets/fonts/OFL.txt") (Join-Path $dest "OFL-Barlow.txt") -ErrorAction SilentlyContinue
	Copy-Item (Join-Path $game "assets/fonts/Bungee-OFL.txt") (Join-Path $dest "OFL-Bungee.txt") -ErrorAction SilentlyContinue
	if ($l.kind -eq "server") {
		foreach ($doc in @("docs/SERVER.md")) { $src = Join-Path $root $doc; if (Test-Path $src) { Copy-Item $src $dest } }
		$cfgs = Join-Path $game "server"
		if (Test-Path $cfgs) { Copy-Item -Recurse $cfgs (Join-Path $dest "config-examples") }
	} else {
		foreach ($doc in @("docs/PLAYER_GUIDE.md", "docs/MODDING.md", "docs/AI_LAB.md")) { $src = Join-Path $root $doc; if (Test-Path $src) { Copy-Item $src $dest } }
		# editable sources of the bundled example mods (the packed .critmod copies are inside the game)
		$ex = Join-Path $root "mods\examples"
		if (Test-Path $ex) { Copy-Item -Recurse $ex (Join-Path $dest "example-mod-sources") }
		$packer = Join-Path $root "tools\mods\pack_mod.py"
		if (Test-Path $packer) { Copy-Item $packer (Join-Path $dest "example-mod-sources") }
	}
	$files = @()
	foreach ($f in Get-ChildItem -Recurse -File $dest) {
		$files += [ordered]@{ path = $f.FullName.Substring($dest.Length + 1).Replace("\", "/"); bytes = $f.Length; sha256 = (Get-FileHash -Algorithm SHA256 $f.FullName).Hash.ToLower() }
	}
	$entry = [ordered]@{ target = $t; folder = $l.dir; binary = $l.file; files = $files }
	if ($Archive) {
		if ($l.os -eq "windows") {
			$zip = Join-Path $OutDir ($l.dir + ".zip")
			if (Test-Path $zip) { Remove-Item $zip }
			Compress-Archive -Path $dest -DestinationPath $zip
			$entry.archive = (Split-Path -Leaf $zip)
		} else {
			$tgz = Join-Path $OutDir ($l.dir + ".tar.gz")
			python (Join-Path $PSScriptRoot "make_tar.py") $dest $tgz $l.file
			$entry.archive = (Split-Path -Leaf $tgz)
		}
		$entry.archive_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $OutDir $entry.archive)).Hash.ToLower()
	}
	$manifest.targets += $entry
}

Remove-Item $buildInfo -ErrorAction SilentlyContinue
$manifest.tag = "$tagAtHead"
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutDir "BUILD_MANIFEST.json")
Step "Done. Manifest: $(Join-Path $OutDir 'BUILD_MANIFEST.json')"
