<#
.SYNOPSIS
  Re-export the saved playable-roster Blender sources into a separate evidence directory and
  compare each GLB with the shipped model. Never rebuilds or overwrites an artist's source.
#>
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [string]$Blender = 'B:\Blender\blender.exe',
    [string[]]$Ids = @('f_stoke', 'f_dredge', 'f_gusto', 'f_dozer', 'f_slurry', 'f_jitters', 'f_varga', 'f_knell')
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$outPath = [IO.Path]::GetFullPath($Out)
if ($outPath.Equals($repo, [StringComparison]::OrdinalIgnoreCase) -or
    $outPath.StartsWith($repo.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Re-export evidence must be outside the source checkout.'
}
foreach ($id in $Ids) {
    if ($id -notmatch '^f_[a-z0-9_]+$' -or $id.EndsWith('_legacy')) { throw "Invalid fighter id: $id" }
}
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
# Resolve the shared lock before the art environment redirects Blender's temporary files to B:.
$lockPath = Join-Path $env:TEMP 'critterweight_full_suite.lock'
. (Join-Path $repo 'tools\blender\art_env.ps1') -ArtRoot $outPath
Set-ArtRuntimePaths
New-Item -ItemType Directory -Force $outPath | Out-Null
$models = Join-Path $outPath 'creatures'
New-Item -ItemType Directory -Force $models | Out-Null
$lock = $null
$report = @()
try {
    $announced = $false
    while ($null -eq $lock) {
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch {
            if (-not $announced) { Write-Host 'Waiting for the shared test lock before Blender'; $announced = $true }
            Start-Sleep -Seconds 10
        }
    }
    foreach ($id in $Ids) {
        $source = Join-Path $repo "tools\blender\$id.blend"
        $shipped = Join-Path $repo "game\assets\models\creatures\$id.glb"
        $exported = Join-Path $models "$id.glb"
        $log = Join-Path $outPath "$id-export.log"
        & $Blender -b $source -t 2 --python-exit-code 1 --python (Join-Path $repo 'tools\blender\export_creature.py') -- --out $exported --scratch (Join-Path $outPath 'scratch') *> $log
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exported)) {
            Get-Content -LiteralPath $log -Tail 20
            throw "Saved-source export failed: $id"
        }
        $expected = (Get-FileHash -LiteralPath $shipped -Algorithm SHA256).Hash.ToLowerInvariant()
        $actual = (Get-FileHash -LiteralPath $exported -Algorithm SHA256).Hash.ToLowerInvariant()
        $report += [ordered]@{ fighter = $id; source_sha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant(); shipped_sha256 = $expected; exported_sha256 = $actual; identical = ($expected -eq $actual) }
        Write-Host ("{0}: saved-source export identical = {1}" -f $id, ($expected -eq $actual))
    }
} finally {
    if ($null -ne $lock) { $lock.Close() }
    $report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath 'export-determinism.json') -Encoding UTF8
}
if ($report.Count -ne $Ids.Count -or @($report | Where-Object { -not $_.identical }).Count -gt 0) { exit 1 }
exit 0
