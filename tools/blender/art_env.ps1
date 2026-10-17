# Dot-source for art jobs. Never use -FullSuite unless running run_suite.ps1 without a filter.
param([switch]$FullSuite,[string]$ArtRoot='B:\Critterweight-art')
if (-not $FullSuite) { $env:TEMP = "$ArtRoot\tmp"; $env:TMP = $env:TEMP }
$env:UV_CACHE_DIR = "$ArtRoot\tools\cache\uv"
$env:UV_PYTHON_INSTALL_DIR = "$ArtRoot\tools\python"
$env:UV_TOOL_DIR = "$ArtRoot\tools\uv-tools"
$env:UV_TOOL_BIN_DIR = "$ArtRoot\tools\bin"
$env:PIP_CACHE_DIR = "$ArtRoot\tools\cache\pip"
$env:npm_config_cache = "$ArtRoot\tools\cache\npm"
$env:PYTHONPYCACHEPREFIX = "$ArtRoot\tools\cache\pycache"
$env:BLENDER_USER_CONFIG = "$ArtRoot\tools\blender-profile\config"
$env:BLENDER_USER_SCRIPTS = "$ArtRoot\tools\blender-profile\scripts"
$env:BLENDER_USER_DATAFILES = "$ArtRoot\tools\blender-profile\datafiles"
$env:BLENDER_EXTENSIONS = "$ArtRoot\tools\blender-profile\extensions"
$env:DISABLE_TELEMETRY = 'true'
$env:BLENDER_HOST = '127.0.0.1'
$env:BLENDER_PORT = '9877'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
function Set-ArtRuntimePaths {
  $env:APPDATA = "$ArtRoot\tmp\AppData\Roaming"
  $env:LOCALAPPDATA = "$ArtRoot\tmp\AppData\Local"
  $env:XDG_CACHE_HOME = "$ArtRoot\tools\cache"
  $env:MESA_SHADER_CACHE_DIR = "$ArtRoot\tools\cache\mesa"
  foreach ($dir in @($env:APPDATA,$env:LOCALAPPDATA,$env:BLENDER_USER_CONFIG,$env:BLENDER_USER_SCRIPTS,$env:BLENDER_USER_DATAFILES,$env:BLENDER_EXTENSIONS)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
