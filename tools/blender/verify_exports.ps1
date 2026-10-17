param([string]$ArtRoot='B:\Critterweight-art')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$manifest=Get-Content -Raw (Join-Path $PSScriptRoot 'model_manifest.json') | ConvertFrom-Json
$hashes=@{}
foreach($entry in $manifest){$hashes[$entry.id]=(Get-FileHash -LiteralPath (Join-Path $repo ('game/assets/models/'+$entry.out)) -Algorithm SHA256).Hash}
& (Join-Path $PSScriptRoot 'rebuild.ps1')
$rows=@()
foreach($entry in $manifest){
 $file=Join-Path $repo ('game/assets/models/'+$entry.out)
 $sha=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
 $rows += [pscustomobject]@{id=$entry.id;source=if($entry.creature){'Blender'}else{'retained forge'};before=$hashes[$entry.id];after=$sha;byteIdentical=$sha -eq $hashes[$entry.id]}
}
$rows | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ArtRoot 'captures\export-determinism.json') -Encoding utf8
if(@($rows | Where-Object {-not $_.byteIdentical}).Count){throw 'Saved source export differs from the captured GLB; review and recapture changed models'}
Write-Output 'All saved-source exports byte-identical; ten retained GLBs unchanged.'
& node (Join-Path $PSScriptRoot 'audit_models.js') --out (Join-Path $ArtRoot 'captures\model-audit-final.json')
if($LASTEXITCODE -ne 0){throw 'GLB contract audit failed'}
