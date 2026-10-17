param([string]$ArtRoot='B:\Critterweight-art')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$expected=[IO.Path]::GetFullPath((Join-Path $ArtRoot 'test_root')).TrimEnd('\')
$resolved=(Resolve-Path -LiteralPath $expected).Path.TrimEnd('\')
if($resolved -ne 'B:\Critterweight-art\test_root' -or ((Get-Item -LiteralPath $resolved).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Full-suite cleanup root must be the real isolated B: art test_root'}
$defaultTemp=[Environment]::ExpandEnvironmentVariables([Environment]::GetEnvironmentVariable('TEMP','User'))
if($env:TEMP -ne $defaultTemp){throw 'Start this final check in a fresh shell with DEFAULT TEMP unchanged'}
$preservedTemp=$env:TEMP
. (Join-Path $PSScriptRoot 'art_env.ps1') -FullSuite
Set-ArtRuntimePaths
if($env:TEMP -ne $preservedTemp){throw 'TEMP changed before full suite'}
$started=Get-Date
$before=(Get-PSDrive C).Free
$commit=(git -C $repo rev-parse HEAD)
$log=Join-Path $ArtRoot 'captures\art-full-suite.log'
Write-Output "Full suite at $commit, test root $resolved, default TEMP preserved: $preservedTemp"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\dev\run_suite.ps1') -GamePath (Join-Path $repo 'game') -UserRoot $resolved -Log $log
$code=$LASTEXITCODE
[pscustomobject]@{commit=$commit;started=$started.ToString('o');finished=(Get-Date).ToString('o');exitCode=$code;userRoot=$resolved;defaultTemp=$preservedTemp;cFreeBefore=$before;cFreeAfter=(Get-PSDrive C).Free;log=$log} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $ArtRoot 'captures\art-full-suite-run.json') -Encoding utf8
Get-Content -LiteralPath $log -Tail 12
exit $code
