# RADE engine part 17, Uninstall and its clean-up (engine-v40; engine-v48: moved out of 13-maintenance.ps1 at the C4 cap,
# one job: remove an app). Uninstall runs the app's own Uninstall steps on a test site, after a fresh backup; then the
# clean-up moves the app's files on this computer to the Recycle Bin (docs/engine.md "Maintenance run types").
# Uses parts 01 to 08 and 12 to 15 (Invoke-Backup, Get-ToolStamp: part 13; Test-RestoreSite: part 14).
# Network: the Uninstall steps reach what each step names; RADE itself signs in only for the backup (part 13).
# Writes: the app's step files and Uninstall\made-<time>.json, the install record; the clean-up moves the app folder (or all
# but Backups), the runner copy, the shortcut, the record and, for the last app, RADE\Config and RADE\runners to the Recycle Bin.
# Credentials: none here (the backup and the steps sign in with the CAC).
# Joined into every bundle by engine/rade_build.py (engine/rade_parts.py ENGINE_PARTS); Windows PowerShell 5.1.

# ---- Uninstall (engine-v40; 90-161.Z R43 E3, the Administrator, 2026-11-25; docs/engine.md "Maintenance run types"). RADE gives
# the mode, the card and the record; the app gives the steps (manifest "uninstall": its own steps, never the install
# steps). Test sites only (the Restore gate, Test-RestoreSite). Back up first: a backup that misses a list stops it
# before any step. The steps run with RADE_MODE=uninstall and RADE_MADE (the made list as a JSON file). Answers 1A, 2A,
# 4A of the Administrator (2026-11-25). engine-v48 (DECISIONS 2026-11-26, the Administrator): after every step is done, the clean-up below
# moves the app's files on this computer to the Recycle Bin.

# Says whether Uninstall may run on the saved site: the Restore test-site gate, with Uninstall's own words. Takes the
# app folder; gives back the Test-RestoreSite table (Ok, Site, Name, NeedMark, Lines).
function Test-UninstallSite([string]$Base) {
  $c = Test-RestoreSite $Base
  $c.Lines = @($c.Lines | ForEach-Object { ([string]$_) -replace 'does not use Restore in this version', 'names no test sites, so Uninstall cannot run' -replace '\bRestore\b', 'Uninstall' })
  return $c
}

<#
.SYNOPSIS
Writes the files of the Uninstall steps (their script or hand-step file) into the app folder.
.DESCRIPTION
A step that came with this paste can then run when the installed version is older. Only those files are written: the
rest of the app's local copy stays as it is.
.PARAMETER Base
The RADE app folder.
.OUTPUTS
The number of files written.
#>
function Write-UninstallFile([string]$Base) {
  $n = 0; $utf8Bom = New-Object System.Text.UTF8Encoding $true
  foreach ($k in @($script:app.Uninstall)) { $s = $steps[[int]$k]; if (-not $s.File) { continue }
    foreach ($f in @($files | Where-Object { $_.Dir -eq $s.Dir -and $_.Name -eq $s.File })) {
      $dir = Join-Path $Base $f.Dir; if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
      $path = Join-Path $dir $f.Name
      if ($f.Kind -eq 'text') { [System.IO.File]::WriteAllText($path, (((Expand-SharedBlock $f.Data) -replace "`r?`n", "`r`n") + "`r`n"), $utf8Bom) }
      else { [System.IO.File]::WriteAllBytes($path, [System.Convert]::FromBase64String(($f.Data -replace '\s', ''))) }
      $n++ } }
  return $n
}

# Writes the made list of the install record (every step's "made" items: kind and name, no address) to
# Uninstall\made-<time>.json in the app folder, for the steps (RADE_MADE). Takes the app folder and the time stamp;
# gives back the file path.
function Save-UninstallMade([string]$Base, [string]$Stamp) {
  $e = Read-Installed (Get-InstalledKey $script:app); $made = @()
  if ($e -and $e.steps) { foreach ($n in @($e.steps.Keys)) { foreach ($m in @($e.steps[$n].made)) {
        if ($m) { $made += [ordered]@{ step = [string]$n; kind = [string]$m.kind; name = [string]$m.name } } } } }
  $p = Join-Path (Join-Path $Base 'Uninstall') ('made-' + $Stamp + '.json')
  Write-FileWhole $p (ConvertTo-Json -InputObject @{ schema = 'rade-made/1'; app = [string]$script:app.Name; made = @($made) } -Depth 5)
  return $p
}

<#
.SYNOPSIS
Writes the result of an Uninstall run to the app's install record (answer 2A of the Administrator, 2026-11-25).
.DESCRIPTION
Every Uninstall step done: "installed" is cleared (the app shows as not installed), "uninstalled" keeps the version,
the time and the made list that the steps removed, "steps" is cleared (a new install runs every step again) and
"lastRun" reads UNINSTALLED. Not every step done: "installed" and "steps" stay, and "lastRun" reads NEEDS REVIEW, so
Maintenance offers Uninstall again. Never writes a record of a newer RADE or of another app (S1, S2).
.PARAMETER Whole
$true when every Uninstall step is done.
.PARAMETER Key
The record key, read before the clean-up ('' = read it now): the key of an app with a site marker holds a hash of the
site address, which the clean-up moves to the Recycle Bin with the app folder.
.OUTPUTS
'' or the reason the record could not be saved.
#>
function Save-Uninstalled([bool]$Whole, [string]$Key = '') {
  try {
    $key = $(if ($Key) { $Key } else { Get-InstalledKey $script:app }); $raw = Read-InstalledRaw $key
    $blk = Get-InstalledBlock $script:app $key; if ($blk) { return $blk }
    if ($raw.State -ne 'ok') { return 'there is no install record to change' }
    $old = Read-Installed $key; if (-not $old) { return 'the install record could not be read' }
    $at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    $ver = $(if ($old.installed) { [string]$old.installed.version } else { [string]$script:app.Version })
    $run = [ordered]@{ version = $ver; build = [string]$buildId; round = [string]$round; at = $at; state = $(if ($Whole) { 'UNINSTALLED' } else { 'NEEDS REVIEW' }) }
    $doc = [ordered]@{ schema = 'rade-installed/' + $installedSchema; about = [string]$raw.Json.about; key = $key; installed = $old.installed; lastRun = $run; steps = $old.steps }
    if ($Whole) { $made = @(); foreach ($n in @($old.steps.Keys)) { foreach ($m in @($old.steps[$n].made)) { if ($m) { $made += $m } } }
      $doc.installed = $null; $doc.steps = [ordered]@{}; $doc.uninstalled = [ordered]@{ version = $ver; at = $at; made = @($made) } }
    Write-FileWhole $raw.Path ($doc | ConvertTo-Json -Depth 9)
    return ''
  } catch { return (ConvertTo-Masked $_.Exception.Message) }
}

<#
.SYNOPSIS
Uninstall: the gate, a fresh backup, then the app's Uninstall steps in order, the record and one report file.
.DESCRIPTION
Stops before any step when the site is not a test site or the backup missed a list. A script step runs as a child
process with the step contract and RADE_MODE=uninstall, RADE_MADE (Invoke-RoundStep); a script step that only prints
SKIP found nothing to remove and counts as done. A hand step shows its card (Invoke-GuideStep); Skip there is not done.
The first step that is not done stops the run: the steps after it do not run (they can need it), and nothing on this
computer moves. engine-v48 (DECISIONS 2026-11-26; order: review of engine-v48, MINOR 1): every step done,
Save-Uninstalled first (a record that cannot be saved: nothing moves), then the clean-up (Get-UninstallCleanPlan), then
the record goes to the Recycle Bin (Clear-UninstallRecord). A whole Uninstall writes no report file (the app folder
goes): its lines are the report.
.PARAMETER Base
The RADE app folder.
.PARAMETER Tick
Run while a child script runs (keeps the window alive), or $null.
.PARAMETER OnStep
Called before each step with the step and its number, or $null.
.PARAMETER KeepBackups
$true (the default) keeps the Backups folder of the app folder; $false moves it to the Recycle Bin with the app folder.
.OUTPUTS
@{ State; Lines; Path }: State is refused, no-backup, done or review; Path is the report file, after a whole Uninstall
the Backups folder that stays, or ''.
#>
function Invoke-Uninstall([string]$Base, [scriptblock]$Tick, [scriptblock]$OnStep, [bool]$KeepBackups = $true) {
  $spMode = [bool]($script:spEnabled -and $script:app.Restore)
  $site = $null; $bk = $null
  if ($spMode) {
    $site = Test-UninstallSite $Base
    if (-not $site.Ok) { return @{ State = 'refused'; Path = ''; Lines = @($site.Lines) } }
  }
  $blk = Get-InstalledBlock $script:app   # a record RADE must not write (newer, another app's, unreadable): no step runs
  if ($blk) { return @{ State = 'refused'; Path = ''; Lines = @(('Uninstall cannot run: ' + $blk + '.'), 'Nothing was changed.') } }   # the record's own reason and what to do
  if ($spMode) {
    $bk = Invoke-Backup $Base $Tick
    $noBk = @('Uninstall removed nothing: the backup did not save every list.', 'Nothing on the site changed. Select "Uninstall" again.')
    if ($bk.State -ne 'done') { return @{ State = 'no-backup'; Path = ''; Lines = @($noBk + @($bk.Lines)) } }
  }
  $stamp = Get-ToolStamp; $log = New-Object System.Collections.Generic.List[string]
  # The log callback of the steps: each line masked, kept for the report. Takes the line.
  $say = { param($t) $log.Add((ConvertTo-Masked ([string]$t))) }
  $lines = $(if ($spMode) {
      @(('Test site: ' + $site.Name), ('Backup: ' + (Split-Path -Leaf $bk.Path) + ' (' + @($script:app.Backup).Count + ' lists)'))
    } else { @('Local-only uninstall (no SharePoint site).') })
  $extra = @{ RADE_MODE = 'uninstall'; RADE_MADE = '' }
  try { $null = Write-UninstallFile $Base; $extra.RADE_MADE = Save-UninstallMade $Base $stamp } catch { & $say ('NOTE: the made list or a step file could not be saved: ' + $_.Exception.Message) }
  $all = @($script:app.Uninstall); $done = 0; $stop = ''
  $script:stepEnvExtra = $extra
  try { for ($i = 0; $i -lt $all.Count; $i++) { $st = $steps[[int]$all[$i]]
      if ($OnStep) { & $OnStep $st ($i + 1) $all.Count }
      & $say ''; & $say ('Uninstall step ' + ($i + 1) + ' of ' + $all.Count + ': ' + $st.Name)
      $t0 = Get-Date
      $r = $(if ($st.Kind -eq 'guide') { Invoke-GuideStep $Base $st $say } else { Invoke-RoundStep $Base $st $say $(if ($Tick) { $Tick } else { {} }) '' })
      $state = Get-StepState $r; $ok = ($state -eq 'PASSED' -or ($state -eq 'SKIPPED' -and $st.Kind -ne 'guide' -and -not $r.Skipped))
      $lines += Get-StepLine $st $r ((Get-Date) - $t0).TotalSeconds
      if ($ok) { $done++; continue }
      $stop = Get-StepTitle $st; break } }
  finally { $script:stepEnvExtra = $null }
  $whole = ($done -eq $all.Count)
  $left = $all.Count - $done - 1; if (-not $whole -and $left -gt 0) { $lines += ('Not run: ' + $left + ' step(s) after "' + $stop + '".') }
  $key = Get-InstalledKey $script:app; $tally = @{ Moved = @{}; Bad = New-Object System.Collections.Generic.List[string] }; $cl = @()   # the key before the clean-up
  # Review of engine-v48 (MINOR 1): the record first. It needs nothing the clean-up moves; if it cannot be saved, nothing moves.
  $sv = Save-Uninstalled $whole $key; $noRec = [bool]($sv -and $whole)
  if ($sv) { $lines += ('NOTE: the install record could not be saved: ' + $sv); $whole = $false }   # the record still says installed: every file stays
  # A whole Uninstall ends saved progress of this round too: a later install must not resume and keep steps whose items are gone.
  if ($whole) { $cs = Clear-RoundState $Base; if ($cs) { $lines += ('NOTE: the saved progress of this round could not be removed: ' + $cs) }
    $plan = Get-UninstallCleanPlan $Base $KeepBackups $key; foreach ($r in @($plan.Refused)) { $tally.Bad.Add($r) }; Invoke-CleanItem $plan.Items $tally
    Clear-UninstallRecord $key $tally; $cl = @(Get-CleanLine $tally $Base) }
  $head = $(if ($whole) { $script:app.Name + ' is uninstalled from the test site. ' + $done + ' of ' + $all.Count + ' steps done.' }
    elseif ($noRec) { 'Every Uninstall step is done, but RADE could not save the install record. Nothing on this computer was moved.' }
    else { 'Uninstall stopped at "' + $stop + '". ' + $done + ' of ' + $all.Count + ' steps done.' })
  $tail = $(if ($whole) { $cl[0] }
    elseif ($noRec) { 'Select "Uninstall" again: RADE saves a backup, runs the steps again and tries to save the record.' }
    else { 'Read the report, fix the cause, then select "Uninstall" again. The backups stay on this computer.' })
  if ($whole) { $cl = @($cl | Select-Object -Skip 1) }
  $p = ''; $bk = Join-Path $Base 'Backups'
  if ($whole) { if (Test-Path -LiteralPath $bk -PathType Container) { $p = $bk } }   # the folder that stays; no report file: the clean-up took the app folder
  elseif (Test-Path -LiteralPath $Base -PathType Container) {
    try { $p = Join-Path (Join-Path $Base 'Uninstall') ('uninstall-' + $stamp + '.txt')
      Write-FileWhole $p ((@($head, '') + $lines + @('', 'Log:') + @($log) -join "`r`n") + "`r`n") } catch { $p = '' } }
  return @{ State = $(if ($whole) { 'done' } else { 'review' }); Path = $p; Lines = @(@($head, $tail) + $cl + $lines) }
}

# ---- Uninstall clean-up (engine-v48; DECISIONS 2026-11-26 "Remove RADE and Uninstall", the Administrator; plan
# docs/reviews/2026-11-27-plan-engine-v48-ui.md step 6). RADE is never installed by itself: each app's Uninstall cleans
# this computer. After every Uninstall step is done: the app folder (all of it, or all but Backups, as the person
# picks), the app's runner copy and its shortcut go to the Recycle Bin; after the record is saved, the record goes too;
# the last app's Uninstall (no other install record) also moves RADE's shared files. It replaces "Remove RADE" of
# engine-v40. Everything goes to the Recycle Bin (Move-ToRecycleBin), never a permanent delete. Nothing outside the RADE
# folder moves, except the app's own shortcut (RADE made it and recorded it).

# Says whether a path is inside the RADE folder (never the RADE folder itself). Takes the path; gives back $true or $false.
function Test-InRadeFolder([string]$Path) {
  try { $root = [System.IO.Path]::GetFullPath((Get-RadePath)).TrimEnd('\', '/'); $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    return $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) } catch { return $false }   # a path it cannot read is not in the folder
}

# Says whether a folder name is a plain app folder name: letters, digits, space, ".", "_", "-", starting and ending with a
# letter, digit, "_" or "-" (so Windows cannot trim it to another name; review of PR 194), and not Config, Backups or
# runners (RADE's own folders). Takes the name; gives back $true or $false.
function Test-RadeAppName([string]$Name) { return ($Name -cmatch '^[A-Za-z0-9]([A-Za-z0-9 ._-]*[A-Za-z0-9_-])?$' -and $Name -notin 'Config', 'Backups', 'runners') }

# Gives the keys of the other install records in RADE\Config\installed: every file but this app's record and its
# .damaged copies. A file that cannot be read gives "?" (it can be any app). Takes this app's record key.
function Get-OtherRecordKey([string]$Key) {
  $dir = Get-RadeConfigFile 'installed'; $own = (Get-ShortHash $Key) + '.json'; $out = @()
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
  foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue)) {
    if ($f.Name.StartsWith($own, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    $k = ''; try { $k = [string](([System.IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json).key) } catch { $k = '' }   # a file it cannot read counts as another app
    $out += $(if ($k) { $k } else { '?' }) }
  return $out
}

# Gives the chosen app's own shortcut: the .lnk file RADE recorded (RADE\runners\<key>.lnk.txt) that starts this app's
# runner copy, or '' (a shortcut that RADE did not make, or that it cannot read, stays). Takes nothing.
function Get-OwnShortcut {
  $l = Get-AppShortcut; if (-not $l -or $l -notmatch '\.lnk$') { return '' }
  # SECURITY-REVIEWER: Read-only WScript.Shell shortcut inspection verifies this .lnk targets only the local user's $runner under OneDrive\RADE\runners\ before uninstall cleanup.
  try { if (([string](New-Object -ComObject WScript.Shell).CreateShortcut($l).Arguments).Contains('"' + (Get-RunnerPath) + '"')) { return $l } } catch { $null = $_ }   # not readable: not RADE's
  return ''
}

<#
.SYNOPSIS
Gives what the Uninstall clean-up moves to the Recycle Bin (the app's files on this computer), and what it refuses.
.DESCRIPTION
The app folder: all of it, or every item in it but Backups when the person keeps the Backups folder. Only a folder
right under the RADE folder with a plain name (Test-RadeAppName) that no other install record names: two apps of one
paste share the folder (record key "<folder>/<app>"). The runner copy (RADE\runners\<key>.ps1, .ico, .lnk.txt) and the
shortcut RADE recorded, while no other record of this app (another site) uses them. The record and the shared files
come after Save-Uninstalled (Clear-UninstallRecord).
.PARAMETER Base
The RADE app folder.
.PARAMETER KeepBackups
$true keeps the Backups folder.
.PARAMETER Key
This app's record key.
.OUTPUTS
@{ Items; Refused }: Items are @{ P (path); F (a folder); Kind; N (its name in a line); Ask (the app folder: Windows asks before a delete for good) }; Refused are "Not moved" lines.
#>
function Get-UninstallCleanPlan([string]$Base, [bool]$KeepBackups, [string]$Key) {
  $items = @(); $no = @(); $others = @(Get-OtherRecordKey $Key); $name = [string]$script:app.Name
  $root = [System.IO.Path]::GetFullPath((Get-RadePath)).TrimEnd('\', '/'); $bp = [System.IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
  $sameDir = @($others | Where-Object { $_ -eq '?' -or ($_ -split '/', 2)[0] -eq $appFolder }).Count
  $sameApp = @($others | Where-Object { $_ -eq '?' -or (($_ -split '/', 2)[0] -eq $appFolder -and (($_ -split '/', 2)[-1] -replace '@[^@]*$', '') -eq $name) }).Count
  if ((Split-Path -Parent $bp) -ne $root -or -not (Test-RadeAppName (Split-Path -Leaf $bp))) {
    $no += ('Not moved: the app folder ' + (ConvertTo-Masked $Base) + '. It is not an app folder in the RADE folder.') }
  elseif ($sameDir) { $no += 'Not moved: the app folder. Another install record on this computer uses it.' }
  elseif (Test-Path -LiteralPath $bp -PathType Container) {
    if (-not $KeepBackups) { $items += @{ P = $bp; F = $true; Kind = 'appdir'; Ask = $true; N = ('the app folder ' + $appFolder) } }   # Ask: review MINOR 3
    else { foreach ($c in @(Get-ChildItem -LiteralPath $bp -Force | Where-Object { $_.Name -ne 'Backups' })) {
        $items += @{ P = $c.FullName; F = [bool]$c.PSIsContainer; Kind = 'app'; N = ($appFolder + '\' + $c.Name) } } } }
  if ($sameApp) { $no += 'Not moved: the runner copy and the shortcut. Another install record of this app uses them.'; return @{ Items = $items; Refused = $no } }
  $lk = Get-OwnShortcut; if ($lk) { $items += @{ P = $lk; F = $false; Kind = 'shortcut'; N = ('the shortcut ' + (Split-Path -Leaf $lk)) } }   # before its .lnk.txt record goes
  $rp = Get-RunnerPath
  foreach ($x in @($rp, [System.IO.Path]::ChangeExtension($rp, '.ico'), (Get-ShortcutRecord))) {
    if (Test-Path -LiteralPath $x -PathType Leaf) { $items += @{ P = $x; F = $false; Kind = 'runner'; N = ('RADE\runners\' + (Split-Path -Leaf $x)) } } }
  return @{ Items = $items; Refused = $no }
}

<#
.SYNOPSIS
Moves each item of a clean-up to the Recycle Bin (Move-ToRecycleBin), after its guard.
.DESCRIPTION
An item must be inside the RADE folder (Test-InRadeFolder); the one exception is the app's own shortcut, a .lnk file
that Get-OwnShortcut checked. An item that fails the guard is refused and named; one that cannot move is named with the
error type; the rest still go.
.PARAMETER Items
The items (P, F, Kind, N; Get-UninstallCleanPlan).
.PARAMETER Tally
@{ Moved (kind to count); Bad (a list of lines) }: the counts and lines are added here.
.OUTPUTS
None.
#>
function Invoke-CleanItem($Items, $Tally) {
  foreach ($i in @($Items | Where-Object { $_ })) {
    $ok = $(if ($i.Kind -eq 'shortcut') { [string]$i.P -match '\.lnk$' } else { Test-InRadeFolder $i.P })
    if (-not $ok) { $Tally.Bad.Add('Not moved: ' + $i.N + '. It is not in the RADE folder.'); continue }
    # A cancel of the question of Windows (-AskFirst) leaves the item; GetBaseException finds the cancel in the wrapper.
    try { Move-ToRecycleBin $i.P -Folder:([bool]$i.F) -AskFirst:([bool]$i.Ask); $Tally.Moved[$i.Kind] = 1 + [int]$Tally.Moved[$i.Kind] }
    catch { $ty = $_.Exception.GetBaseException().GetType().Name   # a .NET error comes wrapped (MethodInvocationException)
      $Tally.Bad.Add($(if ($ty -eq 'OperationCanceledException') { 'Not moved: ' + $i.N + '. You canceled the move.' } else { 'Not moved: ' + $i.N + ' [' + $ty + ']' })) } }
}

<#
.SYNOPSIS
Moves the app's install record to the Recycle Bin, and after the last app's Uninstall RADE's shared files too.
.DESCRIPTION
Runs after Save-Uninstalled saved the record. The last app: no other file is in RADE\Config\installed (a record that
cannot be read counts as another app). Then RADE\Config, RADE\runners and the old RADE\rade-runner.ps1 go; another
folder in the RADE folder and the RADE folder itself stay.
.PARAMETER Key
This app's record key.
.PARAMETER Tally
The counts and lines of the clean-up (Invoke-CleanItem).
.OUTPUTS
None.
#>
function Clear-UninstallRecord([string]$Key, $Tally) {
  $rec = Get-InstalledFile $Key; Invoke-CleanItem @(@{ P = $rec; F = $false; Kind = 'record'; N = 'the install record' }) $Tally
  if ((Test-Path -LiteralPath $rec) -or @(Get-OtherRecordKey $Key).Count) { return }   # review MINOR 2: a record that did not move is still a record
  $root = Get-RadePath
  $shared = @(@{ P = (Join-Path $root 'Config'); F = $true; Kind = 'shared'; N = 'RADE\Config' }, @{ P = (Join-Path $root 'runners'); F = $true; Kind = 'shared'; N = 'RADE\runners' },
    @{ P = (Join-Path $root 'rade-runner.ps1'); F = $false; Kind = 'shared'; N = 'RADE\rade-runner.ps1' })
  Invoke-CleanItem @($shared | Where-Object { Test-Path -LiteralPath $_.P }) $Tally
  if (-not (Test-Path -LiteralPath $shared[0].P)) { $script:radeConfigGone = $true }   # the window must not write RADE\Config again (part 02)
}

# The words of each kind of item in the clean-up line: one, more than one. In the order of the line.
$cleanKinds = [ordered]@{ appdir = @('app folder', 'app folders'); app = @('item of the app folder', 'items of the app folder'); runner = @('runner copy file', 'runner copy files')
  shortcut = @('shortcut', 'shortcuts'); record = @('install record', 'install records'); shared = @('shared RADE folder or file', 'shared RADE folders and files') }

# Gives the lines of the clean-up for the Done card: what went to the Recycle Bin, by count and kind; where the Backups
# folder is, if it stays; each item that did not move. Takes the tally (Invoke-CleanItem) and the app folder.
function Get-CleanLine($Tally, [string]$Base) {
  $parts = @(foreach ($k in @($cleanKinds.Keys)) { $n = [int]$Tally.Moved[$k]; if ($n) { [string]$n + ' ' + $cleanKinds[$k][[int]($n -gt 1)] } })
  $out = @($(if ($parts.Count) { 'Moved to the Recycle Bin: ' + ($parts -join ', ') + '.' } else { 'Nothing moved to the Recycle Bin.' }))
  $bk = Join-Path $Base 'Backups'
  $out += $(if (Test-Path -LiteralPath $bk -PathType Container) { 'The Backups folder stays on this computer: ' + (ConvertTo-Masked $bk) } else { 'The Backups folder is in the Recycle Bin.' })
  return @($out + @($Tally.Bad))
}
