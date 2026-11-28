#!/usr/bin/env bash
# Network rules of the RADE engine (engine/ps/07-checks.ps1; the Administrator, 2026-11-17): a Power Automate address
# from Config is used only on the host and port of the step's own fixed address (the check, the step run and the hand
# step), and no web request of the engine sends the Windows sign-in to the address it asks (only the proxy gets it).
# The functions are cut out of the source and run in pwsh; the last check reads every engine file.
# Network: none.
# Writes: temporary files, deleted on exit.
# Credentials: none.
# Run: tests/net_rules_test.sh (scripts/check.local.sh runs it in both lanes). Needs pwsh 7. Pass = "NETRULES pass".
set -euo pipefail
cd "$(dirname "$0")/.."
src=engine/ps/07-checks.ps1
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
awk '/^function Test-SameHost/{on=1} on{print} on&&/^}/{exit}' "$src" > "$t/host.ps1"
cat >> "$t/host.ps1" <<'P'
$f = 'https://make.powerautomate.com/environments'
# Refused: another host, http, a longer host, no address, another port, the fixed host only as a user name, a host
# with a dot at the end. A blank fixed address refuses everything.
$bad = @('https://example.com/x', 'http://make.powerautomate.com/x', 'https://make.powerautomate.com.example.com/x', 'not a url', '',
  'https://make.powerautomate.com:8443/x', 'https://make.powerautomate.com@example.com/x', 'https://make.powerautomate.com./x') | Where-Object { Test-SameHost $_ $f }
if (Test-SameHost 'https://make.powerautomate.com/' '') { $bad = @($bad) + 'blank fixed address' }
$good = @('https://make.powerautomate.com/other', 'https://MAKE.powerautomate.com/', 'https://make.powerautomate.com:443/x', 'HTTPS://make.powerautomate.com/x') | Where-Object { -not (Test-SameHost $_ $f) }
if (@($bad).Count -or @($good).Count) { 'WRONG ' + (@($bad) + @($good) -join ' '); exit 1 }
'HOSTOK'
P
fail=0
[ -s "$t/host.ps1" ] && [ "$(pwsh -NoProfile -File "$t/host.ps1" 2>&1)" = "HOSTOK" ] || { echo "FAIL host rule (Test-SameHost)"; fail=1; }
# Get-FlowPortal, run: a saved address on the fixed host is used; one on another host is not, and is reported.
{ cat "$t/host.ps1" | sed '/^\$f = /,$d'; awk '/^function Get-FlowPortal/{on=1} on{print} on&&/^}/{exit}' "$src"; cat <<'P'
function Get-ConfigFile([string]$Base, [string]$Name) { return (Join-Path $Base $Name) }
$script:appSteps = @('a'); $steps = @{ a = @{ Url = 'https://make.powerautomate.com/'; UrlConfig = 'flow.txt' } }
$d = Join-Path ([IO.Path]::GetTempPath()) ('nr' + [guid]::NewGuid().ToString('N')); $null = New-Item -ItemType Directory -Path $d
Set-Content -LiteralPath (Join-Path $d 'flow.txt') -Value 'https://make.powerautomate.com/environments/x'
$a = Get-FlowPortal $d
Set-Content -LiteralPath (Join-Path $d 'flow.txt') -Value 'https://evil.example/'
$b = Get-FlowPortal $d
Remove-Item -LiteralPath $d -Recurse -Force
if ($a.Url -eq 'https://make.powerautomate.com/environments/x' -and -not $a.Refused -and $b.Url -eq 'https://make.powerautomate.com/' -and $b.Refused) { 'PORTALOK' } else { 'WRONG' }
P
} > "$t/portal.ps1"
[ "$(pwsh -NoProfile -File "$t/portal.ps1" 2>&1)" = "PORTALOK" ] || { echo "FAIL Get-FlowPortal uses or hides a saved address on another host"; fail=1; }
# Get-WebRequest, run: the request it gives back has the sign-in off and no credentials for the address, and carries the
# user agent and the timeout. Nothing is sent (the request is only made, never started).
# Use-TlsFloor (engine/ps/03-files.ps1; fleet v2) is copied too: after it, TLS 1.2 is on and SSL 3, TLS 1.0 and 1.1 are off.
{ awk '/^function Use-TlsFloor/{on=1} on{print} on&&/^}/{exit}' engine/ps/03-files.ps1; awk '/^function Get-WebRequest/{on=1} on{print} on&&/^}/{exit}' "$src"; cat <<'P'
$webAgent = 'agent-of-the-test'
$r = Get-WebRequest 'https://example.invalid/x' 4321
$p = [Net.ServicePointManager]::SecurityProtocol
$tlsOk = ($p -band [Net.SecurityProtocolType]::Tls12) -and -not ($p -band ([Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Ssl3))
if ($tlsOk -and -not $r.UseDefaultCredentials -and $null -eq $r.Credentials -and $r.UserAgent -eq $webAgent -and $r.Timeout -eq 4321) { 'REQUESTOK' } else { 'WRONG' }
P
} > "$t/request.ps1"
[ "$(pwsh -NoProfile -File "$t/request.ps1" 2>&1)" = "REQUESTOK" ] || { echo "FAIL Get-WebRequest: the sign-in is not off, the agent or timeout is not set, or TLS 1.2 is not the floor"; fail=1; }
# Every engine file: one place makes web requests (Get-WebRequest; the download's WebClient sets the sign-in off itself),
# no line turns the sign-in on, and only a proxy gets credentials.
all="engine/rade_ui.ps1 engine/ps/*.ps1 engine/ps/window/*.ps1"
# shellcheck disable=SC2086
if grep -nE 'UseDefaultCredentials *= *\$true' $all || grep -nE '\.Credentials *=' $all | grep -v 'Proxy\.Credentials' \
   || [ "$(grep -hc 'WebRequest\]::Create' $all | awk '{s+=$1} END {print s+0}')" != 1 ] \
   || [ "$(grep -hc 'New-Object System\.Net\.WebClient' $all | awk '{s+=$1} END {print s+0}')" != 0 ]; then
  echo "FAIL an engine web request can send the Windows sign-in to the address (or is made outside Get-WebRequest)"; fail=1
fi
for fn in Test-WebReach Get-NewerRound Get-NewerVersion Save-RoundDownload; do
  grep -h -A15 "^function $fn" $all | grep -q 'Get-WebRequest ' || { echo "FAIL $fn does not use Get-WebRequest"; fail=1; }
done
# The hand step and the step run check the host too.
grep -q 'Test-SameHost \$u \$fixed' engine/ps/window/ui-cards.ps1 && grep -q 'if (-not \$fixed) {' engine/ps/window/ui-cards.ps1 \
  && grep -q 'Test-SameHost \$v \$Step.Url' engine/ps/04-steps.ps1 \
  || { echo "FAIL the hand step or the step run uses a saved address on another host"; fail=1; }
[ "$fail" = 0 ] && echo "NETRULES pass" || { echo "NETRULES fail"; exit 1; }
