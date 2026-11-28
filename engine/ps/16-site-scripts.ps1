# RADE engine part 16, the site scripts of the checks (moved out of engine/ps/07-checks.ps1 to keep each file at 450
# lines or fewer; fleet v2 DEC 6): the sign-in block ($signInSize, Add-SignInSize), the rights check script
# ($rightsScript), Invoke-ChildScript (moved from part 07 in engine-v42), and the install record on the site
# (Get-MarkerArg, Get-SiteMark, Test-InstalledHere, Test-FirstInstall, $markerScript). Part 07 runs them (Invoke-Check,
# Write-SiteMarker); parts 13 and 14 use Add-SignInSize when they load, so this part comes right after part 07.
# Network: none when it loads; the child scripts it holds sign in to the saved site on the DAF SharePoint host (PnP).
# Writes: none when it loads; Invoke-ChildScript writes each child script to the temp folder and deletes it at the end;
# $markerScript writes the install record (one row of the app's own list on the site).
# Credentials: the interactive CAC sign-in of PnP (-UseWebLogin), in the child scripts.
# Joined into every bundle by engine/rade_build.py, right after part 07; Windows PowerShell 5.1.

<#
.SYNOPSIS
Runs an embedded child script as a child powershell.exe, the way steps run, and gives back its exit code and output lines.
.DESCRIPTION
No -ExecutionPolicy setting (fleet v2, DEC 3: Group Policy governs). The script is written to the Windows temp folder and
deleted at the end. With StageSeconds (R44 E4), RADE reads the output while the child runs: a line "STAGE <name>" starts a
stage, a stage that runs longer than StageSeconds stops the child (Stage then names it), and "STAGE none" ends the timed
stage. Without it, the output is read at the end (the test child of the policy check).
.PARAMETER Text
The script text.
.PARAMETER ArgText
The arguments after the script path.
.PARAMETER Seconds
The time limit of the whole child.
.PARAMETER Tick
A script block called about every 30 ms while the child runs (the window stays live), or $null.
.PARAMETER StageSeconds
The time limit of one stage, or 0 for no stage limit.
.OUTPUTS
@{ Exit; Lines; Why; Stage }: Stage is the stage that was stopped, or ''.
#>
function Invoke-ChildScript([string]$Text, [string]$ArgText, [int]$Seconds, [scriptblock]$Tick, [int]$StageSeconds = 0) {
  $exe = 'powershell.exe'
  if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { $exe = 'pwsh' }
  $runnersDir = Join-Path (Get-RadePath) 'runners'
  if (-not (Test-Path -LiteralPath $runnersDir -PathType Container)) { [void](New-Item -ItemType Directory -Path $runnersDir -Force) }
  $tmp = Join-Path $runnersDir ('@@PREFIX@@-check-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
  $res = @{ Exit = -1; Lines = @(); Why = ''; Stage = '' }
  try {
    [System.IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding $true))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '-NoProfile -File "' + $tmp + '"' + $(if ($ArgText) { ' ' + $ArgText } else { '' })
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    # A PowerShell started with -ExecutionPolicy hands that setting to its child processes in this variable (an old RADE
    # shortcut sets "Bypass"): take only that value out, as Get-StepStartInfo does, else a check would say "ran" where a
    # step cannot. Any other value a person set stays.
    if ($psi.EnvironmentVariables['PSExecutionPolicyPreference'] -ceq 'Bypass') { $psi.EnvironmentVariables.Remove('PSExecutionPolicyPreference') }
    $p = [System.Diagnostics.Process]::Start($psi)
    $script:child = $p   # Exit stops a check too (review R17)
    $errTask = $p.StandardError.ReadToEndAsync(); $got = New-Object System.Collections.Generic.List[string]
    $outTask = $null; $rd = $null
    if ($StageSeconds -gt 0) { $rd = $p.StandardOutput.ReadLineAsync() } else { $outTask = $p.StandardOutput.ReadToEndAsync() }
    $deadline = (Get-Date).AddSeconds($Seconds); $stage = ''; $stageEnd = [datetime]::MaxValue
    while ($true) {
      while ($rd -and $rd.IsCompleted) {   # the lines that are there now; a STAGE line starts a stage and its time limit
        $l = $rd.Result; if ($null -eq $l) { $rd = $null; break }
        $got.Add($l); if ($l -match '^STAGE (.+)$') { $stage = $Matches[1].Trim(); $stageEnd = (Get-Date).AddSeconds($StageSeconds)
          if ($stage -eq 'none') { $stage = '' } }   # "STAGE none": no stage runs (engine-v43)
        $rd = $p.StandardOutput.ReadLineAsync() }
      if ($p.WaitForExit(30)) { break }
      if ($Tick) { & $Tick }
      if ((Get-Date) -gt $deadline) { try { $p.Kill() } catch { $null = $_ }; $res.Why = 'it ran longer than ' + $Seconds + ' seconds'; break }
      if ($stage -and (Get-Date) -gt $stageEnd) { try { $p.Kill() } catch { $null = $_ }   # it ended already
        $res.Stage = $stage; $res.Why = 'its stage "' + $stage + '" ran longer than ' + $StageSeconds + ' seconds'; break }
    }
    $p.WaitForExit()
    while ($rd) { $l = $rd.Result; if ($null -eq $l) { break }; $got.Add($l); $rd = $p.StandardOutput.ReadLineAsync() }   # the last lines after the end
    $res.Exit = $p.ExitCode
    $all = $(if ($outTask) { @(([string]$outTask.Result) -split "`r?`n") } else { @($got) })
    $res.Lines = @($all | Where-Object { $_ })
    if (-not $res.Why -and ([string]$errTask.Result).Trim()) { $res.Why = 'it wrote error output' }
  } catch { $res.Why = $_.Exception.GetType().Name }
  finally { $script:child = $null; try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } } catch { $null = $_ } }
  return $res
}
# engine-v43 S1 (the Administrator, 2026-11-26): the time limit of the sign-in stage of the rights, install record and Restore children
# (Back up keeps its own stage limit, $toolStageSeconds). A frozen sign-in then ends with its stage named: no force close.
$signInStageSeconds = 180
<#
.SYNOPSIS
Puts the sign-in lines of a child (SIGNIN, SIGNIN-WIN) into the run log with RADE's host, and gives the short note.
.DESCRIPTION
engine-v43 S2, S3: each line goes to the run log as "<name> <line> host=<host>" ($env:RADE_HOST: ise, child, shortcut or
console; set by part 09). The note is the SIGNIN line with the host, else (a sign-in that did not finish) the last
SIGNIN-WIN line with the host, else ''.
.PARAMETER Name
The child's name in the log (for example "Rights check").
.PARAMETER Lines
The child's output lines.
.OUTPUTS
The note, or ''.
#>
function Get-SignInNote([string]$Name, [object[]]$Lines) {
  $hostTag = ' host=' + $(if ($env:RADE_HOST) { $env:RADE_HOST } else { 'unknown' })
  $s = @($Lines | Where-Object { [string]$_ -match '^SIGNIN(-WIN)? ' })
  foreach ($l in $s) { Add-RunLog ($Name + ' ' + $l + $hostTag) }
  $done = @($s | Where-Object { [string]$_ -match '^SIGNIN seconds=' } | Select-Object -First 1)
  if ($done.Count) { return ([string]$done[0] + $hostTag) }
  if ($s.Count) { return ([string]$s[-1] + $hostTag) }
  return ''
}
# Gives the words for a stage of the Back up child ("signin", "site", "list <n>"). Takes the stage and the list titles.
function Get-StageText([string]$Stage, [object[]]$Lists) {
  if ($Stage -eq 'signin') { return 'the sign-in' }
  if ($Stage -eq 'site') { return 'the site check' }
  if ($Stage -match '^list (\d+)$' -and [int]$Matches[1] -ge 1 -and [int]$Matches[1] -le @($Lists).Count) { return ('the read of the list "' + [string]$Lists[[int]$Matches[1] - 1] + '"') }
  return ('the stage "' + $Stage + '"')
}
# E3 (R42 plan; the Administrator, 2026-11-21): the one copy of the sign-in block. Each child script that signs in holds the
# line "# <RADE sign-in window size>" in its place; Add-SignInSize puts the block there. An app copies the block (from its
# start line to its end line) into its own task scripts, so both use the same code. The block, its variable and its two
# marker lines keep their names (an app's build finds the block by them), though it no longer sizes a window.
$signInSize = @'
# ---- RADE sign-in window size (start; engine/ps/07-checks.ps1 $signInSize; E3, the Administrator, 2026-11-21)
# engine-v44 (the Administrator, 2026-11-26): RADE never touches the CAC sign-in window of Connect-PnPOnline -UseWebLogin; it opens
# at its own size. The size watch of engine-v35 to engine-v43 (Start-SignInSize) is gone: it froze the sign-in
# (90-161.Z R44 r2, one host: watch on, 2 windows not responding at 9 s; watch off, signed in after 5 s).
# The block holds the read-only window report (Start-SignInReport, Stop-SignInReport), the DPI setting of engine-v46
# (Set-SignInDpiAware) and the one sign-in (Connect-RadeSite).
# Copy this block unchanged between its start and end lines (an app's task scripts may hold the same copy).
# Windows PowerShell 5.1, no module. When the report helper cannot be compiled (Constrained Language Mode), the sign-in
# goes on without it.
# engine-v43 S2 (the Administrator, 2026-11-26: R44 r1 froze at the sign-in with no data): while Connect-PnPOnline runs, a
# background timer reads the windows of THIS process only, about every second, and prints one line at each change:
# "SIGNIN-WIN t=<seconds> windows=<visible> owned=<visible with an owner> min=<minimized> size=<largest WxH>
# hung=<not responding> front=<1 when the foreground window is one of them>". No title, no text, no other process.
# The parent reads the lines while the child runs (Invoke-ChildScript -StageSeconds), so a frozen sign-in still reports.
function Start-SignInReport {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
  param()
  if (-not $PSCmdlet.ShouldProcess('the windows of this process', 'Report their state')) { return }
  # Inline C# compilation is forbidden by DEC-NIPR; sign-in runs without native P/Invoke polling.
  $null = 0
}
function Stop-SignInReport {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
  param()
  if (-not $PSCmdlet.ShouldProcess('the window report of this process', 'Stop')) { return }
  $null = 0
}
function Set-SignInDpiAware {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'None')]
  param()
  if ($env:RADE_SIGNIN_DPI -ne '1') { return 'SIGNIN-DPI aware=off' }
  if (-not $PSCmdlet.ShouldProcess('this process', 'Make DPI-aware')) { return 'SIGNIN-DPI aware=no' }
  return 'SIGNIN-DPI aware=off'
}
# engine-v43 S1: the one sign-in of a child script. Prints "STAGE signin" (the parent stops a stage that runs too long),
# signs in with the CAC (PnP web login), prints "SIGNIN seconds=<n>" and "STAGE none" (no stage runs).
# Throws when the sign-in fails, as Connect-PnPOnline does. Takes the site address.
function Connect-RadeSite([string]$Site) {
  'STAGE signin'
  Set-SignInDpiAware   # engine-v47: prints aware=off unless RADE_SIGNIN_DPI=1 (the DPI sign-in of engine-v46 opened its window after about 90 s)
  $t0 = Get-Date; Start-SignInReport   # engine-v44: no size watch
  try { $null = & { Connect-PnPOnline -Url $Site -UseWebLogin -ErrorAction Stop } *>&1 }
  finally { Stop-SignInReport }   # no report after the sign-in
  'SIGNIN seconds=' + [int]((Get-Date) - $t0).TotalSeconds
  'STAGE none'
}
# ---- RADE sign-in window size (end)
'@
# Gives a child script's text with the sign-in block in place of its marker line. Takes the text; gives back the text.
function Add-SignInSize([string]$Text) { return $Text.Replace('# <RADE sign-in window size>', $signInSize.TrimEnd()) }
$rightsScript = @'
param([string]$Site, [string]$MarkerList = '', [string]$MarkerKey = '', [string]$MarkerField = '')
# <RADE sign-in window size>
# RADE check (read-only): signs in with the CAC (web login, as T16 does) and prints your rights on the site, whether your
# own account is a site collection administrator (one flag; no list of administrators) and, when the app keeps an install
# record on the site, the version in that one row. Prints only right names, True/False and a version, never the site,
# your name or an error message.
try {
  $mod = @(Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending)
  if (-not $mod.Count) { 'RESULT no-pnp'; exit 3 }
  $pin = @($mod | Where-Object { [string]$_.Version -eq '1.12.0' }); if ($pin.Count) { $mod = $pin }   # the tested version first (2.x needs PowerShell 7)
  $null = & { Import-Module PnP.PowerShell -RequiredVersion $mod[0].Version -DisableNameChecking } *>&1
  Connect-RadeSite $Site   # engine-v43 S1: STAGE, SIGNIN and SIGNIN-WIN lines (the block above)
  $script:web = $null
  $null = & { $script:web = Get-PnPWeb -Includes EffectiveBasePermissions -ErrorAction Stop } *>&1
  $p = $script:web.EffectiveBasePermissions
  $k = [Microsoft.SharePoint.Client.PermissionKind]
  foreach ($n in 'ViewListItems', 'AddListItems', 'EditListItems', 'ManageLists', 'ManageWeb', 'ManagePermissions') { 'RIGHT ' + $n + ' ' + $p.Has($k::$n) }
  try {
    $script:adm = $null
    $null = & { $script:adm = (Get-PnPWeb -Includes CurrentUser -ErrorAction Stop).CurrentUser.IsSiteAdmin } *>&1
    if ($script:adm -is [bool]) { 'ADMIN ' + $script:adm } else { 'ADMIN unknown' }
  } catch { 'ADMIN unknown' }
  if ($MarkerList) {
    try {
      $script:mk = 'none'
      $null = & {
        $l = Get-PnPList -Identity $MarkerList -ErrorAction Stop   # a list that does not exist gives nothing, not an error
        if ($l) {
          $q = "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>" + $MarkerKey + "</Value></Eq></Where></Query><RowLimit>1</RowLimit></View>"
          $it = @(Get-PnPListItem -List $l -Query $q -ErrorAction Stop)
          if ($it.Count) {
            $v = ([string]$it[0][$MarkerField]).Trim()
            if ($v -match '^([0-9][0-9.]*)') { $script:mk = 'found ' + $Matches[1] } elseif ($v) { $script:mk = 'found 0' }   # any value is an install
          }
        }
      } *>&1
      'MARKER ' + $script:mk
    } catch { 'MARKER unknown' }
  }
  exit 0
} catch { 'RESULT not-connected ' + $_.Exception.GetType().Name; exit 2 }
'@
$rightsScript = Add-SignInSize $rightsScript
# ---- Install record on the site (the Administrator, 14 Nov 26: one install per site). An app with "marker" in the
# manifest keeps one row (Title = Key) in its own list: the installed version and the date, no name. The record in
# RADE\Config is per account; this row is what another account's RADE sees. A site that has the row and an account
# that did not install it: the deploy is blocked (a second import would run every flow twice).
function Get-MarkerArg {
  $m = $script:app.Marker
  if (-not $m) { return '' }
  return (' -MarkerList "' + $m.List + '" -MarkerKey "' + $m.Key + '" -MarkerField "' + $m.Field + '"')
}
# Gives a short hash that stands for a site address (so the record never holds the address). Takes the site address;
# gives back the hash, or an empty text when the address is not valid.
function Get-SiteMark([string]$Site) {
  if (-not (Test-SiteUrl $Site)) { return '' }
  return (Get-ShortHash $Site.Trim().TrimEnd('/').ToLowerInvariant())
}
function Test-InstalledHere {
  # True when this account's record for this site (Get-InstalledKey) holds a step: a deploy from this account reached
  # a step here. A run that reached no step does not count.
  if (-not (Get-SiteMark (Get-SiteUrl (Get-BasePath)))) { return $false }
  $e = (Read-Installed (Get-InstalledKey $script:app))
  return [bool]($e -and $e.steps -and $e.steps.Count)
}
# Says whether this is a deploy of an app that keeps a row on the site and this account has not installed it on that
# site yet. Takes nothing; gives back $true or $false.
function Test-FirstInstall { return ((Test-Deploy) -and [bool]$script:app.Marker -and -not (Test-InstalledHere)) }
$markerScript = @'
param([string]$Site, [string]$MarkerList, [string]$MarkerKey, [string]$MarkerField, [string]$Value)
# <RADE sign-in window size>
# RADE (one write): signs in with the CAC and sets one row of the app's own list to the installed version and the date.
# Adds the row when it is missing; changes nothing else. Prints one RESULT word, never the site, a name or an error message.
try {
  $mod = @(Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending)
  if (-not $mod.Count) { 'RESULT no-pnp'; exit 3 }
  $pin = @($mod | Where-Object { [string]$_.Version -eq '1.12.0' }); if ($pin.Count) { $mod = $pin }
  $null = & { Import-Module PnP.PowerShell -RequiredVersion $mod[0].Version -DisableNameChecking } *>&1
  Connect-RadeSite $Site   # engine-v43 S1: STAGE, SIGNIN and SIGNIN-WIN lines (the block above)
  $script:res = 'no-list'
  $null = & {
    $l = Get-PnPList -Identity $MarkerList -ErrorAction Stop
    if ($l) {
      $q = "<View><Query><Where><Eq><FieldRef Name='Title'/><Value Type='Text'>" + $MarkerKey + "</Value></Eq></Where></Query><RowLimit>1</RowLimit></View>"
      $it = @(Get-PnPListItem -List $l -Query $q -ErrorAction Stop)
      if ($it.Count) { $null = Set-PnPListItem -List $l -Identity $it[0].Id -Values @{ $MarkerField = $Value } -ErrorAction Stop; $script:res = 'updated' }
      else { $null = Add-PnPListItem -List $l -Values @{ Title = $MarkerKey; $MarkerField = $Value } -ErrorAction Stop; $script:res = 'added' }
    }
  } *>&1
  'RESULT ' + $script:res
  exit 0
} catch { 'RESULT failed ' + $_.Exception.GetType().Name; exit 2 }
'@
$markerScript = Add-SignInSize $markerScript
