<#
.SYNOPSIS
  Packaged dedicated server + packaged clients on this machine over LOOPBACK (NET-01/02/08):
  the server starts from a config file, two scripted clients play a duel to the end, a windowed
  spectator saves a rendered frame of the online match, the token-authenticated TCP admin
  (127.0.0.1) answers `status`, and `shutdown` stops the server gracefully with exit code 0.
.DESCRIPTION
  Writes logs, client results, the capture and steps.json ([{name, status, detail}]) into -Out.
  Called by run_verification.ps1; can also run on its own. LOOPBACK ONLY: this proves the packaged
  builds and the session flow on one PC, not internet play (docs/NETWORKING.md section 11).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/verify/net_session_check.ps1 -Out $env:TEMP\cw-net
#>
param(
	[string]$Dist = "",
	[string]$Out = "",
	[string]$UserRoot = "",
	[int]$Port = 0,
	[switch]$ShowWindows
)
$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($Dist -eq "") { $Dist = Join-Path $root "dist" }
if ($Out -eq "") { $Out = Join-Path $env:TEMP ("critterweight-net-" + (Get-Date -Format "yyyyMMdd-HHmmss")) }
if ($UserRoot -eq "") { $UserRoot = Join-Path $Out "users" }
New-Item -ItemType Directory -Force $Out | Out-Null
New-Item -ItemType Directory -Force $UserRoot | Out-Null
$steps = @()
$procs = @()

function Step($name, $status, $detail) {
	$script:steps += [ordered]@{ name = $name; status = $status; detail = $detail }
	$color = @{ pass = "Green"; fail = "Red"; skipped = "Yellow" }[$status]
	Write-Host ("[{0}] {1} - {2}" -f $status.ToUpper(), $name, $detail) -ForegroundColor $color
}

function Finish() {
	foreach ($p in $script:procs) {
		if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
	}
	ConvertTo-Json -InputObject @($script:steps) -Depth 4 | Set-Content (Join-Path $Out "steps.json")
	exit @($script:steps | Where-Object { $_.status -eq "fail" }).Count
}

function Q([string]$s) { if ($s -match '\s') { '"' + $s + '"' } else { $s } }

## Background verification stays hidden; interactive users can request the spectator with -ShowWindows.
function Start-Game($file, $argList, [switch]$Visible) {
	$quoted = @($argList | ForEach-Object { Q ([string]$_) })
	if ($Visible -and $ShowWindows) { $p = Start-Process -FilePath $file -ArgumentList $quoted -PassThru }
	else { $p = Start-Process -FilePath $file -ArgumentList $quoted -PassThru -WindowStyle Hidden }
	$null = $p.Handle   # keeps the handle open so ExitCode is available after the process exits
	$script:procs += $p
	return $p
}

function ReadJson($path) {
	if (-not (Test-Path $path)) { return $null }
	try { return (Get-Content $path -Raw | ConvertFrom-Json) } catch { return $null }
}

## One TCP admin session: banner, AUTH, then each command (answers end with a "." line).
function Admin($port, $token, $commands) {
	$text = ""
	try {
		$t = New-Object Net.Sockets.TcpClient
		$t.Connect("127.0.0.1", $port)
		$s = $t.GetStream()
		$s.ReadTimeout = 8000
		$w = New-Object IO.StreamWriter($s)
		$w.AutoFlush = $true
		$w.NewLine = "`n"
		$r = New-Object IO.StreamReader($s)
		$text += $r.ReadLine() + "`n"
		$w.WriteLine("AUTH $token")
		$text += $r.ReadLine() + "`n"
		foreach ($c in $commands) {
			$w.WriteLine($c)
			while ($true) {
				$x = $r.ReadLine()
				if ($null -eq $x -or $x -eq ".") { break }
				$text += $x + "`n"
			}
		}
		$t.Close()
	} catch { $text += "ERROR: " + $_.Exception.Message }
	return $text
}

$exe = Join-Path $Dist "Critterweight-windows-x64\Critterweight.exe"
if (-not (Test-Path $exe)) { Step "packaged game executable" "fail" "missing $exe"; Finish }
$srvExe = Join-Path $Dist "Critterweight-server-windows-x64\CritterweightServer.exe"
$srvKind = "server package"
if (-not (Test-Path $srvExe)) { $srvExe = $exe; $srvKind = "game executable, no server package" }
if ($Port -eq 0) { $Port = 47000 + 2 * (Get-Random -Minimum 0 -Maximum 900) }
$token = "verify-" + [guid]::NewGuid().ToString("N")

# server config + a one-entry playlist (short duel), TCP admin on port+1, no stdin console
$pl = Join-Path $Out "verify_duel.json"
[IO.File]::WriteAllText($pl, '{"id": "verify_duel", "name": "Verification duel", "voting": {"enabled": false, "candidates": 1}, "entries": [{"id": "duel", "rules": "duel", "arena": "the_gullet", "weight": 1, "rules_override": {"rounds": 1, "round_time": 60}}]}')
$cfg = Join-Path $Out "server.cfg"
$cfgText = @"
[server]
name = Verification Server
port = $Port
max_players = 4
max_spectators = 2
lan_discovery = false
timeout = 10
[match]
playlist = $($pl.Replace('\', '/'))
lobby_time = 4
results_time = 3
bots = true
[admin]
console = false
port = $($Port + 1)
token = $token
"@
[IO.File]::WriteAllText($cfg, $cfgText)

# 1. dedicated server
# (release builds buffer the engine's --log-file; readiness comes from the server's status.json)
$srvLog = Join-Path $Out "server.log"
$srvStatus = Join-Path $UserRoot "server\server\status.json"
$srv = Start-Game $srvExe @("--headless", "--log-file", $srvLog, "--", "--server", "--config", $cfg, "--user-root", (Join-Path $UserRoot "server"))
$ready = $null
for ($i = 0; $i -lt 120; $i++) {
	Start-Sleep -Milliseconds 250
	$s0 = ReadJson $srvStatus
	if ($s0 -and $s0.state -eq "running") { $ready = $s0; break }
	if ($srv.HasExited) { break }
}
if (-not $ready) { Step "dedicated server start ($srvKind)" "fail" "no running status (exit $($srv.ExitCode)); see server.log"; Finish }
Step "dedicated server start ($srvKind)" "pass" ("'{0}' on UDP {1}, playlist {2}, pid {3}" -f $ready.name, $ready.port, $ready.playlist, $ready.pid)

# 2. two scripted packaged clients play the duel to the end; a windowed spectator saves a frame
$clients = @()
# fighters named as in test_net_multiprocess: the scripted attacker swings within 1.7 m of the target's
# root, which two large default fighters (Dozer vs Dozer) never reach - that duel timed out unresolved
foreach ($c in @(@{ n = "Alice"; s = "aggressive"; x = @("--creature", "f_stoke") }, @{ n = "Bob"; s = "passive"; x = @("--present", "--creature", "f_jitters") })) {
	$lc = $c.n.ToLower()
	$a = @("--headless", "--log-file", (Join-Path $Out "$lc.log"), "--", "--user-root", (Join-Path $UserRoot $lc), "--net-client",
		"--connect", "127.0.0.1:$Port", "--name", $c.n, "--script", $c.s, "--ready", "--stop-after-matches", "1", "--quit-after", "170",
		"--result", (Join-Path $Out "$lc.json")) + $c.x
	$clients += Start-Game $exe $a
}
$png = Join-Path $Out "capture_online_spectator.png"
$viewer = Start-Game $exe @("--log-file", (Join-Path $Out "viewer.log"), "--", "--user-root", (Join-Path $UserRoot "viewer"), "--windowed",
	"--size", "1600x900", "--connect", "127.0.0.1:$Port", "--name", "Viewer", "--spectate", "--capture", $png, "--capture-at", "16") -Visible
$deadline = (Get-Date).AddSeconds(200)
while ((Get-Date) -lt $deadline -and @($clients | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Milliseconds 500 }
$ra = ReadJson (Join-Path $Out "alice.json")
$rb = ReadJson (Join-Path $Out "bob.json")
$clientsClean = @($clients | Where-Object { -not $_.HasExited -or $_.ExitCode -ne 0 }).Count -eq 0
if ($clientsClean -and $ra -and $rb -and $ra.connected -and $rb.connected -and @($ra.results).Count -eq 1 -and @($rb.results).Count -eq 1 -and
	[int]$ra.results[0].winner_team -eq [int]$rb.results[0].winner_team) {
	$you = [int]$ra.matches[0].you
	$won = ([int]$ra.results[0].winner_team -eq [int]$ra.results[0].fighters[$you].team)
	Step "online duel, 2 packaged clients (LOOPBACK)" "pass" ("authoritative result reached both; attacker won: {0}; Alice hits {1}; Bob lowest health {2}; {3:N1} snapshots/s, interpolation {4:N0} ms, RTT {5:N1} ms" -f `
		$won, $ra.hits_dealt, $rb.my_health_min, [double]$ra.stats.snapshot_rate, [double]$ra.stats.interp_delay_ms, [double]$ra.stats.rtt_ms)
} else {
	Step "online duel, 2 packaged clients (LOOPBACK)" "fail" ("connected {0}/{1}, results {2}/{3}, clean exits {4}; see alice.log, bob.log, server.log" -f `
		$(if ($ra) { $ra.connected } else { "no result" }), $(if ($rb) { $rb.connected } else { "no result" }), @($ra.results).Count, @($rb.results).Count, $clientsClean)
}
$vd = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $vd -and -not $viewer.HasExited) { Start-Sleep -Milliseconds 500 }
$joined = (Test-Path (Join-Path $Out "viewer.log")) -and (Select-String -Path (Join-Path $Out "viewer.log") -Pattern "joined '" -Quiet)
if ((Test-Path $png) -and $joined -and $viewer.HasExited -and $viewer.ExitCode -eq 0) { Step "online spectator frame (windowed packaged client)" "pass" (Split-Path $png -Leaf) }
else { Step "online spectator frame (windowed packaged client)" "fail" "capture $(Test-Path $png), joined $joined (exit $($viewer.ExitCode))" }

# 3. token-authenticated TCP admin (127.0.0.1 only) and graceful shutdown
$st = Admin ($Port + 1) $token @("status")
if ($st -match "OK" -and $st -match "phase") { Step "server TCP admin (token, 127.0.0.1)" "pass" (($st -split "`n" | Where-Object { $_ -match "phase" } | Select-Object -First 1)) }
else { Step "server TCP admin (token, 127.0.0.1)" "fail" $st }
$bad = Admin ($Port + 1) "wrong-token-0000000000" @()
if ($bad -match "ERR auth") { Step "server TCP admin refuses a wrong token" "pass" "ERR auth" } else { Step "server TCP admin refuses a wrong token" "fail" $bad }
Admin ($Port + 1) $token @("shutdown Verification finished") | Out-Null
$sd = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $sd -and -not $srv.HasExited) { Start-Sleep -Milliseconds 250 }
if ($srv.HasExited -and $srv.ExitCode -eq 0) { Step "server graceful shutdown" "pass" "exit code 0" }
else { Step "server graceful shutdown" "fail" $(if ($srv.HasExited) { "exit code $($srv.ExitCode)" } else { "still running after 20 s" }) }

# 4. no script or logged errors in any process (logs are complete once the processes exited)
Start-Sleep -Seconds 1
$errs = @()
$logs = @("server.log", "alice.log", "bob.log", "viewer.log") | ForEach-Object { Join-Path $Out $_ }
$logs += Join-Path $UserRoot "server\logs\server.log"
foreach ($path in $logs) {
	if (Test-Path $path) { $errs += @(Select-String -Path $path -Pattern "SCRIPT ERROR|\[ERROR\]" | ForEach-Object { "$(Split-Path $path -Leaf): $($_.Line)" }) }
}
if ($errs.Count -eq 0) { Step "no errors logged (server, clients, spectator)" "pass" "$($logs.Count) logs scanned" }
else { Step "no errors logged (server, clients, spectator)" "fail" (($errs | Select-Object -First 3) -join " | ") }
Finish
