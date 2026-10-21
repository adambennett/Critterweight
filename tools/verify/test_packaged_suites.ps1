<#
.SYNOPSIS
  Negative tests for the packaged-suite runner. A tiny console fixture replaces Godot; this checks
  error handling, not gameplay. The runner still uses the normal shared test lock.
#>
param([Parameter(Mandatory = $true)][string]$Out)
$ErrorActionPreference = 'Stop'
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}
$outPath = [IO.Path]::GetFullPath($Out)
if (Test-Path -LiteralPath $outPath) { throw 'Choose a fresh evidence directory for the fixture run.' }
New-Item -ItemType Directory -Force $outPath | Out-Null
$fixture = Join-Path $outPath 'PackagedSuiteFixture.exe'
$code = @'
using System;
using System.IO;
public static class PackagedSuiteFixture {
    public static int Main(string[] args) {
        string suite = "", output = "";
        for (int i = 0; i + 1 < args.Length; ++i) {
            if (args[i] == "--test") suite = args[i + 1];
            if (args[i] == "--test-out") output = args[i + 1];
        }
        if (output.Length == 0) return 8;
        if (suite == "stale") return 0;
        string total = suite == "empty" ? "0" : "1";
        File.WriteAllText(output, "{\"summary\":\"verification-tool fixture\",\"total\":" + total + ",\"failed\":0,\"skipped\":0}");
        if (suite == "stderr") Console.Error.WriteLine("SCRIPT ERROR: intentional verification-tool fixture");
        return suite == "exit" ? 7 : 0;
    }
}
'@
Add-Type -TypeDefinition $code -OutputAssembly $fixture -OutputType ConsoleApplication
$runner = Join-Path $PSScriptRoot 'packaged_suites.ps1'
$report = @()
foreach ($case in @('success', 'exit', 'stderr', 'stale', 'empty')) {
    # The space is deliberate: both the executable's result path and output directory must work.
    $caseOut = Join-Path $outPath ("case $case")
    New-Item -ItemType Directory -Force $caseOut | Out-Null
    if ($case -eq 'stale') {
        '{"summary":"old success must be removed","total":1,"failed":0,"skipped":0}' |
            Set-Content -LiteralPath (Join-Path $caseOut 'packaged-headless-stale-results.json') -Encoding UTF8
    }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Out $caseOut -Exe $fixture -Headless $case
    $result = $LASTEXITCODE
    $expectedSuccess = $case -eq 'success'
    $ok = (($result -eq 0) -eq $expectedSuccess)
    $report += [ordered]@{ case = $case; expected_success = $expectedSuccess; exit_code = $result; passed = $ok }
    Write-Host ("runner fixture {0}: {1} (exit {2})" -f $case, $(if ($ok) { 'PASS' } else { 'FAIL' }), $result)
}
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outPath 'runner-tests.json') -Encoding UTF8
if (@($report | Where-Object { -not $_.passed }).Count -gt 0) { exit 1 }
exit 0
