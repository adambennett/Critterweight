<#
.SYNOPSIS
  The rendered evidence of a release in one reserved batch (docs/evidence/verification/<version>/):
  the ability-effects showcase of every fighter, the before/after roster walls, a single fighter's
  before/after model captures, the Varga skin capture and the Settings > Graphics screen. Windowed
  Godot (console build), BelowNormal, under the machine-wide test lock and reservation
  (tools/dev/run_suite.ps1), so test runs of other checkouts wait instead of sharing the GPU/CPU.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/release_captures.ps1 -Before B:\Critterweight-work\baseline-src -After B:\git\Critterweight -Out B:\Critterweight-work\v0.9.17\captures
#>
param(
	[Parameter(Mandatory = $true)][string]$Before,
	[Parameter(Mandatory = $true)][string]$After,
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Single = "f_stoke",
	[string]$Steps = "showcase,roster,single,skin,settings",
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
$reserve = Join-Path $env:TEMP "critterweight_release.reserve"
Set-Content -LiteralPath $reserve -Value "release captures $PID"
$lock = $null
$lockPath = Join-Path $env:TEMP "critterweight_full_suite.lock"
while ($null -eq $lock) {
	try { $lock = [System.IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
	catch { Write-Host "waiting for the test lock"; Set-Content -LiteralPath $reserve -Value "release captures $PID"; Start-Sleep -Seconds 10 }
}
$want = $Steps.Split(",")
New-Item -ItemType Directory -Force $Out | Out-Null

function Run-Godot([string]$name, [string[]]$a) {
	$log = Join-Path $Out ($name + ".log")
	Write-Host "==> $name"
	& $Godot @a *> $log
	Write-Host ("    exit {0}" -f $LASTEXITCODE)
}

try {
	if ($want -contains "showcase") {
		$dir = Join-Path $Out "showcase"
		$root = Join-Path $Out "user_showcase"
		Run-Godot "showcase" @("--path", (Join-Path $After "game"), "--resolution", "1600x900", "--", "--user-root", $root,
			"--test", "test_vfx_showcase", "--vfx-showcase", $dir)
	}
	if ($want -contains "roster") {
		& powershell -ExecutionPolicy Bypass -File (Join-Path $After "tools\vfx\roster_wall.ps1") -Before $Before -After $After -Out (Join-Path $Out "roster") -Godot $Godot
	}
	if ($want -contains "single") {
		foreach ($pair in @(@("before", $Before), @("after", $After))) {
			foreach ($view in @(@("front", "25"), @("back", "205"))) {
				$png = Join-Path $Out ("single\{0}_{1}_{2}.png" -f $Single, $pair[0], $view[0])
				New-Item -ItemType Directory -Force (Split-Path $png) | Out-Null
				Run-Godot ("single_{0}_{1}" -f $pair[0], $view[0]) @("--path", (Join-Path $pair[1] "game"), "--resolution", "1920x1080",
					"--script", "res://src/view/model_preview.gd", "--", "--user-root", (Join-Path $Out ("user_single_" + $pair[0])),
					"--creatures", "res://content/core/creatures/$Single.json", "--yaw", $view[1], "--hype", "0.6", "--capture", $png)
			}
		}
	}
	if ($want -contains "skin") {
		Run-Godot "varga_skin" @("--path", (Join-Path $After "game"), "--resolution", "1600x900", "--", "--user-root", (Join-Path $Out "user_skin"),
			"--test", "test_varga_skin_capture", "--varga-skin-capture", (Join-Path $Out "varga_skin"))
	}
	if ($want -contains "settings") {
		$png = Join-Path $Out "ui\settings_graphics.png"
		New-Item -ItemType Directory -Force (Split-Path $png) | Out-Null
		Run-Godot "settings" @("--path", (Join-Path $After "game"), "--resolution", "1920x1080", "--", "--user-root", (Join-Path $Out "user_ui"),
			"--ui-screen", "settings", "--ui-tab", "graphics", "--capture", $png, "--capture-at", "2.0")
	}
} finally {
	$lock.Close()
	Remove-Item -LiteralPath $reserve -ErrorAction SilentlyContinue
}
Write-Host "done: $Out"
