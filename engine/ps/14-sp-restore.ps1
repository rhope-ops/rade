# RADE engine part 14, the Maintenance tool Restore (engine-v31; the local test-site mark, engine-v32; the Administrator,
# 2026-11-20 and 2026-11-21; plan docs/reviews/2026-11-21-plan-restore-v31.md; docs/engine.md "Maintenance run types").
# Puts back the rows of a backup that are missing from their list, on a test site only: a dry run with counts first,
# then (after the user types the app name) a fresh backup, the pause switch, the Recycle Bin, then new rows with lookups
# re-pointed. A row that is on the list is never changed, and no row is made twice.
# Uses parts 01 to 08, 13 and 16 (Get-SiteUrl, Test-SiteUrl, Get-SiteMark, Invoke-ChildScript, Invoke-Backup,
# Get-BackupFileName, ConvertTo-Masked).
# Network: signs in to the saved site and reads only the lists the manifest names ("backup"), their fields and the
# site's Recycle Bin (AGENTS.md "No reconnaissance").
# Writes: site rows of the named lists (missing rows only) and the app's pause-switch row, after the typed confirm; on
# the computer, a fresh backup, Backups\~restore-map-<site hash>.json and, from the mark card,
# Config\<prefix>-restore-test-site.txt.
# Credentials: the interactive CAC sign-in of PnP (-UseWebLogin).
# The functions the window and the text mode call (Get-BackupSet to Invoke-Restore) are in part 15,
# engine/ps/15-restore-run.ps1.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

$restoreWriteSeconds = 3600   # time limit of the Restore write, in seconds: a sign-in and every row it puts back
$backupSetMax = 10            # backups the Restore card lists, newest first (one card of rows)

# ---- Restore (engine-v31; plan docs/reviews/2026-11-21-plan-restore-v31.md). The child script runs in two modes:
# "plan" (the dry run: reads only) and "write" (after the typed confirm). It prints only list numbers, counts and error
# types: never the site, a name, an ID or a value.
$restoreScript = @'
param([string]$Site, [string]$Folder, [string]$Lists, [string]$Mode, [string]$Expect, [string]$Pause, [string]$MapFile, [string]$BackupFolder)
# <RADE sign-in window size>
# RADE Restore: missing rows only. Mode plan reads the site and writes nothing; mode write puts the missing rows back.
# Output: PLAN, BIN, PAUSE, DONE, RESUME and RESULT lines with numbers, error types and a short hash only.
Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue   # Windows PowerShell 5.1 writes an array as {value, Count} while it is loaded; absent elsewhere
$PageSize = 500         # rows a read asks for at once: under the SharePoint list view threshold of 5,000
$BinRowLimit = 5000     # Recycle Bin items read at most (docs/engine.md "Maintenance run types", limits)
$SigBytes = 6           # bytes of the SHA-256 kept as the dry-run hash of a list (12 hex characters)
$SkipTypes = @('Computed', 'Calculated', 'Attachments', 'ContentTypeId', 'File', 'Counter')   # field types SharePoint sets itself
$SkipNames = @('ContentType', 'Attachments')                                                   # fields SharePoint sets itself

# ---- Small helpers.
# The file name of a saved list (the same rule as Get-BackupFileName in the engine). Takes the list title.
function Get-FileName([string]$Name) { return ($Name -replace '[^A-Za-z0-9 _()-]', '_') }
# The IDs in a saved lookup or person value "id;#text;#id;#text" (the even parts). Takes the value; gives back ints.
function Get-SavedIds($Value) { $parts = @(([string]$Value) -split ';#')
  return @(for ($k = 0; $k -lt $parts.Count; $k += 2) { if ($parts[$k] -match '^\d+$') { [int]$parts[$k] } }) }
# Reads the IDs on a list now. Takes the list title; gives back a table ID -> $true; throws when the list cannot be read.
function Read-ListIds([string]$Name) { $script:rows = @()
  $null = & { $script:rows = @(Get-PnPListItem -List $Name -PageSize $PageSize -Fields 'ID' -ErrorAction Stop) } *>&1
  $ids = @{}; foreach ($item in $script:rows) { $ids[[int]$item.Id] = $true }; return $ids }

# ---- The same-row groups (reviews 3 and 4 of PR 151): each Restore that makes a row new links its old ID and the new
# one; all IDs linked, step by step, are one row. A groups table holds P (each ID's parent) and M (each root's IDs), so
# a group is found at once, not by a scan.
# Gives the root ID of a group (and shortens the path). Takes the groups and an ID.
function Get-Root($Groups, [int]$Id) { if (-not $Groups.P.ContainsKey($Id)) { return $Id }
  $root = $Id; while ($Groups.P[$root] -ne $root) { $root = $Groups.P[$root] }
  while ($Groups.P[$Id] -ne $root) { $next = $Groups.P[$Id]; $Groups.P[$Id] = $root; $Id = $next }; return $root }
# Links two IDs as one row. Takes the groups and the two IDs.
function Join-Ids($Groups, [int]$First, [int]$Second) {
  foreach ($id in $First, $Second) { if (-not $Groups.P.ContainsKey($id)) { $Groups.P[$id] = $id
      $Groups.M[$id] = New-Object 'System.Collections.Generic.List[int]'; $Groups.M[$id].Add($id) } }
  $rootA = Get-Root $Groups $First; $rootB = Get-Root $Groups $Second
  if ($rootA -ne $rootB) { $Groups.P[$rootB] = $rootA; $Groups.M[$rootA].AddRange($Groups.M[$rootB]); $Groups.M.Remove($rootB) } }
# The IDs of the row that an ID is one of. Takes the groups and the ID; gives back ints.
function Get-Group($Groups, [int]$Id) { if (-not $Groups.P.ContainsKey($Id)) { return @($Id) }; return @($Groups.M[(Get-Root $Groups $Id)]) }
# The ID under which a row is on the list now (any ID of its group), or $null. Takes the list's state and the ID.
function Get-OnList($State, [int]$Id) { foreach ($member in (Get-Group $State.Groups $Id)) { if ($State.Have.ContainsKey($member)) { return $member } }; return $null }
# Says whether an ID of a row has a pending mark ("p<ID>": a new row was being written and not confirmed). Takes the
# list's state and the ID.
function Test-Pending($State, [int]$Id) { foreach ($member in (Get-Group $State.Groups $Id)) { if ($State.Pend.ContainsKey($member)) { return $true } }; return $false }

<#
.SYNOPSIS
Turns a saved value (Back up's plain form) into what Add-PnPListItem takes for a field of this type.
.DESCRIPTION
Lookup IDs go to the ID the row has on that list now (Get-OnList) when the list is one of the restored lists; an ID
that is not there is dropped and counted in $script:unlinked. A person goes back by its site user ID, a link as
"url, description", managed metadata by its term ID, several choices as a list, a date as a date; a place is not written.
.PARAMETER Field
The field (InternalName, TypeAsString, LookupGuid).
.PARAMETER Value
The saved value.
.PARAMETER Info
The restored lists' states (Lists, ById).
.OUTPUTS
The value to write, or $null for no value.
#>
function ConvertTo-WriteValue($Field, $Value, $Info) {
  if ($null -eq $Value -or ([string]$Value) -eq '') { return $null }
  $type = [string]$Field.TypeAsString
  if ($type -in 'Lookup', 'LookupMulti') {
    $target = $Info.ById[[string]$Field.LookupGuid]; $out = @()
    foreach ($id in (Get-SavedIds $Value)) {
      if ($null -eq $target) { $out += $id; continue }   # a list RADE does not restore: the ID stays
      $on = Get-OnList $Info.Lists[$target] $id; if ($null -ne $on) { $out += [int]$on } else { $script:unlinked++ } }
    if (-not $out.Count) { return $null }
    if ($type -eq 'Lookup') { return $out[0] } else { return $out } }
  if ($type -in 'User', 'UserMulti') { $ids = @(Get-SavedIds $Value); if (-not $ids.Count) { return $null }
    if ($type -eq 'User') { return $ids[0] } else { return $ids } }
  if ($type -eq 'URL') { $parts = ([string]$Value) -split ';#', 2; if ($parts.Count -gt 1 -and $parts[1]) { return ($parts[0] + ', ' + $parts[1]) }; return $parts[0] }
  if ($type -in 'TaxonomyFieldType', 'TaxonomyFieldTypeMulti') { $terms = @(([string]$Value) -split ';#' | ForEach-Object { ($_ -split '\|')[-1] } | Where-Object { $_ })
    if ($type -eq 'TaxonomyFieldType') { return $terms[0] } else { return $terms } }
  if ($type -eq 'MultiChoice') { return @(([string]$Value) -split ';#' | Where-Object { $_ }) }
  if ($type -eq 'DateTime') { if ($Value -is [datetime]) { return $Value }
    return [datetime]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) }
  if ($type -eq 'Geolocation') { return $null }   # not written in v1 (no plain form PnP takes)
  return $Value
}

# ---- The record of re-made rows: Backups\~restore-map-<site hash>.json, one file per site (IDs belong to a site), from
# any backup of this app: links "old-new" and pending marks "p<ID>" per list title. A pending mark is saved before a new
# row is written and replaced by the link after: a row with a mark is never made again (the write may have worked).
# Reads the record. Takes nothing; gives back a table list title -> entries; stops the run with "MAP failed" when the
# file is there but cannot be read (an empty file too: it is never read as "no record").
function Read-RestoreRecord {
  $record = @{}; if (-not (Test-Path -LiteralPath $MapFile -PathType Leaf)) { return $record }
  try { $json = [System.IO.File]::ReadAllText($MapFile) | ConvertFrom-Json
    if ($null -eq $json) { throw 'empty record' }
    foreach ($prop in $json.PSObject.Properties) { $record[$prop.Name] = @(@($prop.Value) | Where-Object { [string]$_ -match '^(\d+-\d+|p\d+)$' } | ForEach-Object { [string]$_ }) } }
  catch { 'MAP failed'; exit 6 }
  return $record }
# Writes the record: every link and pending mark, the lists of this run and the others as read. Writes a new file, then
# puts it in place, so a stop halfway never leaves a cut file. Throws when it cannot. Takes nothing.
function Save-RestoreRecord {
  if ($MapFile.Length -gt 240) { throw ('map path is too long (' + $MapFile.Length + ' > 240 chars)') }
  $out = [ordered]@{}; foreach ($title in @($record.Keys)) { $out[$title] = @($record[$title]) }
  foreach ($k in $keys) { $state = $info.Lists[$k]; $out[$state.Name] = @($state.Links) }
  $tmp = $MapFile + '.new'
  [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $out -Depth 4), (New-Object System.Text.UTF8Encoding $true))
  for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
      if (Test-Path -LiteralPath $MapFile) { [System.IO.File]::Replace($tmp, $MapFile, [NullString]::Value) } else { [System.IO.File]::Move($tmp, $MapFile) }
      break
    } catch {
      if ($attempt -ge 5) { throw }
      Start-Sleep -Milliseconds (100 * $attempt)
    }
  } }

<#
.SYNOPSIS
Reads one list for Restore: its saved rows, the IDs on it now, its writable fields and its same-row groups.
.PARAMETER Number
The list's number (its place in the manifest's "backup").
.PARAMETER Name
The list title.
.OUTPUTS
The list's state (Name, Saved, Have, Fields, Groups, Links, Pend, Missing, Unsure, After, Bin, Url), or $null after a
PLAN line that says why it is left out (nofile, nolist or failed and the error type).
#>
function Read-RestoreList([int]$Number, [string]$Name) {
  $file = Join-Path $Folder ((Get-FileName $Name) + '.json')
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { 'PLAN ' + $Number + ' nofile'; return $null }
  try {
    $saved = @([System.IO.File]::ReadAllText($file) | ConvertFrom-Json) | Where-Object { $null -ne $_ }
    $script:found = $null; $null = & { $script:found = Get-PnPList -Identity $Name -Includes RootFolder -ErrorAction Stop } *>&1
    if (-not $script:found) { 'PLAN ' + $Number + ' nolist'; return $null }
    $have = Read-ListIds $Name
    $script:defs = @(); $null = & { $script:defs = @(Get-PnPField -List $Name -ErrorAction Stop) } *>&1
    $fields = @(foreach ($def in $script:defs) {
      if ($def.ReadOnlyField -or $def.Hidden -or ([string]$def.TypeAsString) -in $SkipTypes -or [string]$def.InternalName -in $SkipNames) { continue }
      $guid = ''; if ([string]$def.SchemaXml -match 'List="\{?([0-9a-fA-F-]{36})\}?"') { $guid = $Matches[1].ToLowerInvariant() }
      [pscustomobject]@{ InternalName = [string]$def.InternalName; TypeAsString = [string]$def.TypeAsString; LookupGuid = $guid } })
    $state = @{ Name = $Name; Saved = $saved.Count; Have = $have; Fields = $fields; Groups = @{ P = @{}; M = @{} }; Links = @(); Pend = @{}; Bin = @{}
      Url = ([string]$script:found.RootFolder.ServerRelativeUrl).Trim('/').ToLowerInvariant(); Id = ([string]$script:found.Id).Trim('{}').ToLowerInvariant() }
    if ($record.ContainsKey($Name)) { $state.Links = @($record[$Name])
      foreach ($entry in $state.Links) { if ($entry -match '^p(\d+)$') { $state.Pend[[int]$Matches[1]] = $true }
        else { $pair = $entry -split '-'; Join-Ids $state.Groups ([int]$pair[0]) ([int]$pair[1]) } } }
    # A saved row is on the list when any ID of its group is (its own, or one an earlier Restore gave it).
    $known = @{}; foreach ($row in $saved) { foreach ($member in (Get-Group $state.Groups ([int]$row.ID))) { $known[$member] = $true } }
    $gone = @($saved | Where-Object { $null -eq (Get-OnList $state ([int]$_.ID)) })
    $state.Unsure = @($gone | Where-Object { Test-Pending $state ([int]$_.ID) }).Count   # not put back: a hand check
    $state.Missing = @($gone | Where-Object { -not (Test-Pending $state ([int]$_.ID)) })
    $state.After = @($have.Keys | Where-Object { -not $known.ContainsKey($_) }).Count
    $state.Before = $have.Count   # the rows on the list when this run read it: the base of the count check after the write
    return $state
  } catch { 'PLAN ' + $Number + ' failed ' + $_.Exception.GetType().Name; return $null }
}

# Finds, for each missing row, an ID of its group in the site's Recycle Bin (its own first), each bin item once (R1).
# Fills each list's Bin (saved ID -> @{ Item; Id }). Takes nothing; a bin that cannot be read gives a BIN line.
function Find-BinRows {
  try { $script:bin = @(); $null = & { $script:bin = @(Get-PnPRecycleBinItem -RowLimit $BinRowLimit -ErrorAction Stop) } *>&1 }
  catch { 'BIN failed ' + $_.Exception.GetType().Name; return }
  $inBin = @{}
  foreach ($item in $script:bin) { if ([string]$item.ItemType -ne 'ListItem' -or [string]$item.LeafName -notmatch '^(\d+)_\.000$') { continue }
    $inBin[([string]$item.DirName).Trim('/').ToLowerInvariant() + '|' + $Matches[1]] = $item }
  foreach ($k in $keys) { $state = $info.Lists[$k]; $used = @{}
    foreach ($row in $state.Missing) { foreach ($member in (Get-Group $state.Groups ([int]$row.ID))) { $key = $state.Url + '|' + $member
        if ($inBin.ContainsKey($key) -and -not $used.ContainsKey($member)) { $state.Bin[[int]$row.ID] = @{ Item = $inBin[$key]; Id = $member }; $used[$member] = $true; break } } } } }

# Prints the PLAN line of each list, with a short hash of its missing IDs and bin choices (the write checks the same
# rows, not only the same count; no ID is printed). Takes nothing.
function Write-PlanLines {
  foreach ($k in $keys) { $state = $info.Lists[$k]
    $text = (@($state.Missing | ForEach-Object { [int]$_.ID } | Sort-Object) -join ',') + '/' + (@($state.Bin.Keys | Sort-Object | ForEach-Object { [string]$_ + ':' + $state.Bin[$_].Id }) -join ',')
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $state.Sig = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))[0..($SigBytes - 1)] | ForEach-Object { $_.ToString('x2') }); $sha.Dispose()
    'PLAN ' + $k + ' saved=' + $state.Saved + ' now=' + $state.Have.Count + ' missing=' + $state.Missing.Count + ' bin=' + $state.Bin.Count +
      ' new=' + ($state.Missing.Count - $state.Bin.Count) + ' after=' + $state.After + ' unsure=' + $state.Unsure + ' sig=' + $state.Sig } }

# Says whether the site is as the dry run saw it: the same hash for each list, and no list more or less. Takes nothing.
function Test-SameAsPlan {
  $want = @{}; foreach ($entry in ($Expect -split ',')) { if ($entry -match '^(\d+):([0-9a-f]+)$') { $want[[int]$Matches[1]] = $Matches[2] } }
  if ($want.Count -ne $keys.Count) { return $false }
  foreach ($k in $keys) { if ($want[$k] -ne $info.Lists[$k].Sig) { return $false } }
  return $true }

# R2: reads the pause-switch row, then sets it to its on value. Takes nothing; gives back the switch (List, Title,
# Field, On, Row, Old) and prints nothing, or $null with no switch; stops the run (no row written) when the row is not there, is on already or cannot be set.
function Set-PauseOn {
  if (-not $Pause) { return $null }
  $part = $Pause -split '\|'; $switch = @{ List = $part[0]; Title = $part[1]; Field = $part[2]; On = $part[3] }
  try { $caml = '<View><Query><Where><Eq><FieldRef Name="Title"/><Value Type="Text">' + $switch.Title + '</Value></Eq></Where></Query></View>'
    $script:found = $null; $null = & { $script:found = @(Get-PnPListItem -List $switch.List -Query $caml -ErrorAction Stop) } *>&1; $row = @($script:found)[0]
    if (-not $row) { 'RESULT no-pause-row'; exit 5 }
    $old = [string]$row[$switch.Field]
    if ($old -eq $switch.On) { 'RESULT paused-already'; exit 5 }
    $null = & { Set-PnPListItem -List $switch.List -Identity $row.Id -Values @{ $switch.Field = $switch.On } -ErrorAction Stop } *>&1 }
  catch { 'RESULT pause-failed ' + $_.Exception.GetType().Name; exit 5 }
  return ($switch + @{ Row = $row; Old = $old }) }

# R1: puts back each chosen Recycle Bin item; after an error the list is read again (a restore that reported an error
# but worked is not made a second time). A row that did not come back is made new later (Add-MissingRows): the BINERR
# line gives its list and the first error type, so the result card says so (E2, R42; the Administrator, 2026-11-21).
# Takes nothing; sets $script:stopMake when a list cannot be read again.
function Restore-BinRows {
  foreach ($k in $keys) { $state = $info.Lists[$k]; $state.FromBin = 0; $state.BinFailed = 0; $binErr = ''; $failed = @()
    foreach ($id in @($state.Bin.Keys)) { $choice = $state.Bin[$id]
      try { $null = & { Restore-PnPRecycleBinItem -Identity $choice.Item -Force -ErrorAction Stop } *>&1; $state.Have[[int]$choice.Id] = $true; $state.FromBin++ }
      catch { $state.Bin.Remove($id); $failed += @{ Id = $choice.Id; Err = $_.Exception.GetType().Name } } }
    if ($failed.Count) { try { foreach ($id in @((Read-ListIds $state.Name).Keys)) { $state.Have[$id] = $true } } catch { $script:stopMake = $true } }
    # A restore that reported an error but put the row back (it is on the list now, with its own ID) counts as back.
    # BINERR gives the error type of the first row that really did not come back.
    foreach ($miss in $failed) { if ($state.Have.ContainsKey([int]$miss.Id)) { $state.FromBin++ } else { $state.BinFailed++; if (-not $binErr) { $binErr = [string]$miss.Err } } }
    if ($state.BinFailed) { 'BINERR ' + $k + ' ' + $binErr } } }   # an error type only: no site, name, ID or value

# R5: the lists in dependency order: a list whose lookup reads another restored list comes after it; a loop keeps the
# manifest order for the lists left. Takes nothing; gives back the list numbers.
function Get-ListOrder {
  $order = @(); $left = New-Object 'System.Collections.Generic.List[int]'; foreach ($k in $keys) { $left.Add($k) }
  while ($left.Count) { $next = $null
    foreach ($k in $left) { $deps = @($info.Lists[$k].Fields | Where-Object { $_.LookupGuid } | ForEach-Object { $info.ById[$_.LookupGuid] } |
        Where-Object { $null -ne $_ -and $_ -ne $k -and $left.Contains($_) })
      if (-not $deps.Count) { $next = $k; break } }
    if ($null -eq $next) { $next = $left[0] }
    $order += $next; $null = $left.Remove($next) }
  return $order }

<#
.SYNOPSIS
Makes the missing rows of one list that did not come back from the Recycle Bin, each with a pending mark saved first.
.DESCRIPTION
A write that works but reports an error keeps its mark, so no later run makes it again (a hand check). A record that
cannot be saved stops new rows ($script:mapStop). A row whose group is on the list already is not made.
.PARAMETER State
The list's state.
.OUTPUTS
None; sets Made, Failed, Skipped and Unlinked on the state.
#>
function Add-MissingRows($State) {
  $State.Made = 0; $State.Failed = 0; $State.Skipped = 0; $script:unlinked = 0
  if (@($State.Missing).Count -gt 0) {
    try { Save-RestoreRecord } catch { $script:mapStop = $true; return }
  }
  try {
    foreach ($row in @($State.Missing | Sort-Object { [int]$_.ID })) {
      if ($null -ne (Get-OnList $State ([int]$row.ID))) { continue }   # back from the Recycle Bin, or another saved ID of the same row was made
      $values = @{}
      $unlinkedBefore = $script:unlinked   # a row that is not written does not add to the empty-lookup count
      try { foreach ($field in $State.Fields) { $prop = $row.PSObject.Properties[$field.InternalName]; if (-not $prop) { continue }
          $value = ConvertTo-WriteValue $field $prop.Value $info; if ($null -ne $value) { $values[$field.InternalName] = $value } } }
      catch { $State.Skipped++; $script:unlinked = $unlinkedBefore; continue }   # a saved value that cannot be read (a bad date): not written, no mark; the next rows go on
      $mark = 'p' + [int]$row.ID
      $State.Links += $mark
      try { $script:made = $null; $null = & { $script:made = Add-PnPListItem -List $State.Name -Values $values -ErrorAction Stop } *>&1; $newId = [int]$script:made.Id
        if ($newId -le 0) { throw 'no ID' } }   # no ID back: the write is not confirmed, so the mark stays
      catch {
        $State.Failed++
        $errMsg = (([string]$_.Exception.Message) -replace 'https?://\S+', '<url>' -replace '[\r\n]+', ' ').Trim()
        if ($errMsg.Length -gt 120) { $errMsg = $errMsg.Substring(0, 120) }
        'ROWERR ' + $_.Exception.GetType().Name + ': ' + $errMsg
        continue }   # the mark stays: the row may be on the list; the next runs leave it for a hand check
      $State.Have[$newId] = $true; Join-Ids $State.Groups ([int]$row.ID) $newId; $State.Made++
      $State.Links = @(@($State.Links | Where-Object { $_ -ne $mark }) + @([string]$row.ID + '-' + $newId))
    }
  } finally {
    try { Save-RestoreRecord } catch { $script:mapStop = $true }
  }
  $State.Unlinked = $script:unlinked }

# ---- The run.
try {
  $mod = @(Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending)
  if (-not $mod.Count) { 'RESULT no-pnp'; exit 3 }
  $pin = @($mod | Where-Object { [string]$_.Version -eq '1.12.0' }); if ($pin.Count) { $mod = $pin }
  $null = & { Import-Module PnP.PowerShell -RequiredVersion $mod[0].Version -DisableNameChecking } *>&1
  Connect-RadeSite $Site   # engine-v43 S1: STAGE, SIGNIN and SIGNIN-WIN lines (the block above)
} catch { 'RESULT not-connected ' + $_.Exception.GetType().Name; exit 2 }
$record = Read-RestoreRecord
$info = @{ Lists = @{}; ById = @{} }; $names = @($Lists -split '\|')
for ($i = 1; $i -le $names.Count; $i++) { $state = Read-RestoreList $i $names[$i - 1]
  if ($state -is [hashtable]) { $info.Lists[$i] = $state; $info.ById[$state.Id] = $i } elseif ($state) { $state } }   # a PLAN line comes back as text
$keys = @($info.Lists.Keys | Sort-Object)
Find-BinRows
Write-PlanLines
if ($Mode -ne 'write') { 'RESULT plan'; exit 0 }
if (-not (Test-SameAsPlan)) { 'RESULT changed'; exit 4 }
if ($BackupFolder) {
  function ConvertTo-PlainBackupValue($V) {
    if ($V -is [datetime]) { return $V.ToUniversalTime().ToString('o') }
    if (($null -eq $V) -or ($V -is [string]) -or ($V -is [ValueType])) { return $V }
    $p = $V.PSObject.Properties
    if ($p['LookupId']) { return ([string]$V.LookupId + ';#' + [string]$V.LookupValue) }
    if ($p['Url']) { return ([string]$V.Url + ';#' + [string]$V.Description) }
    if ($p['TermGuid']) { return ([string]$V.Label + '|' + [string]$V.TermGuid) }
    if ($p['Latitude']) { return ('POINT(' + [string]$V.Longitude + ' ' + [string]$V.Latitude + ')') }
    if ($V -is [System.Collections.IEnumerable]) { return ((@(foreach ($x in $V) { ConvertTo-PlainBackupValue $x }) | ForEach-Object { [string]$_ }) -join ';#') }
    return [string]$V
  }
  for ($bi = 1; $bi -le $names.Count; $bi++) {
    try {
      $script:bItems = @()
      $null = & { $script:bItems = @(Get-PnPListItem -List $names[$bi - 1] -PageSize $PageSize -ErrorAction Stop) } *>&1
      $bRows = @(foreach ($it in $script:bItems) { $o = [ordered]@{}; foreach ($fk in @($it.FieldValues.Keys)) { $o[$fk] = ConvertTo-PlainBackupValue $it.FieldValues[$fk] }; [pscustomobject]$o })
      $bj = Join-Path $BackupFolder ('~' + $bi + '.json'); $bc = Join-Path $BackupFolder ('~' + $bi + '.csv')
      [System.IO.File]::WriteAllText($bj, (ConvertTo-Json -InputObject @($bRows) -Depth 4), (New-Object System.Text.UTF8Encoding $true))
      if ($bRows.Count) { $bRows | Export-Csv -LiteralPath $bc -NoTypeInformation -Encoding UTF8 } else { [System.IO.File]::WriteAllText($bc, '') }
      'BACKUP ' + $bi + ' ' + $bRows.Count
    } catch { 'BACKUP ' + $bi + ' failed ' + $_.Exception.GetType().Name; 'RESULT backup-failed'; exit 6 }
  }
}
$pauseSwitch = Set-PauseOn; if ($pauseSwitch) { 'PAUSE on' }   # the function gives back only the switch: its line is printed here
$script:stopMake = $false; $script:mapStop = $false
try {
  Restore-BinRows
  foreach ($k in (Get-ListOrder)) { $state = $info.Lists[$k]; $state.Made = 0; $state.Failed = 0; $state.Skipped = 0; $state.Unlinked = 0
    if (-not ($script:stopMake -or $script:mapStop)) { Add-MissingRows $state } }   # a list not read again, or a record not saved: no new row
  # R7 (counts only): the rows on each list after the write.
  foreach ($k in $keys) { $state = $info.Lists[$k]; $count = -1; try { $count = (Read-ListIds $state.Name).Count } catch { $count = -1 }   # -1: not read
    'DONE ' + $k + ' before=' + $state.Before + ' bin=' + $state.FromBin + ' made=' + $state.Made +
      ' failed=' + $state.Failed + ' skipped=' + $state.Skipped + ' binfailed=' + $state.BinFailed + ' unlinked=' + $state.Unlinked + ' now=' + $count }
} finally {
  if ($pauseSwitch) { $back = @{ $pauseSwitch.Field = $pauseSwitch.Old }
    try { $null = & { Set-PnPListItem -List $pauseSwitch.List -Identity $pauseSwitch.Row.Id -Values $back -ErrorAction Stop } *>&1; 'RESUME ok' }
    catch { 'RESUME failed' } } }
if ($script:mapStop) { 'RESULT map-write-failed'; exit 8 }
if ($script:stopMake) { 'RESULT reread-failed'; exit 7 }
'RESULT done'; exit 0
'@
$restoreScript = Add-SignInSize $restoreScript   # E3: the sign-in block (16-site-scripts.ps1)

# RADE engine part 15, the Maintenance tool Restore, the functions the window and the text mode call (moved out of
# engine/ps/14-restore.ps1 to keep each file at 450 lines or fewer; fleet v2 DEC 6): the backups Restore can use, the
# local test-site mark, the dry run and the write. Part 14 holds the child script ($restoreScript) these functions run.
# Uses parts 01 to 08, 13, 14 and 16 (Get-SiteUrl, Test-SiteUrl, Get-SiteMark, Invoke-ChildScript, Get-BackupFileName,
# $restoreScript, $restoreWriteSeconds, $backupSetMax).
# Network: through the child script of part 14 only (the saved site; AGENTS.md "No reconnaissance").
# Writes: through the child script of part 14 (site rows, after the typed confirm); on the computer, a fresh backup,
#   Backups\~restore-map-<site hash>.json and, from the mark card, Config\<prefix>-restore-test-site.txt.
# Credentials: the interactive CAC sign-in of PnP (-UseWebLogin), in the child script.
# Joined into every bundle by engine/rade_build.py, right after part 14; Windows PowerShell 5.1.

<#
.SYNOPSIS
Gives the backups on this computer that Restore can use, newest first ($backupSetMax at most).
.DESCRIPTION
A backup is a folder in Backups that holds the JSON file of at least one list the manifest names ("backup").
.PARAMETER Base
The RADE app folder.
.OUTPUTS
A list of @{ Path; Name (the folder name, its time); Lists (how many named lists it holds) }.
#>
function Get-BackupSet([string]$Base) {
  $root = Join-Path $Base 'Backups'; if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
  $out = @()
  foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name -Descending)) {
    $count = @($script:app.Backup | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $folder.FullName ((Get-BackupFileName $_) + '.json')) -PathType Leaf) }).Count
    if ($count) { $out += @{ Path = $folder.FullName; Name = $folder.Name; Lists = $count } }
    if ($out.Count -ge $backupSetMax) { break } }
  return $out
}

# ---- The local test-site mark (engine-v32; the Administrator, 2026-11-21): an app whose manifest gives
# "restore.testSites": "local" names no site (a public repo must not hold it). The person marks the saved site as a test
# site on this computer, on the card where they type its name; the mark is Config\@@PREFIX@@-restore-test-site.txt in
# the app folder, next to the site address (Config\@@PREFIX@@-site.txt), never in a repo.
# Gives the path of the mark file. Takes the app folder.
function Get-RestoreMarkFile([string]$Base) { return (Get-ConfigFile $Base '@@PREFIX@@-restore-test-site.txt') }
# Gives the site name the mark holds, or '' (no mark, or a file that cannot be read). Takes the app folder.
function Get-RestoreMark([string]$Base) {
  $p = Get-RestoreMarkFile $Base
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
  try { return ([string](Get-Content -LiteralPath $p -TotalCount 1)).Trim() } catch { return '' } }
# Saves the mark: the site name, one line. Throws when it cannot. Takes the app folder and the site name.
function Save-RestoreMark([string]$Base, [string]$Name) {
  $p = Get-RestoreMarkFile $Base; $dir = Split-Path -Parent $p
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  [System.IO.File]::WriteAllText($p, ($Name.Trim() + "`r`n"), (New-Object System.Text.UTF8Encoding $true)) }
# Removes the mark (engine-v33; the Administrator, 2026-11-21): Restore then asks for the site name again. Throws when
# the file is there and cannot be removed. Takes the app folder.
function Clear-RestoreMark([string]$Base) {
  $p = Get-RestoreMarkFile $Base; if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-Item -LiteralPath $p -Force -ErrorAction Stop } }
<#
.SYNOPSIS
Diagnose's line about the local test-site mark (engine-v33; the Administrator, 2026-11-21: one NOTE line).
.DESCRIPTION
Only for an app with "testSites": "local". A NOTE, never a FINDING: no mark is a normal state. Names no site (the
report is saved on the computer).
.PARAMETER Base
The RADE app folder.
.OUTPUTS
A ConvertTo-ToolLine table, or $null for an app without the local mark.
#>
function Get-RestoreMarkNote([string]$Base) {
  if (-not ($script:app.Restore -and $script:app.Restore.Local)) { return $null }
  $site = Get-SiteUrl $Base; $mark = Get-RestoreMark $Base
  if (-not (Test-SiteUrl $site)) { return (ConvertTo-ToolLine 'NOTE' 'Restore test-site mark: no site address is saved' 'Select "Repair": its checks ask for the site address') }
  $name = $site.Substring($sitePrefix.Length).TrimEnd('/')
  if (-not $mark) { return (ConvertTo-ToolLine 'NOTE' 'Restore test-site mark: the saved site is not marked, so Restore asks for its name first' '') }
  $off = 'To take the mark off, select Restore, then "Remove test-site mark"'
  if ($mark -eq $name) { return (ConvertTo-ToolLine 'NOTE' 'Restore test-site mark: the saved site is marked as a test site on this computer' $off) }
  return (ConvertTo-ToolLine 'NOTE' 'Restore test-site mark: the mark on this computer is for another site, so Restore asks for the name of the saved site first' '')
}

<#
.SYNOPSIS
Says whether Restore may write on the saved site: the app names Restore ("restore") and the site is one of its test
sites, or (with "testSites": "local") the site is marked as a test site on this computer.
.DESCRIPTION
Restore runs only on a test site (the Administrator, 2026-11-20 and 2026-11-21). The site name is the part of the saved
address after the site prefix, compared without case. With a list of names, the site must be in it; with "local", the
mark (Get-RestoreMark) must hold this site's name. A mark of another site does not count.
.PARAMETER Base
The RADE app folder.
.OUTPUTS
@{ Ok; Site; Name; NeedMark; Lines }: Ok is $true when Restore may run; Name is the site name; NeedMark is $true when
only the mark is missing (the window then shows the mark card); Lines say why not.
#>
function Test-RestoreSite([string]$Base) {
  $restoreDef = $script:app.Restore
  if (-not $restoreDef) { return @{ Ok = $false; Site = ''; Name = ''; NeedMark = $false; Lines = @(($script:app.Name + ' does not use Restore in this version.'), 'Nothing was changed.') } }
  $site = Get-SiteUrl $Base
  if (-not (Test-SiteUrl $site)) { $why = @('No site address is saved, so Restore did not sign in.', 'Select "Repair": its checks ask for the site address.')
    return @{ Ok = $false; Site = ''; Name = ''; NeedMark = $false; Lines = $why } }
  $name = $site.Substring($sitePrefix.Length).TrimEnd('/')
  if ($restoreDef.Local) {
    if ((Get-RestoreMark $Base) -eq $name) { return @{ Ok = $true; Site = $site; Name = $name; NeedMark = $false; Lines = @() } }
    $why = 'Restore runs only on a site marked as a test site on this computer. The saved site is not marked.'
    return @{ Ok = $false; Site = $site; Name = $name; NeedMark = $true; Lines = @($why, 'Nothing was changed.') } }
  if (@($restoreDef.TestSites | Where-Object { [string]$_ -eq $name }).Count) { return @{ Ok = $true; Site = $site; Name = $name; NeedMark = $false; Lines = @() } }
  $why = 'Restore runs only on a test site that the app names. The saved site is not one.'
  return @{ Ok = $false; Site = $site; Name = $name; NeedMark = $false; Lines = @($why, 'Nothing was changed.') }
}

# Reads the PLAN lines of the Restore child script: one table for each list number. Takes the output lines; gives
# back @{ <n> = @{ Saved; Now; Missing; Bin; New; After; Unsure; Sig } or @{ Error } }.
function Read-RestorePlan([string[]]$Lines) {
  $plans = @{}
  foreach ($line in $Lines) {
    if ($line -match '^PLAN (\d+) saved=(\d+) now=(\d+) missing=(\d+) bin=(\d+) new=(\d+) after=(\d+) unsure=(\d+) sig=([0-9a-f]+)$') {
      $plans[[int]$Matches[1]] = @{ Saved = [int]$Matches[2]; Now = [int]$Matches[3]; Missing = [int]$Matches[4]; Bin = [int]$Matches[5]
        New = [int]$Matches[6]; After = [int]$Matches[7]; Unsure = [int]$Matches[8]; Sig = $Matches[9] } }
    elseif ($line -match '^PLAN (\d+) (.+)$') { $plans[[int]$Matches[1]] = @{ Error = $Matches[2] } } }
  return $plans
}
# The -MapFile argument of the Restore child script: Backups\~restore-map-<site hash>.json in the app folder, one record
# for every backup of this app on that site (reviews of PR 151: a map per backup folder let two backups make the same row
# twice; a map for every site would mix two sites' IDs). Takes the app folder and the site address.
function Get-RestoreMapArg([string]$Base, [string]$Site) {
  return (' -MapFile "' + (Join-Path (Join-Path $Base 'Backups') ('~restore-map-' + (Get-SiteMark $Site) + '.json')) + '"') }
# The words for a sign-in or tool stop of a child script. Takes the RESULT word and the child's Why.
function Get-ChildStopText([string]$Res, [string]$Why) {
  switch ($Res) { 'no-pnp' { return 'the SharePoint tool is not installed' } 'not-connected' { return 'the sign-in did not finish' }
    'reread-failed' { return 'a list could not be read again after the Recycle Bin, so no new row was made' }
    'map-write-failed' { return 'the record of re-made rows could not be saved, so Restore stopped making new rows' }
    default { return ('it stopped: ' + $(if ($Why) { $Why } else { 'no result' })) } } }

<#
.SYNOPSIS
Restore, the dry run (R4): reads the site and says, for each list, what Restore would put back. Writes nothing.
.PARAMETER Base
The RADE app folder.
.PARAMETER Dir
The backup folder (from Get-BackupSet).
.PARAMETER Tick
Run while the sign-in and the reads go on, or $null.
.OUTPUTS
@{ State; Lines; Plan; Expect; Missing }: State is plan, refused or failed; Lines are plain report lines (counts only);
Plan is Read-RestorePlan's table; Expect is the hash of the missing and Recycle Bin rows per list ("1:<hex>,2:<hex>")
the write checks again; Missing is the total.
#>
function Invoke-RestorePlan([string]$Base, [string]$Dir, [scriptblock]$Tick) {
  $siteCheck = Test-RestoreSite $Base
  if (-not $siteCheck.Ok) { return @{ State = 'refused'; Lines = $siteCheck.Lines; Plan = @{}; Expect = ''; Missing = 0 } }
  $lists = @($script:app.Backup | Where-Object { $_ })
  $argText = '-Site "' + $siteCheck.Site + '" -Folder "' + $Dir + '" -Lists "' + ($lists -join '|') + '" -Mode plan' + (Get-RestoreMapArg $Base $siteCheck.Site)
  $child = Invoke-ChildScript $restoreScript $argText $toolReadSeconds $Tick $signInStageSeconds   # engine-v43 S1: a frozen sign-in stops after 3 minutes
  $null = Get-SignInNote 'Restore dry run' $child.Lines
  $res = ''; foreach ($line in $child.Lines) { if ($line -match '^RESULT (\S+)') { $res = $Matches[1] } elseif ($line -eq 'MAP failed') { $res = 'map' } }
  $stop = $(if ($res -eq 'map') { "the record of an earlier Restore on this site (Backups\~restore-map-*.json) could not be read" } else { Get-ChildStopText $res $child.Why })
  if ($res -ne 'plan') { return @{ State = 'failed'; Plan = @{}; Expect = ''; Missing = 0; Lines = @(('The dry run did not finish: ' + $stop + '.'), 'Nothing was changed.') } }
  $plan = Read-RestorePlan $child.Lines; $lines = @(); $exp = @(); $tot = 0; $fromBinTotal = 0; $newTotal = 0
  for ($i = 1; $i -le $lists.Count; $i++) {
    $listName = [string]$lists[$i - 1]; $item = $plan[$i]
    if (-not $item) { $lines += ('NOTE: "' + $listName + '": no result'); continue }
    if ($item.Error) { $why = $(switch -regex ($item.Error) { '^nofile' { 'this backup has no file for it' } '^nolist' { 'the list is not on the site (Restore does not make lists)' }
          default { 'it could not be read (' + ($item.Error -replace '^failed ', '') + ')' } })
      $lines += ('NOTE: "' + $listName + '" is left out: ' + $why); continue }
    $exp += ([string]$i + ':' + $item.Sig); $tot += $item.Missing; $fromBinTotal += $item.Bin; $newTotal += $item.New
    $lines += ('"' + $listName + '": ' + $item.Saved + ' in the backup, ' + $item.Now + ' on the list now. Would put back ' + $item.Missing +
      ' (' + $item.Bin + ' from the Recycle Bin, ' + $item.New + ' as new rows). ' + $item.After + ' made after the backup stay.')
    if ($item.Unsure) { $lines += ('NOTE: "' + $listName + '": ' + $item.Unsure + ' row(s) are left out: an earlier Restore wrote them but did not confirm it. Check the list by hand') } }
  $head = @(('Dry run: ' + $tot + ' rows would come back (' + $fromBinTotal + ' from the Recycle Bin, ' + $newTotal + ' as new rows). Nothing was written.'))
  if (@($child.Lines | Where-Object { $_ -like 'BIN failed*' }).Count) { $head += 'NOTE: the Recycle Bin could not be read, so every missing row would come back as a new row (a new ID).' }
  return @{ State = 'plan'; Plan = $plan; Expect = ($exp -join ','); Missing = $tot; Lines = @($head + $lines) }
}

<#
.SYNOPSIS
Restore, the write: a fresh backup (R3), the pause switch on (R2), the Recycle Bin (R1), new rows in dependency order
with lookups re-pointed (R5), the pause switch back, then the row count of each list.
.DESCRIPTION
Runs only after the user typed the app name on the dry-run card, and only on a test site. Writes missing rows only: a
row on the list is never changed, and a row made after the backup stays (the Administrator, 2026-11-21). The site must
be as the dry run saw it (the same missing and Recycle Bin rows per list), else nothing is written.
.PARAMETER Base
The RADE app folder.
.PARAMETER Dir
The backup folder the dry run used.
.PARAMETER Plan
The result of Invoke-RestorePlan.
.PARAMETER Tick
Run while the run goes on, or $null.
.OUTPUTS
@{ State; Lines; Path }: State is done, failed, changed or refused; Path is the fresh backup folder or ''.
#>
function Invoke-Restore([string]$Base, [string]$Dir, $Plan, [scriptblock]$Tick) {
  $siteCheck = Test-RestoreSite $Base
  if (-not $siteCheck.Ok) { return @{ State = 'refused'; Path = ''; Lines = $siteCheck.Lines } }
  if (-not $Plan -or $Plan.State -ne 'plan' -or -not $Plan.Missing) { return @{ State = 'failed'; Path = ''; Lines = @('There are no rows to put back.', 'Nothing was changed.') } }
  $lists = @($script:app.Backup | Where-Object { $_ }); $pause = $script:app.Restore.Pause
  $freshDir = Get-NewBackupDir $Base (Get-ToolStamp)   # F4c.1: fresh backup runs inside the same sign-in session as Restore write
  if (-not $freshDir) { return @{ State = 'failed'; Path = ''; Lines = @('Restore wrote nothing: could not make the fresh backup folder on this computer.') } }
  $pauseArg = $(if ($pause) { ' -Pause "' + $pause.List + '|' + $pause.Title + '|' + $pause.Field + '|' + $pause.On + '"' } else { '' })
  $child = Invoke-ChildScript $restoreScript ('-Site "' + $siteCheck.Site + '" -Folder "' + $Dir + '" -Lists "' + ($lists -join '|') + '" -Mode write -Expect "' + $Plan.Expect + '"' + $pauseArg +
    (Get-RestoreMapArg $Base $siteCheck.Site) + ' -BackupFolder "' + $freshDir + '"') $restoreWriteSeconds $Tick $signInStageSeconds   # engine-v43 S1
  $null = Get-SignInNote 'Restore' $child.Lines
  $res = ''; $done = @{}; $resume = ''; $binErr = @{}; $bkGot = @{}
  foreach ($line in $child.Lines) { if ($line -match '^RESULT (\S+)') { $res = $Matches[1] } elseif ($line -match '^DONE (\d+) (.+)$') { $done[[int]$Matches[1]] = $Matches[2] }
    elseif ($line -match '^RESUME (\S+)') { $resume = $Matches[1] } elseif ($line -match '^BINERR (\d+) ([A-Za-z0-9_.]+)$') { $binErr[[int]$Matches[1]] = $Matches[2] }
    elseif ($line -match '^BACKUP (\d+) (.+)$') { $bkGot[[int]$Matches[1]] = $Matches[2] } }
  $bkOk = $true
  if ($res -in 'changed', 'paused-already', 'no-pause-row', 'pause-failed', 'backup-failed' -or $child.Stage) { $null = Clear-BackupDir $freshDir; $bkOk = $false }
  else { for ($bi = 1; $bi -le $lists.Count; $bi++) { if ([string]$bkGot[$bi] -notmatch '^\d+$' -or -not (Rename-BackupFile $freshDir $bi (Get-BackupFileName ([string]$lists[$bi - 1])))) { $bkOk = $false } } }
  $freshLine = $(if ($bkOk) { 'Fresh backup before Restore: ' + (ConvertTo-Masked $freshDir) } else { 'Fresh backup before Restore: not saved.' })
  $stop = $(switch ($res) { 'changed' { 'the site changed after the dry run. Run Restore again for a new dry run' }
      'backup-failed' { 'the fresh backup before it did not save every list' }
      'paused-already' { 'the pause switch is on already (another Restore, or it was left on). Check it, then run Restore again' }
      'no-pause-row' { "the app's pause-switch row is not on the site" } 'pause-failed' { 'the pause switch could not be set' } default { '' } })
  if (-not $stop -and $child.Stage) { $stop = 'the sign-in did not finish in ' + [int]($signInStageSeconds / 60) + ' minutes, so RADE stopped it' }   # engine-v43 S1
  if ($stop) { return @{ State = $(if ($res -eq 'changed') { 'changed' } else { 'failed' }); Path = ''; Lines = @(('Restore wrote no rows: ' + $stop + '.'), 'Nothing on the site changed.') } }
  $lines = @(); $bad = 0; $back = 0
  for ($i = 1; $i -le $lists.Count; $i++) {
    $listName = [string]$lists[$i - 1]; $doneText = [string]$done[$i]; $item = $Plan.Plan[$i]
    if (-not $item -or $item.Error) { continue }
    if ($doneText -notmatch '^before=(\d+) bin=(\d+) made=(\d+) failed=(\d+) skipped=(\d+) binfailed=(\d+) unlinked=(\d+) now=(-?\d+)$') {
      $bad++; $lines += ('FINDING: "' + $listName + '": no result. What to do: compare the list with the backup'); continue }
    $before = [int]$Matches[1]; $fromBin = [int]$Matches[2]; $made = [int]$Matches[3]; $notConfirmed = [int]$Matches[4]; $skipped = [int]$Matches[5]
    $binFailed = [int]$Matches[6]; $unlinkedCount = [int]$Matches[7]; $now = [int]$Matches[8]
    $back += $fromBin + $made
    $want = $before + $fromBin + $made; $ok = ($notConfirmed -eq 0 -and $skipped -eq 0 -and $binFailed -eq 0 -and $now -eq $want)
    $txt = '"' + $listName + '": ' + $fromBin + ' back from the Recycle Bin, ' + $made + ' made new; ' + $now + ' rows on the list now'
    if ($unlinkedCount) { $txt += '; ' + $unlinkedCount + ' lookup value(s) left empty (the row they pointed to is not there)' }
    if ($ok) { $lines += ('PASS: ' + $txt); continue }
    $notConfirmedText = $(if ($notConfirmed) { '; ' + $notConfirmed + ' row(s) not confirmed (they may be on the list; Restore never makes them again)' } else { '' })
    if ($skipped) { $notConfirmedText += '; ' + $skipped + ' row(s) not written: a saved value could not be read (the next dry run offers them again)' }
    if ($binFailed) { $notConfirmedText += '; ' + $binFailed + ' row(s) did not come back from the Recycle Bin (' + $(if ($binErr[$i]) { $binErr[$i] } else { 'error' }) +
        '), so Restore made them as new rows with new row numbers' }   # E2 (R42): a planned Recycle Bin row made new is never a PASS
    $bad++; $lines += ('FINDING: ' + $txt + $notConfirmedText + '. What to do: compare the list with the backup') }
  if ($res -ne 'done') { $bad++
    $lines += ('FINDING: Restore stopped before the end: ' + (Get-ChildStopText $res $child.Why) + '. What to do: run Restore again (it puts back only what is still missing)') }
  if ($pause -and $resume -ne 'ok') { $bad++; $lines += "FINDING: the pause switch could not be put back. What to do: set it back by hand in the app's settings" }
  $head = @(('Restore put back ' + $back + ' of ' + $Plan.Missing + ' rows. Rows on the lists were not changed.'), $freshLine)
  if ($pause -and $resume -eq 'ok') { $head += "The app's pause switch is back as it was." }
  return @{ State = $(if ($bad) { 'failed' } else { 'done' }); Path = $fresh.Path; Lines = @($head + $lines) }
}
