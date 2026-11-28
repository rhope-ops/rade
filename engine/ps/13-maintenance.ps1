# RADE engine part 13, the Maintenance tools (the Administrator, 2026-11-20; docs/engine.md "Maintenance run types").
# Diagnose: read-only; the install record, the app's local files and the app's RADE checks again; one report file.
# Back up: reads only the lists the app's manifest names ("backup") and saves each as JSON plus a CSV copy.
# Restore (engine-v31) is parts 14 and 15, engine/ps/14-restore.ps1 and 15-restore-run.ps1; it uses Invoke-Backup and Get-BackupFileName from here.
# Uninstall and its clean-up are part 17, engine/ps/17-uninstall.ps1 (engine-v48).
# Uses parts 01 to 08 (Get-BasePath, Read-Installed, Get-InstalledKey, Get-StartPath, Invoke-Check, Invoke-ChildScript).
# Network: Diagnose runs the app's own RADE checks (their fixed addresses only); Back up signs in to the saved site and
# reads only the lists the manifest names (AGENTS.md "No reconnaissance"). Neither one writes to the site.
# Writes: Diagnose: Diagnose\diagnose-<time>.txt; Back up: Backups\<time>\<list>.json and .csv (the app folder).
# Credentials: the interactive CAC sign-in of PnP (-UseWebLogin), for Back up only.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# Time limit of a child script that signs in and reads every named list, in seconds (Back up and the Restore dry run;
# the Administrator's lists are small, so it is generous).
$toolReadSeconds = 1800
# R44 E4 (R43: Back up stopped after a sign-in window): the time limit of one stage (sign-in, site check, one list), in seconds.
$toolStageSeconds = 300

# Gives the time stamp of a report or a backup folder (sortable, no colons). Takes nothing.
function Get-ToolStamp { return (Get-Date).ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture) }
# Makes one finding of a Maintenance tool. Takes PASS, FINDING or NOTE, the fact and what to do (or '').
function ConvertTo-ToolLine([string]$State, [string]$Text, [string]$Fix) { return @{ State = $State; Text = $Text; Fix = $Fix } }

<#
.SYNOPSIS
Diagnose, part D1: the install record and the app's local files against this paste.
.DESCRIPTION
Reads RADE's own files only: the install record (RADE\Config\installed), the start script of the app (manifest
"start") and the RADE runner copy. Each finding names its fix. Changes nothing.
.OUTPUTS
A list of ConvertTo-ToolLine tables.
#>
function Get-DiagnoseInstall {
  $e = Read-Installed (Get-InstalledKey $script:app); $out = @(); $pv = [string]$script:app.Version
  $repair = 'Select "Repair" on the Maintenance card'
  if (-not ($e -and $e.installed)) { return @(ConvertTo-ToolLine 'FINDING' ('This computer has no install record of ' + $script:app.Name + ' that ended PASSED') $repair) }
  $iv = [string]$e.installed.version; $c = 0
  try { $c = ([version]$pv).CompareTo([version]$iv) } catch { $c = [string]::CompareOrdinal($pv, $iv) }
  if ($c -eq 0) { $out += ConvertTo-ToolLine 'PASS' ('The installed version, ' + $iv + ', is the version in this paste') '' }
  elseif ($c -gt 0) { $out += ConvertTo-ToolLine 'FINDING' ('The installed version is ' + $iv + '; this paste has ' + $pv) ('Select "Update to ' + $pv + '" on the Maintenance card') }
  else { $out += ConvertTo-ToolLine 'FINDING' ('The installed version, ' + $iv + ', is newer than this paste (' + $pv + ')') ('Use the newest paste of ' + $script:app.Name) }
  $ls = $(if ($e.lastRun) { [string]$e.lastRun.state } else { '' })
  if ($ls -and $ls -ne 'PASSED') { $out += ConvertTo-ToolLine 'FINDING' ('The last install run ended ' + $ls) $repair }
  if ($e.steps) { foreach ($n in @($e.steps.Keys)) { $s = [string]$e.steps[$n].state
    if ($s -and $s -ne 'PASSED') { $out += ConvertTo-ToolLine 'FINDING' ('Step "' + $n + '" ended ' + $s + ' in its last run') $repair } } }
  $st = [string]$script:app.Start
  if ($st) { if (Get-StartPath) { $out += ConvertTo-ToolLine 'PASS' ('The start script ' + $st + ' is in the app folder') '' }
    else { $out += ConvertTo-ToolLine 'FINDING' ('The start script ' + $st + ' is missing from the app folder') ($repair + ': it puts the file back') } }
  $rp = Get-RunnerPath   # engine-v42: the app's own runner copy, RADE\runners\<key>.ps1
  if (Test-Path -LiteralPath $rp -PathType Leaf) { $out += ConvertTo-ToolLine 'PASS' 'The RADE runner copy of this app is saved' '' }
  else { $out += ConvertTo-ToolLine 'NOTE' 'The RADE runner copy of this app is not saved, so its shortcut cannot start RADE' $repair }
  return $out
}

<#
.SYNOPSIS
Diagnose, part D0: the app's RADE checks again, as the Ready card runs them, with no saved result reused.
.DESCRIPTION
A check that runs on its own runs again now. A sign-in or look-and-answer check needs the user, so Diagnose shows its
saved result, or says it was not run. The checks are read-only (docs/engine.md "Checks").
.PARAMETER Base
The RADE app folder.
.PARAMETER Tick
Run while a check waits (keeps the window alive), or $null.
.OUTPUTS
A list of ConvertTo-ToolLine tables, one for each check.
#>
function Get-DiagnoseCheck([string]$Base, [scriptblock]$Tick) {
  $site = Get-SiteUrl $Base; $cache = Read-CheckCache; $out = @()
  foreach ($id in @($script:appChecks)) {
    $d = Get-CheckDef $id; $r = $null
    if ($d.Kind -eq 'auto') { $r = Invoke-Check $d $Base $site $Tick } else { $r = Get-CheckToRun $d $cache $Base $site $false }
    if (-not $r) { $out += ConvertTo-ToolLine 'NOTE' ([string]$d.Name + ': not run (it needs you)') 'Select "Repair": its checks ask for it'; continue }
    $w = $(if ($r.State -in 'PASSED', 'WARNING') { 'PASS' } else { 'FINDING' })
    $out += ConvertTo-ToolLine $w ([string]$d.Name + ': ' + $r.State + $(if ($r.Detail) { '. ' + $r.Detail } else { '' })) ([string]$r.Fix)
  }
  return $out
}

<#
.SYNOPSIS
Runs Diagnose and saves its report in the app folder's Diagnose folder (never attached to the e-mail draft).
.PARAMETER Base
The RADE app folder.
.PARAMETER Tick
Run while a check waits, or $null.
.OUTPUTS
@{ Lines; Path; Findings }: the report lines (masked), the report file ('' when it could not be written) and the count
of findings.
#>
function Invoke-Diagnose([string]$Base, [scriptblock]$Tick) {
  $all = @(Get-DiagnoseInstall) + @(Get-DiagnoseCheck $Base $Tick) + @(Get-RestoreMarkNote $Base | Where-Object { $_ })   # the mark line: part 14 (engine-v33)
  $n = @($all | Where-Object { $_.State -eq 'FINDING' }).Count
  $lines = @(('Diagnose of ' + $script:app.Name + ' ' + $script:app.Version + ', ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '. Read-only: nothing was changed.'),
    $(if ($n) { [string]$n + ' finding(s). Each one says what to do.' } else { 'No findings.' }))
  foreach ($f in $all) { $lines += ($f.State + ': ' + $f.Text + $(if ($f.Fix) { '. What to do: ' + $f.Fix } else { '' })) }
  $lines = @($lines | ForEach-Object { ConvertTo-Masked $_ })
  $p = ''
  try { $dir = Join-Path $Base 'Diagnose'   # not Rounds\<round>: the e-mail draft attaches every file there (review of PR 143)
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $p = Join-Path $dir ('diagnose-' + (Get-ToolStamp) + '.txt'); Write-FileWhole $p (($lines -join "`r`n") + "`r`n") } catch { $p = '' }
  return @{ Lines = $lines; Path = $p; Findings = $n }
}

# ---- Back up. The child script reads each named list and writes ~<n>.json and ~<n>.csv into the folder it is given.
# It prints only a list number, a row count or an error type: never the site, a name, a value or an error message.
$backupScript = @'
param([string]$Site, [string]$Folder, [string]$Lists)
# <RADE sign-in window size>
# RADE Back up (reads the site, writes this computer only): signs in with the CAC and saves each named list.
# Windows PowerShell 5.1 writes an array as {value, Count} while this type data is loaded: take it out first.
Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue
# Turns one SharePoint field value into plain text or a number: lookup and person "id;#text", link "url;#text", managed
# metadata "label|guid", place "POINT(lon lat)", several values joined with ";#", a date in ISO form (UTC). Takes the value.
function ConvertTo-PlainValue($V) {
  if ($V -is [datetime]) { return $V.ToUniversalTime().ToString('o') }
  if (($null -eq $V) -or ($V -is [string]) -or ($V -is [ValueType])) { return $V }
  $p = $V.PSObject.Properties
  if ($p['LookupId']) { return ([string]$V.LookupId + ';#' + [string]$V.LookupValue) }
  if ($p['Url']) { return ([string]$V.Url + ';#' + [string]$V.Description) }
  if ($p['TermGuid']) { return ([string]$V.Label + '|' + [string]$V.TermGuid) }
  if ($p['Latitude']) { return ('POINT(' + [string]$V.Longitude + ' ' + [string]$V.Latitude + ')') }
  if ($V -is [System.Collections.IEnumerable]) { return ((@(foreach ($x in $V) { ConvertTo-PlainValue $x }) | ForEach-Object { [string]$_ }) -join ';#') }
  return [string]$V
}
try {
  $mod = @(Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending)
  if (-not $mod.Count) { 'RESULT no-pnp'; exit 3 }
  $pin = @($mod | Where-Object { [string]$_.Version -eq '1.12.0' }); if ($pin.Count) { $mod = $pin }
  $null = & { Import-Module PnP.PowerShell -RequiredVersion $mod[0].Version -DisableNameChecking } *>&1
  # R44 E4: STAGE lines let RADE stop a stage that takes too long and name it (Invoke-ChildScript -StageSeconds).
  Connect-RadeSite $Site   # engine-v43 S1: STAGE signin, SIGNIN and SIGNIN-WIN lines (the block above)
  # R44 E4: the site check. The connection must be to the given site, else nothing is read (prints no address).
  'STAGE site'
  $script:web = $null
  try { $null = & { $script:web = Get-PnPWeb -ErrorAction Stop } *>&1; $u = [string]$script:web.Url } catch { 'RESULT site-unknown ' + $_.Exception.GetType().Name; exit 5 }
  if ($u.TrimEnd('/').ToLowerInvariant() -ne $Site.Trim().TrimEnd('/').ToLowerInvariant()) { 'RESULT wrong-site'; exit 4 }
  $i = 0
  foreach ($name in ($Lists -split '\|')) {
    $i++
    'STAGE list ' + $i
    try {
      $script:items = @()
      $null = & { $script:items = @(Get-PnPListItem -List $name -PageSize 500 -ErrorAction Stop) } *>&1
      $rows = @(foreach ($it in $script:items) { $o = [ordered]@{}
        foreach ($k in @($it.FieldValues.Keys)) { $o[$k] = ConvertTo-PlainValue $it.FieldValues[$k] }
        [pscustomobject]$o })
      $j = Join-Path $Folder ('~' + $i + '.json'); $c = Join-Path $Folder ('~' + $i + '.csv')   # '~': no list title has it, so no name clash
      [System.IO.File]::WriteAllText($j, (ConvertTo-Json -InputObject @($rows) -Depth 4), (New-Object System.Text.UTF8Encoding $true))
      if ($rows.Count) { $rows | Export-Csv -LiteralPath $c -NoTypeInformation -Encoding UTF8 } else { [System.IO.File]::WriteAllText($c, '') }
      'LIST ' + $i + ' ' + $rows.Count
    } catch { 'LIST ' + $i + ' failed ' + $_.Exception.GetType().Name }
  }
  'RESULT done'; exit 0
} catch { 'RESULT not-connected ' + $_.Exception.GetType().Name; exit 2 }
'@
if (Get-Command Add-SignInSize -ErrorAction SilentlyContinue) { $backupScript = Add-SignInSize $backupScript }   # E3: the sign-in block (16-site-scripts.ps1)

# Gives the file name (no extension) of a saved list: its title with any sign a file name cannot hold made "_" (the
# build allows letters, digits, space, "_", "-", "(" and ")", so this changes nothing today). Takes the list title.
function Get-BackupFileName([string]$Name) { return ($Name -replace '[^A-Za-z0-9 _()-]', '_') }
# Makes the new folder of a backup, Backups\<time> in the app folder; a folder of that name that is there already (the
# same second, or the hour that repeats when daylight saving ends) is never reused: -2, -3 and so on follow. Takes the
# RADE app folder and the time stamp; gives back the new folder, or '' when none could be made.
function Get-NewBackupDir([string]$Base, [string]$Stamp) {
  $root = Join-Path $Base 'Backups'
  for ($k = 1; $k -le 50; $k++) { $d = Join-Path $root ($Stamp + $(if ($k -gt 1) { '-' + $k } else { '' }))
    if (Test-Path -LiteralPath $d) { continue }
    try { $null = New-Item -ItemType Directory -Path $d -ErrorAction Stop; return $d } catch { if (-not (Test-Path -LiteralPath $d)) { return '' } } }
  return '' }
# Removes the folder of a backup that saved nothing (only the new folder this run made). Takes the folder; gives back
# $true when it is gone.
function Clear-BackupDir([string]$Dir) {
  try { Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction Stop; return $true } catch { return (-not (Test-Path -LiteralPath $Dir)) } }
# Gives a saved list its name: ~<n>.json and ~<n>.csv become <list>.json and <list>.csv; both must be there. Takes the
# folder, the list number and the file name; gives back $true when both files have their name.
function Rename-BackupFile([string]$Dir, [int]$I, [string]$Name) {
  try { foreach ($x in '.json', '.csv') { $to = Join-Path $Dir ($Name + $x); if (Test-Path -LiteralPath $to) { return $false }   # never over another list's file
      Move-Item -LiteralPath (Join-Path $Dir ('~' + $I + $x)) -Destination $to -ErrorAction Stop }
    return ((Test-Path -LiteralPath (Join-Path $Dir ($Name + '.json')) -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Dir ($Name + '.csv')) -PathType Leaf)) } catch { return $false } }

<#
.SYNOPSIS
Runs Back up: saves each list the manifest names ("backup") as JSON plus a CSV copy in a new Backups\<time> folder.
.DESCRIPTION
An app that names no lists: Back up says so and writes nothing (the Administrator, 2026-11-20). With no valid site
address it stops before the sign-in. A list that cannot be read is reported by name, never skipped without a word. The
files are named after the list; a list file is checked after the run (it must be there). Nothing on the site changes.
.PARAMETER Base
The RADE app folder.
.PARAMETER Tick
Run while the sign-in and the reads go on (keeps the window alive), or $null.
.OUTPUTS
@{ State; Lines; Path }: State is none, no-site, done or failed; Lines are plain report lines; Path is the folder or ''.
#>
function Invoke-Backup([string]$Base, [scriptblock]$Tick) {
  $lists = @($script:app.Backup | Where-Object { $_ })
  if (-not $lists.Count) { $why = $script:app.Name + ' names no lists to back up, so Back up saved nothing.'
    return @{ State = 'none'; Path = ''; Lines = @($why, 'The app adds them in its manifest ("backup").') } }
  $site = Get-SiteUrl $Base
  if (-not (Test-SiteUrl $site)) {
    return @{ State = 'no-site'; Path = ''; Lines = @('No site address is saved, so Back up did not sign in.', 'Select "Repair": its checks ask for the site address.') } }
  $dir = Get-NewBackupDir $Base (Get-ToolStamp)   # always a new folder: a failed run removes only this one
  if (-not $dir) { return @{ State = 'failed'; Path = ''; Lines = @('Back up could not make its folder on this computer.') } }
  $r = Invoke-ChildScript $backupScript ('-Site "' + $site + '" -Folder "' + $dir + '" -Lists "' + ($lists -join '|') + '"') $toolReadSeconds $Tick $toolStageSeconds
  $got = @{}; $res = ''
  foreach ($l in $r.Lines) { if ($l -match '^LIST (\d+) (.+)$') { $got[[int]$Matches[1]] = $Matches[2] } elseif ($l -match '^RESULT (\S+)') { $res = $Matches[1] } }
  $note = Get-SignInNote 'Back up' $r.Lines   # R44 E4, engine-v43 S2, S3: the sign-in lines in the run log, with the host
  $signLine = ''; if ($note -match '^SIGNIN seconds=(\d+)') { $signLine = 'The sign-in took ' + $Matches[1] + ' seconds.' }
  if ($res -ne 'done') { $why = $(switch ($res) { 'no-pnp' { 'the SharePoint tool is not installed' } 'not-connected' { 'the sign-in did not finish' }
        'wrong-site' { 'the sign-in connected to another site than the saved site address' }
        'site-unknown' { 'RADE could not read which site the sign-in connected to' }
        default { $(if ($r.Stage) { (Get-StageText $r.Stage $lists) + ' did not finish in ' + [int]($toolStageSeconds / 60) + ' minutes, so RADE stopped it' } else { 'it stopped: ' + $r.Why }) } })
    $gone = Clear-BackupDir $dir
    $left = $(if ($gone) { 'Nothing on the site changed.' } else { 'Nothing on the site changed. Its unfinished folder stays: ' + (ConvertTo-Masked $dir) })
    return @{ State = 'failed'; Path = ''; Lines = @(@(('Back up saved nothing: ' + $why + '.'), $left, 'Select "Back up" again.') + @($signLine | Where-Object { $_ })) } }
  $lines = @(); $bad = 0
  for ($i = 1; $i -le $lists.Count; $i++) {
    $n = [string]$lists[$i - 1]; $v = [string]$got[$i]; $ok = $false
    if ($v -match '^\d+$') { $ok = Rename-BackupFile $dir $i (Get-BackupFileName $n) }
    if ($ok) { $lines += ('PASS: "' + $n + '": ' + $v + ' rows saved'); continue }
    $bad++; $ty = $(if ($v -match '^failed (\S+)') { ' (' + $Matches[1] + ')' } elseif ($v) { ' (its files could not be named)' } else { '' })
    $lines += ('FINDING: "' + $n + '" was not saved' + $ty + '. What to do: check that the list exists and that you can read it, then select "Back up" again')
  }
  $head = $(if ($bad) { [string]$bad + ' of ' + $lists.Count + ' lists were not saved.' } else { 'All ' + $lists.Count + ' lists were saved.' })
  return @{ State = $(if ($bad) { 'failed' } else { 'done' }); Path = $dir; Lines = @(@($head, 'Nothing on the site changed.') + $lines + @($signLine | Where-Object { $_ })) }
}
