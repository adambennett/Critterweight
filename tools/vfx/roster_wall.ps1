<#
.SYNOPSIS
  Before/after roster walls: the eight playable fighters lined up under arena lighting (front and
  back), captured with model_preview.gd from two checkouts, joined into one image per view.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/vfx/roster_wall.ps1 -Before B:\Critterweight-work\baseline-src -After B:\git\Critterweight -Out B:\Critterweight-work\v0.9.17\roster
#>
param(
	[Parameter(Mandatory = $true)][string]$Before,
	[Parameter(Mandatory = $true)][string]$After,
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Godot = "C:\Program Files (x86)\Godot\Godot_v4.5.1-stable_win64_console.exe",
	[string]$Extra = ""
)
$ErrorActionPreference = "Stop"
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
New-Item -ItemType Directory -Force $Out | Out-Null
$ids = @('f_stoke', 'f_dredge', 'f_gusto', 'f_dozer', 'f_slurry', 'f_jitters', 'f_varga', 'f_knell')
$creatures = ($ids | ForEach-Object { "res://content/core/creatures/$_.json" }) -join ','
foreach ($pair in @(@('before', $Before), @('after', $After))) {
	foreach ($view in @(@('front', '25'), @('back', '205'))) {
		$png = Join-Path $Out ("{0}_{1}.png" -f $pair[0], $view[0])
		$a = @('--path', (Join-Path $pair[1] 'game'), '--resolution', '1920x1080', '--script', 'res://src/view/model_preview.gd', '--',
			'--user-root', (Join-Path $Out ("user_" + $pair[0])), '--creatures', $creatures, '--spacing', '1.75', '--yaw', $view[1],
			'--hype', '0.6', '--capture', $png)
		if ($Extra -ne "") { $a += $Extra.Split(' ') }
		& $Godot @a *> (Join-Path $Out ("{0}_{1}.log" -f $pair[0], $view[0]))
		if (-not (Test-Path $png)) { throw "capture failed: $png" }
		Write-Host "captured $png"
	}
}
