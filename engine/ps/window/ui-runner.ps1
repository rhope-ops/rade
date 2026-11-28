# RADE window part 07, the run: the callbacks Invoke-Round uses (log line, tick, step state), the Run button,
# and the Done, Needs review and Stopped cards. Uses the card parts and Invoke-Round.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.
# Network: none.
# Writes: none.
# Credentials: none.

# ---- The run. Invoke-Round calls back: a log line ($ui.Say), a tick ($ui.Tick), a step that starts ($ui.OnStatus) and
# a step that ends ($ui.OnStep). A step you do by hand comes in through $script:guideUi, what a step does now through
# $script:nowUi, and the last question of a test round through $script:feedbackUi.
$ui.Say = { param($t)
  Add-RunLog $t; $ui.Log.Add([string]$t)
  if ($ui.RecOn) { try { $ui.RecText.AppendText([string]$t + "`r`n") } catch { $null = $_ } }
  try { [System.Windows.Forms.Application]::DoEvents() } catch { $null = $_ } }
# L7 (the Administrator, 2026-11-19): the now-doing line under the step's bar. The engine calls this ($script:nowUi) with a
# plain sentence for each item a step script reports (Get-NowText) and for a NOW line. Cards v2 (plan engine-v48 step 5):
# the text as written, with no "..." added; it wraps to $ui.NowLines lines and the line keeps its room. Takes the text.
$ui.ShowNow = { param([string]$Text)
  try { if ($ui.View -eq 'run') { $ui.NowRaw = $Text.Trim(); & $ui.CutNow; $ui.Now.Visible = $true } } catch { $null = $_ } }   # a line that cannot show never stops a step
# Shows the whole now-doing text ($ui.NowRaw) in $ui.NowLines lines at the line's wrap width (a text longer than that, over
# the manifest's 80 characters, is cut at the end of the last line); runs again after a resize ($ui.BreakAll). Takes nothing.
$ui.CutNow = {
  try {
    $w = [int](& $ui.GetWrap $ui.Now); $x = [string]$ui.NowRaw
    if ($x) { $x = & $ui.FitLines (& $ui.BreakLong $x $ui.Now.Font $w) $ui.Now.Font $w $ui.NowLines }
    if ([string]$ui.Now.Text -cne $x) { $ui.Now.Text = $x }
  } catch { $null = $_ } }   # a line that cannot show never stops a step
# The engine's callback for the now-doing line (Add-StepLine): shows the text and emits nothing. Takes the text.
$script:nowUi = { param($t) $null = & $ui.ShowNow ([string]$t) }
# L8 (the Administrator, 2026-11-19): a step stays on the Run card for $ui.Layout.StepMs (engine/window.json) at least, so a
# run of fast steps does not flicker. Waits out the rest of that time since the step showed. Takes nothing.
$ui.HoldStep = {
  while ($ui.View -eq 'run' -and $null -ne $ui.StepAt -and -not $script:closing -and
    -not $ui.Form.IsDisposed -and ($ui.Clock.Elapsed.TotalMilliseconds - [double]$ui.StepAt) -lt [double]$ui.Layout.StepMs) {
    [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 15
  } }
# Draws the progress: both bars, the time in the step, the step fraction and the overall percent (the Administrator, 2026-11-19:
# the percent only). Takes nothing; does nothing when no step runs.
$ui.Paint = {
  if (-not $script:prog -or -not $script:stepStart) { return }
  $g = Get-Progress
  $all = [math]::Max($g.All, $ui.Bars['all'].Target); & $ui.SetBar 'all' $all $true; & $ui.SetBar 'run' $all $true; & $ui.SetBar 'step' ([math]::Max($g.StepShown, $ui.Bars['step'].Target)) $true
  if ($ui.View -ne 'run') { return }
  & $ui.ShowTime
  $fr = $(if ($script:prog.Frac -ge 0) { [string]$script:prog.FracText } else { '' }); if ($ui.StepFrac.Text -ne $fr) { $ui.StepFrac.Text = $fr }   # one size ($ui.FixW): the bar keeps its width
  # Cards v2: one percent for the whole run, on the card beside its bar (the bottom line has none).
  $rt = [string][int]($g.All * 100) + ' %'; if ($ui.PctL.Text -ne $rt) { $ui.PctL.Text = $rt } }
# The time in this step (R28 N10): "4m 12s"; with hours "1h 04m 12s".
$ui.Elapsed = { param([double]$Sec) $q = [int][math]::Floor([math]::Max(0, $Sec)); $h = [int][math]::Floor($q / 3600); $m = [int][math]::Floor(($q % 3600) / 60); $x = $q % 60
  if ($h) { return ('{0}h {1:00}m {2:00}s' -f $h, $m, $x) }; return ('{0}m {1:00}s' -f $m, $x) }
# Shows the time in this step on the step line, once for each second. The time keeps one size from its widest value
# ($ui.FixW), so the bar beside it never changes its width. Takes nothing; a failure is ignored.
$ui.ShowTime = {
  try {
    if ($ui.View -eq 'run' -and $script:stepStart) {
      $t = & $ui.Elapsed ((Get-Date) - $script:stepStart).TotalSeconds
      if ($ui.StepTime.Text -ne $t) { $ui.StepTime.Text = $t }
    }
  } catch { $null = $_ } }
$ui.TimeT = New-Object System.Windows.Forms.Timer; $ui.TimeT.Interval = 1000; $ui.TimeT.Add_Tick({ & $ui.ShowTime })
# The tick callback of a running step: repaints the bars and lets the window handle its events. Emits nothing.
$ui.Tick = { $null = & $ui.Paint; [System.Windows.Forms.Application]::DoEvents() }   # a callback must emit nothing: its output would join the engine function's return value
# Returns the title the window shows for a step (its manifest title, else its name). Takes the step name.
$ui.TitleOf = { param([string]$Name) foreach ($s in @($steps)) { if ([string]$s.Name -ceq $Name) { return (Get-StepTitle $s) } }; return $Name }   # the title of the step with this name
# ---- The step list of the Run card (plan engine-v48 step 3, Cards v2). $ui.RunList has one row for each step of this
# run (Clean-up first when it runs): @{ Key (the step name, or 'Clean-up'); Title; Sub (the second line); State }. The
# running row is the tinted $ui.RunRow; the row before it and the rows after it are drawn in $ui.RunA and $ui.RunB.
$ui.RunList = @()
# The status of a row: its word and the token of its color. Takes the state word; gives back @(word, token).
$ui.RunMark = { param([string]$S) switch ($S) { 'PASSED' { @('PASSED', 'GreenInk') } 'DONE' { @('DONE', 'GreenInk') } 'SKIPPED' { @('SKIPPED', 'Gray') }
    'FAILED' { @('FAILED', 'Red') } 'NEEDS REVIEW' { @('NEEDS REVIEW', 'Red') } 'INTERRUPTED' { @('STOPPED', 'Red') } default { @('WAITING', 'Gray') } } }
# Makes the rows of this run from the steps that are on. Takes the selection (one flag for each step); sets $ui.RunList.
$ui.MakeRunList = { param($Sel)
  $ui.RunList = @(); if ($cleanup.Count -and $ui.Clean -and -not $script:resume) {   # a resume runs no clean-up (Invoke-Round)
  $ui.RunList += @{ Key = 'Clean-up'; Title = 'Clean-up'; Sub = ''; State = '' } }
  for ($k = 0; $k -lt $steps.Count; $k++) { if ($Sel[$k]) { $ui.RunList += @{ Key = [string]$steps[$k].Name; Title = (Get-StepTitle $steps[$k]); Sub = [string]$steps[$k].Doing; State = '' } } } }
# The room the Run card has for drawn rows: the card's height less its header, its body without the lists and its
# buttons (each as tall as its parts ask for), so the card never scrolls for its lists (the Windows job of PR 211: fixed
# thresholds made the Run card scroll at 1004 x 577 with long texts). Takes nothing; gives back pixels (0 at least).
$ui.RunRoom = {
  # Returns preferred or current height of a control.
  $ph = { param($C) $h = 0; try { $h = [int]$C.GetPreferredSize((New-Object System.Drawing.Size(0, 0))).Height } catch { $null = $_ }; [math]::Max($h, [int]$C.Height) }   # no measure: its height
  return [int][math]::Max(0, [int]$ui.Card.ClientSize.Height - (& $ph $ui.Head) - (& $ph $ui.Body) - (& $ph $ui.Tail) - (& $ui.Sc $ui.Z.G2)) }
$ui.RunMost = 4   # at most 4 drawn rows beside the running one (the Cards v2 mock: 5 rows in all)
# The width of a drawn row's texts (the row less the status column and the side room). Takes the row width.
$ui.RunTextW = { param([int]$W) [int][math]::Max(1, $W - (& $ui.Sc 120) - 2 * (& $ui.Sc $ui.Z.G2)) }
# The height of one drawn row slot (R35, the Administrator, 2026-11-19: values do not move anything): the tallest row this
# run can have, from the longest name of all its steps (2 lines at most) and a second line of 2 lines, 44 px at least.
# Takes the width; gives back pixels.
$ui.RunSlotOf = { param([int]$W)
  $h1 = & $ui.LineH $ui.F.SmallB; $h2 = & $ui.LineH $ui.F.Small; $tw = & $ui.RunTextW $W; $n1 = 1
  foreach ($x in @($ui.RunList)) { $n1 = [math]::Max($n1, (& $ui.Rows ([string]$x.Title) $ui.F.SmallB $tw $h1 2)) }
  return [int][math]::Max((& $ui.Sc 44), $n1 * $h1 + 2 * $h2 + (& $ui.Sc $ui.Z.G3)) }
$ui.RunCap = @{}; $ui.RunSlotH = 0; $ui.RunN = 0; $ui.RunKey = ''   # the slots of each list, the slot height, the slots in all, the size they are for
# Sizes one drawn list to its slots (not to its rows: a list keeps its height from step to step). Takes the panel.
$ui.SizeRuns = { param($P) $P.Height = [math]::Max(1, [int]$ui.RunCap[$P] * [int]$ui.RunSlotH)
  $P.AccessibleDescription = (@($P.Tag) | ForEach-Object { [string]$_.Title + ': ' + (& $ui.RunMark ([string]$_.State))[0] }) -join '; ' }
# The number of row slots the Run card has room for at this window size (R35: once for a size, again only after a
# resize, so the parts never move from step to step). Takes nothing; sets $ui.RunN, $ui.RunSlotH and $ui.RunKey.
$ui.RunFit = { $key = [string]$ui.Card.ClientSize.Width + 'x' + $ui.Card.ClientSize.Height; if ($ui.RunKey -eq $key) { return }
  foreach ($p in @($ui.RunA, $ui.RunB)) { $ui.RunCap[$p] = 0; $p.Visible = $false }   # first the card with no list: its room ($ui.RunRoom)
  try { $ui.Card.PerformLayout() } catch { $null = $_ }; $ui.RunSlotH = & $ui.RunSlotOf ([int]$ui.RunA.Width)
  $ui.RunN = [int][math]::Min($ui.RunMost, [math]::Floor((& $ui.RunRoom) / [math]::Max(1, $ui.RunSlotH))); $ui.RunKey = $key }
# Puts the rows around the running step into the lists: one slot for the step before it (empty on the first step), the
# other slots for the steps after it. The slots keep their heights from step to step. Takes nothing.
$ui.PlaceRuns = {
  $all = @($ui.RunList); $r = -1; for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i].State -eq 'RUNNING') { $r = $i } }
  $ui.StepSum.Text = $(if ($r -ge 0) { [string]$all[$r].Sub } else { '' }); $ui.StepSum.Visible = $true   # its room is the longest summary ($ui.Range)
  & $ui.RunFit; $na = [int][bool]$ui.RunN; $a = @(); if ($na -and $r -gt 0) { $a = @($all[$r - 1]) }
  $b = @(); for ($i = $r + 1; $i -lt $all.Count -and $b.Count -lt ($ui.RunN - $na); $i++) { $b += $all[$i] }
  $ui.RunA.Tag = $a; $ui.RunB.Tag = $b; $ui.RunCap[$ui.RunA] = $na; $ui.RunCap[$ui.RunB] = $ui.RunN - $na
  foreach ($p in @($ui.RunA, $ui.RunB)) { & $ui.SizeRuns $p; $p.Visible = [bool]$ui.RunCap[$p] }   # only the Run card shows them ($ui.Dress hides them)
  $ui.RunA.Invalidate(); $ui.RunB.Invalidate(); & $ui.Squeeze }
# Marks the step that starts as running, and a row that was running and has no result as done. Takes the step name.
$ui.RunStart = { param([string]$Name) foreach ($x in @($ui.RunList)) { if ($x.State -eq 'RUNNING') { $x.State = 'DONE' } }
  foreach ($x in @($ui.RunList)) { if ([string]$x.Key -ceq $Name) { $x.State = 'RUNNING'; break } } }
# Keeps the result of a step that ended in its row: the state word and the rest of its result line as its second line.
# Takes the step name, the state word and the rest of the line.
$ui.RunEnd = { param([string]$Name, [string]$State, [string]$Rest)
  foreach ($x in @($ui.RunList)) {
    if ([string]$x.Key -ceq $Name) {
      $x.State = $State
      $t = ($Rest.Substring([math]::Min($Rest.Length, $State.Length)) -replace '^[\s:(]+', '' -replace '\)$', '').Trim()
      if ($t) { $x.Sub = $t }
    }
  } }
$ui.PaintRuns = {
  <#
  .SYNOPSIS
  Draws the rows of one step list: a thin line under each row, the name and the second line (2 lines each at most), and at the
  right the status as an icon and a word (PASSED with a tick, WAITING with a ring, FAILED with a cross).
  .PARAMETER P
  The list panel (its Tag holds the rows).
  .PARAMETER G
  Its graphics.
  .OUTPUTS
  Nothing; a failure draws nothing more.
  #>
  param($P, $G)
  try {
    $G.Clear($ui.C.White); $G.SmoothingMode = 'AntiAlias'; $w = $P.ClientSize.Width; $y = 0
    $pad = & $ui.Sc $ui.Z.G2; $mw = & $ui.Sc 120; $h1 = & $ui.LineH $ui.F.SmallB; $h2 = & $ui.LineH $ui.F.Small
    $wrap = 'Left, Top, NoPrefix, WordBreak, EndEllipsis, TextBoxControl'; $ln = New-Object System.Drawing.Pen($ui.C.Hair)
    foreach ($r in @($P.Tag)) { $h = [int]$ui.RunSlotH; $m = & $ui.RunMark ([string]$r.State); $col = $ui.C[[string]$m[1]]
      $tw = & $ui.RunTextW $w; $n1 = & $ui.Rows ([string]$r.Title) $ui.F.SmallB $tw $h1 2   # the name and the second line wrap to 2 lines each (Cards v2)
      & $ui.Word $G ([string]$r.Title) $ui.F.SmallB $ui.C.Navy $pad ($y + (& $ui.Sc 6)) $tw ($n1 * $h1) $wrap
      & $ui.Word $G ([string]$r.Sub) $ui.F.Small $ui.C.Gray $pad ($y + (& $ui.Sc 6) + $n1 * $h1) $tw (2 * $h2) $wrap
      & $ui.Word $G ([string]$m[0]) $ui.F.SmallB $col ($w - $mw) $y ($mw - $pad) $h 'Right, VerticalCenter, NoPrefix, SingleLine'
      $ww = [int](& $ui.Meas ([string]$m[0]) $ui.F.SmallB 100000).Width; & $ui.RunIcon $G ([string]$m[0]) $col ($w - $pad - $ww - (& $ui.Sc 16)) ($y + [int]($h / 2))
      $y += $h; $G.DrawLine($ln, 0, ($y - 1), $w, ($y - 1)) }
    $ln.Dispose() } catch { $null = $_ } }   # a list that cannot be drawn: the running row and the percent still show
# Draws the icon of a status, 10 px, centered on a point: a tick, a cross, a ring (WAITING) or a dash. Takes the graphics,
# the word, the color and the point.
$ui.RunIcon = {
  <#
  .SYNOPSIS
  Draws a 10 px status icon (check, cross, circle, or dash) for a painted run list row.
  .DESCRIPTION
  Draws a vector glyph centered vertically at ($X, $Y) using the specified color on the Graphics surface.
  .PARAMETER G
  Graphics context from the Paint event.
  .PARAMETER Word
  Status label word ('PASSED', 'DONE', 'FAILED', 'NEEDS REVIEW', 'STOPPED', 'WAITING', etc.).
  .PARAMETER Color
  Pen color for drawing the glyph.
  .PARAMETER X
  Left X coordinate in pixels.
  .PARAMETER Y
  Vertical center Y coordinate in pixels.
  .OUTPUTS
  None.
  #>
  param($G, [string]$Word, $Color, [int]$X, [int]$Y)
  $d = & $ui.Sc 10; $t = $Y - [int]($d / 2); $pn = New-Object System.Drawing.Pen($Color, [single](& $ui.Sc 2))
  if ($Word -in 'PASSED', 'DONE') {
    $pts = [System.Drawing.Point[]]@(
      (New-Object System.Drawing.Point($X, ($t + [int]($d / 2)))),
      (New-Object System.Drawing.Point(($X + [int]($d / 3)), ($t + $d))),
      (New-Object System.Drawing.Point(($X + $d), $t)))
    $G.DrawLines($pn, $pts)
  }
  elseif ($Word -in 'FAILED', 'NEEDS REVIEW', 'STOPPED') { $G.DrawLine($pn, $X, $t, ($X + $d), ($t + $d)); $G.DrawLine($pn, ($X + $d), $t, $X, ($t + $d)) }
  elseif ($Word -eq 'WAITING') { $G.DrawEllipse($pn, $X, $t, $d, $d) } else { $G.DrawLine($pn, $X, $Y, ($X + $d), $Y) }
  $pn.Dispose() }
# The installed part of this app's install record, or $null (the row the person sees next on Maintenance: $ui.RowVerb).
$ui.InstNow = {
  $e = $null; try { $e = Read-Installed (Get-InstalledKey $script:app) } catch { $null = $_ }   # no record: not installed
  if ($e -and $e.installed) { return $e.installed }; return $null }
# A count with its noun, singular for 1 ("1 step", "3 checks"). Takes the number and the noun.
$ui.Counted = { param([int]$N, [string]$One) [string]$N + ' ' + $One + $(if ($N -ne 1) { 's' } else { '' }) }
# The Cancel question (Cards v2; critique change 10): Cancel or Esc on the Run card asks first. "Stop the install" lets the
# step that runs now finish and then stops the run ($script:stopAfter, engine/ps/06-round.ps1); "Keep installing" shows the
# Run card again. The run goes on while the question shows; during the setup, before the first step, it says so. Takes nothing.
$ui.VCancelQ = {
  if (-not $ui.Running -or $ui.View -ne 'run') { return }
  $t = & $ui.TitleOf $ui.StepNow; $dep = Test-Deploy; $verb = $(if ($dep) { 'install' } else { 'round' })
  $cqP1 = $(if ($ui.StepI -and $t) { 'RADE stops after "' + $t + '". The steps that passed stay done.' } else { 'RADE stops before the first step.' })
  $cqP2 = $(if ($dep) { 'To finish the install later, select "' + (& $ui.RowVerb (& $ui.InstNow)) + '" again.' } else { '' })
  & $ui.SetCard @{ View = 'cancelq'; Light = 'you'; Kicker = $ui.Kick.Text; Sentence = ('Stop the ' + $verb + '?')
    P = @($cqP1, $cqP2)
    Buttons = @(@{ Text = ('Stop the ' + $verb); Kind = 'dangerline'; Always = $true; Act = { $script:stopAfter = $true; & $ui.ShowRun; & $ui.Say1 'RADE stops after the step that runs now.' } },
      @{ Text = $(if ($dep) { 'Keep installing' } else { 'Keep running' }); Kind = 'primary'; Always = $true; Act = { & $ui.ShowRun } }) } }
# Shows the run card: step k of n, the step name, the bars, Cancel and the next step that needs you.
$ui.ShowRun = {
  <#
  .SYNOPSIS
  Displays and configures the Run progress card with step rows, bars, summary ranges, and Cancel button.
  .DESCRIPTION
  Sets up the Run view, populates range metrics for stable layout, updates current step title and overall percent,
  and refreshes edge alignment and elapsed step time.
  .OUTPUTS
  None.
  #>
  $runSent = $(if (Test-Deploy) { 'Installing ' + (Get-AppWord) + ' ' + $script:app.Version + '.' } else { 'Running round ' + $round + '.' })
  $runFoot = $(if (@($ui.Guides).Count) { 'RADE needs you next at "' + (& $ui.TitleOf $ui.Guides[0]) + '". Until then, keep this window open.' }
    elseif (-not (Test-Deploy) -and -not $ui.Asked) { 'RADE asks you one last question at the end. Until then, keep this window open.' }
    else { 'Nothing is needed from you. Keep this window open.' })
  & $ui.SetCard @{ View = 'run'; Kicker = $(if ($ui.StepI) { 'Step ' + $ui.StepI + ' of ' + $ui.StepN } else { 'Starting' }); Sentence = $runSent
    StepRow = $true; Buttons = @(@{ Text = 'Cancel (Esc)'; Always = $true; Act = { & $ui.VCancelQ } })   # Cards v2: the Cancel question first (the window's X still asks with a message)
    Range = @{ Kick = @('STARTING', 'STEP 00 OF 00'); StepName = @(@($steps | ForEach-Object { Get-StepTitle $_ }) + @('Clean-up')) }   # every step title: the step row keeps its place
    Foot = $runFoot }
  $ui.Range[$ui.StepSum] = @($ui.RunList | ForEach-Object { [string]$_.Sub } | Where-Object { $_ }); & $ui.Reflow $ui.StepSum   # one height for every summary (R35)
  $ui.StepName.Text = (& $ui.TitleOf $ui.StepNow); $ui.PctL.Text = [string][int]($ui.Bars['all'].Target * 100) + ' %'
  # the edge follows the ink of the new text's first letter (titles start with any letter)
  $null = & $ui.PlaceRuns; $null = & $ui.FitEdges; $null = & $ui.FitBar; $null = & $ui.ShowTime }
# Shows a new step on the Run card that is shown: its number in the line in capitals and its title. Both keep their size
# ($ui.Range of the card), and the edges are fitted for the title's first letter. Takes the step number, the count and the name.
$ui.ShowStep = { param([int]$I, [int]$N, [string]$Name)
  $ui.Kick.Text = ('Step ' + $I + ' of ' + $N).ToUpperInvariant(); $ui.StepName.Text = (& $ui.TitleOf $Name)
  $null = & $ui.FitEdges; $null = & $ui.FitBar }
# Invoke-Round calls this when a step starts: keeps its name, start and estimate, and moves the run card on.
# Takes the step index, the step count, the name and the estimate.
$ui.OnStatus = {
  <#
  .SYNOPSIS
  Handles step-start notifications from Invoke-Round and advances the Run card display.
  .DESCRIPTION
  Holds the previous step minimally, records step timing metadata, marks the step RUNNING, updates the Run or
  Cancel-question view, resets step progress bar, and pumps UI events.
  .PARAMETER i
  One-based index of the starting step.
  .PARAMETER count
  Total number of active steps in the run.
  .PARAMETER name
  Identifier name of the starting step.
  .PARAMETER estimate
  Estimated duration in seconds for progress calculations.
  .OUTPUTS
  None.
  #>
  param($i, $count, $name, $estimate)
  $null = & $ui.HoldStep
  $script:statusBase = $name; $script:stepStart = Get-Date; $script:stepEst = $estimate
  if ($i -le 1) { $null = & $ui.SetBar 'all' 0 $true }
  $ui.StepI = [int]$i; $ui.StepN = [int]$count; $ui.StepNow = [string]$name
  $null = & $ui.RunStart ([string]$name)
  if ($ui.View -eq 'cancelq') { $ui.Kick.Text = ('Step ' + $i + ' of ' + $count).ToUpperInvariant() }   # the Cancel question stays
  elseif ($ui.View -ne 'run') { $null = & $ui.ShowRun } else { $null = & $ui.ShowStep $i $count $name; $null = & $ui.PlaceRuns }
  $null = & $ui.SetBar 'step' 0 $true; $ui.StepFrac.Text = ''; $null = & $ui.FitBar; $null = & $ui.ShowTime
  $null = & $ui.ShowNow ''; $ui.StepAt = $ui.Clock.Elapsed.TotalMilliseconds   # Cards v2: the step's doing text is its summary line ($ui.PlaceRuns); the now-doing line waits for its first item
  $null = & $ui.Paint; [System.Windows.Forms.Application]::DoEvents() }
# Called when a step ends: keeps its state word (DONE, PASSED, SKIPPED, ...) from the result line and redraws. Takes the
# step number and its result line.
$ui.OnStep = { param($k, $line)
  $nm = [string]$steps[$k].Name + ': '; $rest = [string]$line; if ($rest.StartsWith($nm, [System.StringComparison]::Ordinal)) { $rest = $rest.Substring($nm.Length) }
  $st = 'DONE'; foreach ($w in 'NEEDS REVIEW', 'INTERRUPTED', 'FAILED', 'SKIPPED', 'PASSED') { if ($rest.StartsWith($w, [System.StringComparison]::Ordinal)) { $st = $w; break } }
  $ui.StepState[[int]$k] = $st; $null = & $ui.RunEnd ([string]$steps[$k].Name) $st $rest; $null = & $ui.Paint }
# Gives the "Window: OK" or "Window: NOT OK" line for the report, with the layout self-check when it is on. Takes
# nothing; gives back the text.
$ui.WindowLine = {
  $w = $(if ($ui.OkBox.Checked) { 'Window: OK' } else { 'Window: NOT OK - write here what overlapped or was cut off' })
  if ($ui.LayOn -and ($env:RADE_LAYOUT -eq '1' -or -not (Test-Deploy))) { $w += "`r`n" + (& $ui.LayLine) }
  @(@($w) + @(& $ui.ScaleLines)) -join "`r`n" }   # E4: the SCALE line of each RADE window shown since this one opened
$ui.StartApp = {
  <#
  .SYNOPSIS
  Launches the installed application (.ps1, https:// URL, or executable) and closes RADE.
  .DESCRIPTION
  Clears any inherited Bypass execution-policy preference, starts the configured start target,
  verifies immediate PowerShell launch exit codes, and closes the form on success.
  .OUTPUTS
  None.
  #>
  $p = Get-StartPath; if (-not $p) { & $ui.Say1 'The start file of this application was not found. Select "Install" to put it back.'; return }
  # No -ExecutionPolicy setting (DEC 3): drop only a "Bypass" handed down by an old RADE shortcut (RADE closes after this)
  if ($env:PSExecutionPolicyPreference -ceq 'Bypass') { Remove-Item -LiteralPath 'Env:PSExecutionPolicyPreference' -ErrorAction SilentlyContinue }
  try {
    if ($p -match '\.ps1$') {
      $pr = Start-Process -FilePath (Get-PowerShellExe) -ArgumentList ('-NoProfile -STA -File "' + $p + '"') -WorkingDirectory (Split-Path -Parent $p) -PassThru
      if ($pr) { $null = $pr.Handle }   # Windows PowerShell 5.1 keeps the exit code only when the handle is held
      if ($pr -and $pr.WaitForExit(2500) -and $pr.ExitCode -ne 0) {
        & $ui.Say1 ('The application stopped as soon as it started (exit code ' + $pr.ExitCode + '). Ask in the Teams channel.')
        return
      }
    } elseif ($p -match '^https://') {
      $null = Start-Process -FilePath $p
    } else {
      $null = Start-Process -FilePath $p -WorkingDirectory (Split-Path -Parent $p)
    }
    $ui.Started = $true; $ui.Form.Close() } catch { & $ui.Say1 'The application could not be started. Select "Start" again, or ask in the Teams channel.' } }
# Starts the run: saves the shortcut folder, asks for the folder some steps need, then calls Invoke-Round with the
# window callbacks and shows Done, Needs review or Stopped. Takes nothing.
$ui.Run = {
  <#
  .SYNOPSIS
  Validates options, prompts for any step folder inputs, executes Invoke-Round, and shows the outcome card.
  .DESCRIPTION
  Saves shortcut directory if applicable, collects AskParam folders, initializes progress bars, runs Invoke-Round
  with UI callbacks, and routes to $ui.VDone or $ui.VStopped.
  .OUTPUTS
  None.
  #>
  $ui.LinkDir = ''; $ui.FieldAsked = $false
  if ($ui.View -eq 'ready' -and $ui.FieldRow.Visible -and $ui.FieldL.Text -eq 'Shortcut in') {   # R29 N8: the folder for the app's shortcut (the label is the key: 06-open.ps1)
    $d = $ui.Field.Text.Trim().Trim('"')
    if ($d -and -not (Test-Path -LiteralPath $d -PathType Container)) {
      & $ui.Say1 'That folder was not found. Select "Browse" to choose a folder, or empty the box for no shortcut.'; $script:resume = $null; return
    }
    $ui.LinkDir = $d; $ui.FieldAsked = $true; if ($d) { Save-ShortcutDir $d } }
  $dep = Test-Deploy; $ui.Running = $true; $ui.Asked = $false; $ui.StepAt = $null; $ui.Summary = @(); $ui.Log.Clear(); $ui.StepState = @{}; $ui.StepI = 0; $ui.StepNow = ''; $ui.Edit = $false
  $to = ''; if (-not $dep) { $to = [string](Get-MailTo (Get-BasePath)); $ui.ToBox.Text = $to }
  $sel = @(); $ui.Guides = @()
  for ($k = 0; $k -lt $steps.Count; $k++) {
    $on = [bool]($script:appSteps -contains $k -and $ui.Sel[[int]$k]); $sel += $on
    if ($on -and $steps[$k].Kind -eq 'guide') { $ui.Guides += [string]$steps[$k].Name }
  }
  $kept = $(if ($script:resume) { Get-ResumeKept $script:resume } else { @{} })
  $answers = @()
  for ($k = 0; $k -lt $steps.Count; $k++) {
    $a = ''
    if ($sel[$k] -and $steps[$k].AskParam -and -not $kept.ContainsKey([string]$steps[$k].Name)) {
      $pick = New-Object System.Windows.Forms.FolderBrowserDialog
      $pick.Description = $steps[$k].AskPrompt; $pick.ShowNewFolderButton = $false
      if ([string]$pick.ShowDialog($ui.Form) -eq 'OK') { $a = [string]$pick.SelectedPath }
      else { $sel[$k] = $false; $ui.Guides = @($ui.Guides | Where-Object { $_ -ne [string]$steps[$k].Name }); $ui.Log.Add($steps[$k].Name + ': skipped (no folder picked)') }
      $pick.Dispose()
    }
    $answers += $a
  }
  $ui.Bars['all'].Fill = $ui.C.Info; $ui.Bars['run'].Fill = $ui.C.Info; $ui.Bars['step'].Fill = $ui.C.Info
  & $ui.SetBar 'all' 0 $true; & $ui.SetBar 'run' 0 $true; & $ui.SetBar 'step' 0 $true
  $script:stopAfter = $false; & $ui.MakeRunList $sel; $ui.RunKey = ''; & $ui.ShowRun; $ui.TimeT.Start()
  $checkLines = Get-CheckSummary $script:checkResults
  $script:roundStart = Get-Date
  try {
    $ui.Summary = Invoke-Round ([bool]($cleanup.Count -and $ui.Clean)) $sel $to $ui.Say $ui.Tick $ui.OnStep $ui.OnStatus $ui.WindowLine $answers $checkLines
    & $ui.HoldStep; $script:stepStart = $null; $ui.Running = $false
    if (-not ($script:closing -or $ui.Form.IsDisposed)) { & $ui.VDone }   # closed in the last moments of the run: no clipboard, no folder
  } catch {
    $script:stepStart = $null; $ui.Running = $false
    if ($script:closing -or $ui.Form.IsDisposed) { return }   # Exit during a step: the report on disk says STOPPED
    $msg = 'STOPPED: ' + (ConvertTo-Masked ([string]$_)); & $ui.Say $msg
    $what = [string](Get-WhatToDo $msg); if ($what) { & $ui.Say $what }
    & $ui.VStopped $msg.Substring(9) $what
  } finally { $script:resume = $null; $ui.Running = $false; try { $ui.TimeT.Stop() } catch { $null = $_ }; $sv = $ui.StepState; & $ui.InitSel; $ui.StepState = $sv } }
# Pause and resume (the Administrator, 2026-11-20; docs/engine.md "Pause and resume"): runs the round again from its saved state.
# The steps that passed stay done; the step that was running and the steps after it run. Takes nothing.
$ui.ResumeRun = {
  $st = Read-RoundState (Get-BasePath)
  if ($st.State -ne 'ok') {
    $null = Clear-RoundState (Get-BasePath); & $ui.VReady
    & $ui.Say1 'The saved progress could not be read, so the round starts over. Select the main button to start.'; return
  }
  $sel = Get-ResumeSelection $st.Doc; for ($k = 0; $k -lt $steps.Count; $k++) { if ($script:appSteps -contains $k) { $ui.Sel[[int]$k] = [bool]$sel[$k] } }
  $script:resume = $st.Doc; & $ui.Run }
# Start over: the saved state goes to the Recycle Bin, then the round runs from its first step. Takes nothing.
$ui.StartOver = {
  $why = Clear-RoundState (Get-BasePath)
  if ($why) { & $ui.Say1 ('The saved progress could not be moved to the Recycle Bin (' + $why + ').'); return }
  $script:resume = $null; & $ui.Run }
# Summarizes artifacts created by previous installs of the selected application.
$ui.MadeText = {
  <#
  .SYNOPSIS
  Summarizes items created by past installs of the selected application by kind.
  .DESCRIPTION
  Reads the installation record for $script:app, counts created entries by kind, and formats a sentence
  for the Done card.
  .OUTPUTS
  String summary sentence, or empty string if nothing was created.
  #>
  $c = [ordered]@{}; $e = (Read-Installed (Get-InstalledKey $script:app))
  if ($e -and $e.steps) {
    foreach ($n in @($e.steps.Keys)) {
      foreach ($m in @($e.steps[$n].made)) { if ($null -ne $m) { $k = [string]$m.kind; if ($c.Contains($k)) { $c[$k] = [int]$c[$k] + 1 } else { $c[$k] = 1 } } }
    }
  }
  if (-not $c.Count) { return '' }
  $parts = @(); foreach ($k in @($c.Keys)) { $parts += ([string]$c[$k] + ' ' + $k + $(if ($c[$k] -ne 1) { 's' } else { '' })) }
  return ('The installs of this application made: ' + ($parts -join ', ') + '.') }
# Copies the summary (else the log) to the clipboard and says "Copied.". Takes nothing.
$ui.Copy = {
  $t = $(if (@($ui.Summary).Count) { @($ui.Summary) } else { @($ui.Log) }) -join "`r`n"
  try { [System.Windows.Forms.Clipboard]::SetText($t); & $ui.Say1 'Copied.' } catch { & $ui.Say1 'The clipboard is busy. Select the button again.' } }
# Opens the results folder in Explorer, when there is one. Takes nothing.
$ui.Open = { if ($script:resultsDir) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $script:resultsDir + '"') } }
# engine-v46 (the Administrator, 2026-11-26: "I got no notification that a script was blocked"): the end card names each step
# whose script Windows blocked 2 times (Invoke-RoundStep), also when it is not the first problem. Takes nothing; gives
# back the paragraph, or '' when no step was blocked.
$ui.BlockedText = { $b = @($script:blockedSteps | Where-Object { $_ })
  if (-not $b.Count) { return '' }
  $bDesc = $(if ($b.Count -eq 1) { 'the step "' + $b[0] + '"' } else { [string]$b.Count + ' steps: "' + ($b -join '", "') + '"' })
  return ('Windows blocked the script of ' + $bDesc + ' 2 times. Details shows the policy line.') }
# Shows the card at the end of a run: Done when every step passed ($ui.VPassed), else the step-failed card for the first
# step that failed ($ui.VStepFail), or Needs review. Copies the summary and opens the folder in a test round. Takes nothing.
$ui.VDone = {
  <#
  .SYNOPSIS
  Handles end-of-round presentation by showing Done, StepFail, or Needs review cards.
  .DESCRIPTION
  Sets progress bar finish state, locates the first failed/needs-review step when applicable, displays the
  corresponding card, and copies summary / opens results folder for test rounds.
  .OUTPUTS
  None.
  #>
  $sum = @($ui.Summary); $dep = Test-Deploy; $bad = ([string]$sum[0] -match 'NEEDS REVIEW')
  $ui.Took = Format-Duration ((Get-Date) - $script:roundStart).TotalSeconds
  $ui.Bars['all'].Fill = $(if ($bad) { $ui.C.Red } else { $ui.C.Green }); & $ui.SetBar 'all' $(if ($bad) { $ui.Bars['all'].Target } else { 1 }) $true
  $ui.Mail = $(if ($script:draftMade) { 'An Outlook draft is open with the summary and all result files. Review it, then select Send.' }
    else { 'The results folder is open and the summary is on the clipboard. Paste it into an e-mail and attach the files.' })
  if (-not $bad) { & $ui.VPassed } else {
    # The first step that failed or needs review, with its help line from the manifest; the rest is in Details.
    $one = ''; $what = ''; $more = 0
    for ($k = 0; $k -lt $sum.Count; $k++) {
      if ([string]$sum[$k] -match ': (NEEDS REVIEW|FAILED) ') {
        if ($one) { $more++ }
        else { $one = [string]$sum[$k]; if ($k + 1 -lt $sum.Count -and [string]$sum[$k + 1] -match '^\s+What to do: ') { $what = ([string]$sum[$k + 1]).Trim() } }
      }
    }
    $row = $null; $ri = 0
    for ($i = 0; $i -lt @($ui.RunList).Count; $i++) {
      if ($one.StartsWith([string]$ui.RunList[$i].Key + ': ', [System.StringComparison]::Ordinal)) { $row = $ui.RunList[$i]; $ri = $i + 1; break }
    }
    if ($row) { & $ui.VStepFail $row $ri $one $what $more } else {
      if (-not $one) { $one = 'A file, the clean-up or a result file needs review. Details shows which.' }
      $revP1 = $one + $(if ($more) { ' (and ' + $more + ' more in Details)' } else { '' })
      $revP4 = $(if ($dep) { 'Steps that passed stay done. If you paste the block again, RADE runs only what is left.' } else { $ui.Mail })
      $revNote = $(if ($dep) { '"Copy summary" puts the report on the clipboard. Paste it in the channel. Nothing was sent.' } else { '' })
      & $ui.SetCard @{ View = 'review'; Light = 'bad'; Kicker = 'Needs review'; Right = 'Needs review'
        Sentence = $(if ($dep) { 'The install is not complete.' } else { 'The round needs review.' })
        P = @($revP1, $what, (& $ui.BlockedText), $revP4)
        Help = $(if ($dep) { Get-HelpLine } else { '' }); Note = $revNote
        Buttons = @(@{ Text = 'Copy summary'; Kind = 'primary'; Act = { & $ui.Copy } }, @{ Text = 'Open results folder'; Act = { & $ui.Open } }, @{ Text = 'Close'; Act = { $ui.Form.Close() } })
        Test = (-not $dep); Back = { & $ui.VReady } } } }
  if (-not $dep) { & $ui.Copy; if (-not $script:draftMade) { & $ui.Open } }   # a test round: the summary is on the clipboard, and with no draft the folder opens
  & $ui.ToFront }
$ui.VPassed = {
  <#
  .SYNOPSIS
  Shows the Done card of a run that passed (Cards v2): the green light line, the kicker "ALL n STEPS PASSED" in the
  PASSED color, the tick and the headline, the strong summary line "<n> steps and <m> checks passed in <time>.", what
  was sent (nothing), the main button "Start <word> (Enter)" when it can start, and no Back.
  .OUTPUTS
  Nothing.
  #>
  $dep = Test-Deploy; $made = ''; if ($dep) { $made = [string](& $ui.MadeText) }
  $all = @($ui.RunList).Count; $n = @($ui.RunList | Where-Object { [string]$_.State -in 'PASSED', 'DONE' }).Count   # counted from the states: a skipped step did not pass
  $m = @($script:appChecks | Where-Object { $script:checkResults[$_] -and [string]$script:checkResults[$_].State -like 'PASSED*' }).Count   # a warning did not pass
  $iconNote = ''; if ($dep) { $saved = Save-RunnerCopy   # a copy that stays (a higher engine) keeps its shortcut (review of PR 199)
    $noBox = 'The shortcut folder box was empty, so RADE made no shortcut. Open RADE from the GitHub README instead.'   # R28: the runner copy and the shortcut (a deploy that passed)
    $iconNote = $(if (-not $saved) { '' } elseif ($ui.FieldAsked -and -not $ui.LinkDir -and (Get-DesktopDir)) { $noBox } else { [string](Add-DesktopIcon ([string]$ui.LinkDir)) }) }
  $inst = ($dep -and (Get-InstalledText $script:app) -match 'is installed$'); $w = Get-AppWord
  # Start (R28 fix: after a first install the Done card had no Start button): the checks passed before the install.
  $startB = $(if ($inst -and [string]$script:app.Start -and (Get-StartPath)) { @{ Text = 'Start ' + $w; Kind = 'primary'; Act = { & $ui.StartApp } } } else { $null })
  $passKick = $(if (($dep -and -not $inst) -or $n -ne $all) { 'Passed' } else { $(if ($n -eq 1) { 'The step passed' } else { 'All ' + $n + ' steps passed' }) })
  $passSent = $(if (-not $dep) { 'Round ' + $round + ' is done.' }
    elseif ($inst) { $w + ' ' + $script:app.Version + ' is installed.' }
    else { 'The run passed, but version ' + $script:app.Version + ' is not recorded as installed.' })
  $passP1 = (& $ui.Counted $n 'step') + ' and ' + (& $ui.Counted $m 'check') + ' passed in ' + $ui.Took + '.'
  $passP2 = $(if ($dep -and -not $inst) { 'Some steps were off or skipped. Run again with every step on.' } else { '' })
  $passP3 = $(if ($dep) { 'Nothing was sent. The report stays on this computer.' } else { $ui.Mail })
  $passBtns = @(
    @{ Text = 'Open results folder'; Act = { & $ui.Open } },
    @{ Text = 'Copy summary'; Act = { & $ui.Copy } },
    @{ Text = 'Close'; Kind = $(if ($startB) { '' } else { 'primary' }); Act = { $ui.Form.Close() } },
    $startB)
  & $ui.SetCard @{ View = 'done'; Light = 'pass'; Tick = $true; KickColor = 'GreenInk'; Strong = $true
    Kicker = $passKick; Sentence = $passSent; P = @($passP1, $passP2, $passP3, $made, $iconNote)
    Buttons = $passBtns; Test = (-not $dep) } }
$ui.VStepFail = {
  <#
  .SYNOPSIS
  Shows the step-failed card (Cards v2): the kicker "STEP k OF n FAILED" with a cross, both in the error color; the
  headline "A step failed: <step title>."; what happened; the boxed WHAT TO DO line; the help line; "Try again (Enter)"
  (the Ready card, which offers Resume), "Copy summary" and "Close".
  .PARAMETER Row
  The row of the step in $ui.RunList.
  .PARAMETER K
  Its number in the run.
  .PARAMETER Line
  Its result line from the summary.
  .PARAMETER What
  Its "What to do:" line ('' when it has none).
  .PARAMETER More
  How many more steps failed or need review.
  .OUTPUTS
  Nothing.
  #>
  param($Row, [int]$K, [string]$Line, [string]$What, [int]$More)
  $dep = Test-Deploy; $said = $Line.Substring([math]::Min($Line.Length, ([string]$Row.Key).Length + 2))
  $what = ($said -replace '^(FAILED|NEEDS REVIEW)[^:]*:\s*', '').Trim(); if ($what) { $said = $what }   # what happened, without the state word and the time (Cards v2)
  & $ui.SetCard @{ View = 'stepfail'; Light = 'bad'; KickColor = 'Red'; Kicker = ([string][char]0x00D7 + ' Step ' + $K + ' of ' + @($ui.RunList).Count + ' failed')
    Sentence = ('A step failed: ' + [string]$Row.Title + '.'); Todo = ($What -replace '^What to do:\s*', '')
    P = @(($said + $(if ($More) { ' (and ' + $More + ' more in Details)' } else { '' })), (& $ui.BlockedText), $(if ($dep) { '' } else { $ui.Mail })); Help = (Get-HelpLine)
    Buttons = @(@{ Text = 'Copy summary'; Act = { & $ui.Copy } }, @{ Text = 'Close'; Act = { $ui.Form.Close() } }, @{ Text = 'Try again'; Kind = 'primary'; Act = { & $ui.VReady } })
    Test = (-not $dep) } }
# Shows the Paused card (the Administrator, 2026-11-20): the sign-in failed in a step (the CAC is out), so the round paused at that
# step; Resume runs it again. Takes the reason ("INTERRUPTED: ..."); does nothing when the window is closing.
$ui.VPaused = { param([string]$Why)
  if ($script:closing -or $ui.Form.IsDisposed) { return }
  $p1 = (($Why.Substring(13) -replace '\. Insert your CAC, then select Resume$', '') -replace '^t', 'T') + '.'
  & $ui.SetCard @{ View = 'stopped'; Kicker = 'Paused'; Right = 'Paused'; Sentence = 'Insert your CAC, then select Resume.'
    P = @($p1, 'The steps that passed stay done. Resume runs this step again.'); Back = { & $ui.VReady }
    Buttons = @(@{ Text = 'Resume'; Kind = 'primary'; Act = { & $ui.ResumeRun } }, @{ Text = 'Copy the log'; Act = { & $ui.Copy } }, @{ Text = 'Close'; Act = { $ui.Form.Close() } }) }
  & $ui.ToFront }
# Shows the Stopped card with why the run stopped and what to do. Takes the reason and the help text; does nothing when
# the window is closing.
$ui.VStopped = { param([string]$Why, [string]$What)
  if ($script:closing -or $ui.Form.IsDisposed) { return }
  $dep = Test-Deploy
  if ($Why -match '^INTERRUPTED: ') { & $ui.VPaused $Why; return }   # the sign-in failed (CAC out): Paused, not Stopped
  $stopBtns = @(@{ Text = 'Copy the log'; Kind = 'primary'; Act = { & $ui.Copy } }, @{ Text = 'Try again'; Act = { & $ui.VReady } }, @{ Text = 'Close'; Act = { $ui.Form.Close() } })
  & $ui.SetCard @{ View = 'stopped'; Light = 'bad'; Kicker = 'Stopped'; Right = 'Stopped'
    Sentence = $(if ($dep) { 'The install stopped.' } else { 'The round stopped.' })
    P = @(($Why.Substring(0, 1).ToUpperInvariant() + $Why.Substring(1)), $What, 'The report in the results folder says STOPPED.'); Help = $(if ($dep) { Get-HelpLine } else { '' })
    Buttons = $stopBtns; Back = { & $ui.VReady } }
  & $ui.ToFront }
# ticking again removes only this note
$ui.OkBox.Add_CheckedChanged({
  if (-not $ui.OkBox.Checked) { & $ui.Say1 'Select "Make e-mail draft" to make a draft that says "Window: NOT OK".' }
  elseif ($ui.Note.Text -match '^Select "Make e-mail draft"') { & $ui.Say1 '' } })
$ui.DraftB.Add_Click({
  $to = $ui.ToBox.Text.Trim()
  if ($to -and -not (Test-MailTo $to)) { & $ui.Say1 'The e-mail address does not look right.'; return }
  try { $null = Save-MailTo (Get-BasePath) $to } catch { $null = $_ }
  $why = Save-RoundDraft $script:resultsDir $ui.Summary $to (& $ui.WindowLine)
  & $ui.Say1 $(if ($why) { 'The Outlook draft could not be created (' + $why + ').' } else { 'The Outlook draft is open.' }) })

# RADE window part 11, the Maintenance tools on the Maintenance card (the Administrator, 2026-11-20; one card from engine-v47): a click on the
# Diagnose or the Back up row runs it (engine/ps/13-maintenance.ps1), with a card while it runs and a card with its result.
# Restore (engine-v31, the Administrator, 2026-11-21): pick a backup, the dry-run card with its counts, the typed app
# name, then the write and its result card. The local test-site mark (engine-v32, the Administrator, 2026-11-21): for an
# app with "testSites": "local", a card where the person types the site name marks the saved site as a test site; the
# backup card has "Remove test-site mark" (engine-v33).
# Listed before 10-keys.ps1 in engine/rade_build.py (that part shows the form).
# Network: none here (parts 13 and 14 name what each tool reaches).
# Writes: the mark file, from the mark card, and its removal (Save-RestoreMark, Clear-RestoreMark, engine/ps/15-restore-run.ps1).
# Credentials: none.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# The line on a card while a child may show the CAC sign-in window (R44 E4: in R43 no sign-in window showed in front).
$ui.SignInHint = 'A sign-in window may open. If you do not see it, press Alt+Tab.'

# The tool rows of the Maintenance card (indexes 0 to 2). Diagnose and Back up (engine-v30); Restore (engine-v31) for an app that names it.
$ui.ToolRows = {
  $n = @($script:app.Backup).Count; $lists = $(if ($n -eq 1) { '1 list' } elseif ($n) { [string]$n + ' lists' } else { 'No lists named' })
  # Short texts and facts (engine-v47, review of PR 209): each row is one line on the Maintenance card, with 2 lines at most
  # for its text, also at 150 % and in a narrow window (the Administrator, 2026-11-26: no cut text).
  @(@{ Index = 0; Name = 'Diagnose'; Ver = ''; Sub = 'Checks the install. Changes nothing.'; R1 = 'Writes a report' },
    @{ Index = 1; Name = 'Back up'; Ver = ''; Sub = 'Saves the lists to this computer.'; R1 = $lists },
    $(if ($script:app.Restore) { @{ Index = 2; Name = 'Restore'; Ver = ''; Sub = 'Puts missing rows back. Test sites only.'; R1 = 'Changes the site' } }
      else { @{ Off = $true; Index = 2; Name = 'Restore'; Ver = ''; Sub = 'Puts missing rows back from a backup.'; R1 = 'Not set up'; Soon = $true } })) }

$ui.RunTool = {
  <#
  .SYNOPSIS
  Runs one Maintenance tool from its row: a card while it runs, then the result card.
  .PARAMETER J
  The row: 0 Diagnose, 1 Back up, 2 Restore (its first card: $ui.VRestorePick).
  #>
  param([int]$J)
  if ($J -eq 2 -and -not $ui.Busy) { & $ui.VRestorePick; return }
  if ($J -notin 0, 1 -or $ui.Busy) { return }
  $name = $(if ($J -eq 0) { 'Diagnose' } else { 'Back up' })
  $what = $(if ($J -eq 0) { 'Read-only. Nothing is changed.' } else { 'Reads the lists and saves them on this computer. Nothing on the site changes. ' + $ui.SignInHint })
  & $ui.SetCard @{ View = 'toolrun'; Kicker = [string]$ui.Kick.Text; Sentence = ($name + ' is running.'); P = @($what) }
  $ui.Busy = $true; [System.Windows.Forms.Application]::DoEvents(); $res = $null
  try { $bp = Get-BasePath
    if ($J -eq 0) { $res = Invoke-Diagnose $bp { [System.Windows.Forms.Application]::DoEvents() } } else { $res = Invoke-Backup $bp { [System.Windows.Forms.Application]::DoEvents() } } }
  catch { $res = @{ State = 'failed'; Findings = 1; Path = ''; Lines = @(($name + ' stopped with an error [' + $_.Exception.GetType().Name + '].'), 'Nothing was changed. Select it again.') } }
  finally { $ui.Busy = $false }
  if ($ui.Form.IsDisposed -or $script:closing) { return }
  & $ui.ToolResult $name $res }

$ui.ToolResult = {
  <#
  .SYNOPSIS
  Shows the result card of a Maintenance tool: what it found, saved or put back, and the file or folder it wrote.
  .PARAMETER Name
  The tool: Diagnose, Back up or Restore.
  .PARAMETER Res
  Its result: Invoke-Diagnose (Lines, Path, Findings), Invoke-Backup or Invoke-Restore (State, Lines, Path).
  #>
  param([string]$Name, $Res)
  $diag = ($Name -eq 'Diagnose'); $bad = $(if ($diag) { [int]$Res.Findings -gt 0 } else { [string]$Res.State -in 'failed', 'refused', 'changed', 'unmark-failed', 'no-backup', 'review' })
  $st = [string]$Res.State
  $sent = $(if ($diag -and $bad) { 'Diagnose found ' + $Res.Findings + ' thing(s) to fix.' } elseif ($diag) { 'Diagnose found nothing to fix.' }
    elseif ($Name -eq 'Restore') { $(switch ($st) { 'done' { 'Restore put the missing rows back.' } 'refused' { 'Restore cannot run here.' } 'none' { 'Restore has no backup to use.' }
        'changed' { 'Restore wrote nothing: the site changed after the dry run.' } default { 'Restore did not finish.' } }) }
    elseif ($Name -eq 'Uninstall') { $(switch ($st) { 'done' { $script:app.Name + ' is uninstalled.' } 'refused' { 'Uninstall cannot run here.' } 'no-backup' { 'Uninstall removed nothing.' }
        'review' { 'Uninstall did not finish.' } default { 'Uninstall stopped with an error.' } }) }
    elseif ($st -eq 'done') { 'Back up saved the lists.' } elseif ($st -eq 'none') { 'Back up has no lists to save.' }
    elseif ($st -eq 'no-site') { 'Back up saved nothing.' } else { 'Back up did not save everything.' })
  if ($Name -eq 'Restore' -and $st -eq 'unmarked') { $sent = 'The test-site mark is removed.' }
  if ($Name -eq 'Restore' -and $st -eq 'unmark-failed') { $sent = 'The test-site mark was not removed.' }
  $lines = @($Res.Lines); $path = $(if ($Res.Path) { [string]$Res.Path } else { $null })
  $buttons = @(@{ Text = 'Done'; Kind = 'primary'; Act = $ui.ToolsBack })
  # Uninstall (engine-v40): after a whole Uninstall the app is not installed, so Done goes to Choose; else to the Maintenance card.
  if ($Name -eq 'Uninstall') { $buttons = @(@{ Text = 'Done'; Kind = 'primary'; Act = $(if ($st -eq 'done') { { & $ui.VChoose } } else { { & $ui.VMaint $ui.MaintInst } }) }) }
  if ($Res.Unmark) { $buttons = @(& $ui.UnmarkButton) + $buttons }   # a marked site with no backup (engine-v33)
  & $ui.SetCard @{ View = 'toolres'; Light = $(if ($bad) { 'bad' } else { '' }); Kicker = [string]$ui.Kick.Text; Sentence = $sent
    P = @($lines | Select-Object -First 2); Lines = @($lines | Select-Object -Skip 2); Path = $path
    Buttons = $buttons; Back = $(if ($Name -eq 'Uninstall') { $buttons[0].Act } else { $ui.ToolsBack }) }
  & $ui.ToFront }

$ui.VRestorePick = {
  <#
  .SYNOPSIS
  Restore, card 1 (view restpick): the backups on this computer, newest first, one row each.
  .DESCRIPTION
  A site that only lacks the local test-site mark (engine-v32) goes to the mark card ($ui.VRestoreMark); a site that is
  not a test site, or no backup, goes straight to the result card. Keeps the site name for the "Test site:" line of the
  dry-run and confirm cards ($ui.RestoreSite). Takes no parameter.
  #>
  $appPath = Get-BasePath; $siteCheck = Test-RestoreSite $appPath
  if ($siteCheck.NeedMark) { $ui.MarkNext = $ui.VRestorePick; $ui.MarkBack = $ui.ToolsBack; & $ui.VRestoreMark; return }
  if (-not $siteCheck.Ok) { & $ui.ToolResult 'Restore' @{ State = 'refused'; Path = ''; Lines = $siteCheck.Lines }; return }
  $ui.RestoreSite = [string]$siteCheck.Name; $marked = [bool]$script:app.Restore.Local   # Ok with "local": the site is marked
  $ui.RestoreSets = @(Get-BackupSet $appPath)
  $noSet = @('There is no backup of this app on this computer.', 'Select "Back up" first.')
  if (-not $ui.RestoreSets.Count) { & $ui.ToolResult 'Restore' @{ State = 'none'; Path = ''; Unmark = $marked; Lines = $noSet }; return }
  $buttons = $(if ($marked) { @(& $ui.UnmarkButton) } else { $null })   # the focus is on the newest backup row (SetCard), never on this button
  $rows = @(for ($k = 0; $k -lt $ui.RestoreSets.Count; $k++) { $set = $ui.RestoreSets[$k]
      @{ Index = $k; Name = $set.Name; Ver = ''; Sub = ([string]$set.Lists + ' of ' + @($script:app.Backup).Count + ' lists'); R1 = $(if ($k -eq 0) { 'Newest' } else { '' }) } })
  & $ui.SetCard @{ View = 'restpick'; Kicker = [string]$ui.Kick.Text; Sentence = 'Which backup does Restore use?'
    P = @('Restore first runs a dry run on the site and shows what it would put back. Nothing is written before you confirm.')
    Options = $rows; OnOption = { param($j) & $ui.RestorePlan $j }; Buttons = $buttons; Back = $ui.ToolsBack } }


# The "Remove test-site mark" button (engine-v33; the Administrator, 2026-11-21): a secondary button on the backup card
# and on the no-backup result card of a marked site. Takes nothing; gives back the button table.
$ui.UnmarkButton = { return @{ Text = 'Remove test-site mark'; Kind = ''; Act = { & $ui.RestoreUnmark } } }

# Removes the mark, then shows the result card. No typed confirm: it makes Restore stricter. Takes nothing.
$ui.RestoreUnmark = {
  if ($ui.Busy) { return }
  $res = @{ State = 'unmarked'; Path = ''; Lines = @('The saved site is no longer marked as a test site on this computer.', 'Restore asks for the site name again before it runs.') }
  try { Clear-RestoreMark (Get-BasePath) }
  catch { $res = @{ State = 'unmark-failed'; Path = ''; Lines = @(('The mark could not be removed [' + $_.Exception.GetType().Name + '].'), 'Nothing was changed.') } }
  & $ui.ToolResult 'Restore' $res }

$ui.VRestoreMark = {
  <#
  .SYNOPSIS
  Restore, the mark card (view restmark): the person types the saved site's name to mark it as a test site on this
  computer.
  .DESCRIPTION
  The Administrator, 2026-11-21: for an app whose manifest gives "testSites": "local" (its public repo names no site).
  The card does not show the name: the person types it, so the mark says they know which site this is. The mark is
  stored only on this computer, next to the site address (Config). Takes no parameter.
  #>
  $where = "The mark stays on this computer only, in the app's Config folder. Restore and Uninstall refuse every site without it."
  & $ui.SetCard @{ View = 'restmark'; Light = 'you'; Kicker = [string]$ui.Kick.Text; Sentence = 'Is the saved site a test site?'
    P = @('Restore and Uninstall change only a test site. To mark the saved site as one, type its name: the part of its address after the last /.', $where)
    Field = @{ Label = 'Site name'; Text = ''; Name = 'The site name, to mark the saved site as a test site'; Max = 200 }; Focus = 'field'
    Buttons = @(@{ Text = 'Mark as test site'; Kind = 'primary'; Act = { & $ui.RestoreMarkGo } }); Back = $(if ($ui.MarkBack) { $ui.MarkBack } else { $ui.ToolsBack }) } }

# Restore, the mark card's button: checks the typed name against the saved site (without case; a pasted full address
# counts too), saves the mark, then shows card 1. Takes nothing.
$ui.RestoreMarkGo = {
  if ($ui.Busy) { return }
  $appPath = Get-BasePath; $siteCheck = Test-RestoreSite $appPath; $typed = $ui.Field.Text.Trim().TrimEnd('/')
  if ($typed.StartsWith($sitePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { $typed = $typed.Substring($sitePrefix.Length) }
  if (-not $siteCheck.Name -or $typed -ne $siteCheck.Name) { & $ui.Say1 'That is not the name of the saved site. Type the part of its address after the last /.'; return }
  try { Save-RestoreMark $appPath $siteCheck.Name }
  catch { & $ui.Say1 ('The mark could not be saved [' + $_.Exception.GetType().Name + ']. Nothing was changed.'); return }
  if ($ui.MarkNext) { & $ui.MarkNext } else { & $ui.VRestorePick } }   # Restore's backup card, or Uninstall's confirm card

$ui.RestorePlan = {
  <#
  .SYNOPSIS
  Restore, card 2: runs the dry run of the backup picked (reads the site only), then shows the confirm card.
  .PARAMETER Row
  The backup's row number on the restpick card.
  #>
  param([int]$Row)
  if ($ui.Busy -or $Row -ge @($ui.RestoreSets).Count) { return }
  $ui.RestoreDir = [string]$ui.RestoreSets[$Row].Path
  $siteLine = 'Test site: ' + $ui.RestoreSite
  & $ui.SetCard @{ View = 'toolrun'; Kicker = [string]$ui.Kick.Text; Sentence = 'The Restore dry run is running.'; P = @($siteLine, 'Reads the site. Nothing is written. ' + $ui.SignInHint) }
  $ui.Busy = $true; [System.Windows.Forms.Application]::DoEvents(); $dry = $null
  try { $dry = Invoke-RestorePlan (Get-BasePath) $ui.RestoreDir { [System.Windows.Forms.Application]::DoEvents() } }
  catch { $dry = @{ State = 'failed'; Lines = @(('The dry run stopped with an error [' + $_.Exception.GetType().Name + '].'), 'Nothing was changed.') } }
  finally { $ui.Busy = $false }
  if ($ui.Form.IsDisposed -or $script:closing) { return }
  if ($dry.State -ne 'plan') { & $ui.ToolResult 'Restore' $dry; return }
  $ui.RestoreDry = $dry; & $ui.VRestoreConfirm }

$ui.VRestoreConfirm = {
  <#
  .SYNOPSIS
  Restore, card 3 (view restconfirm): the dry run's counts for each list and, when rows would come back, the box for
  the app name.
  .DESCRIPTION
  The Administrator, 2026-11-21: the user types the app name, then RADE saves a fresh backup, then writes. With nothing
  to put back the card has Done only. Reads $ui.RestoreDry (Invoke-RestorePlan); takes no parameter.
  #>
  $dry = $ui.RestoreDry; $lines = @($dry.Lines); $siteLine = 'Test site: ' + $ui.RestoreSite
  if (-not $dry.Missing) { & $ui.SetCard @{ View = 'restconfirm'; Kicker = [string]$ui.Kick.Text; Sentence = 'Nothing to restore.'
      P = @($siteLine, $lines[0]); Lines = @($lines | Select-Object -Skip 1)
      Buttons = @(@{ Text = 'Done'; Kind = 'primary'; Act = $ui.ToolsBack }); Back = { & $ui.VRestorePick } }; return }
  $pauseDef = $script:app.Restore.Pause
  $flow = $(if ($pauseDef) { "RADE turns the app's pause switch on while it writes, then puts it back." } else { 'This app names no pause switch: its flows keep running while rows come back.' })
  # One operator (the Administrator, 2026-11-21): the record of re-made rows is in this RADE folder only.
  $oneOperator = 'Only one person runs Restore for this site, from this RADE folder.'
  & $ui.SetCard @{ View = 'restconfirm'; Light = 'you'; Kicker = [string]$ui.Kick.Text; Sentence = ('Put back ' + $dry.Missing + ' rows on the site?')
    P = @($siteLine, $lines[0], ('RADE first saves a fresh backup. Rows on the lists now are not changed. ' + $flow + ' ' + $oneOperator)); Lines = @($lines | Select-Object -Skip 1)
    Field = @{ Label = ('Type ' + $script:app.Name + ' to confirm'); Text = ''; Name = 'The app name, to confirm Restore' }; Focus = 'field'
    Buttons = @(@{ Text = 'Restore'; Kind = 'primary'; Act = { & $ui.RestoreGo } }); Back = { & $ui.VRestorePick } } }

# Restore, card 4: checks the typed name, then runs the write (Invoke-Restore) and shows its result. Takes nothing.
$ui.RestoreGo = {
  if ($ui.Busy) { return }
  if ($ui.Field.Text.Trim() -cne [string]$script:app.Name) { & $ui.Say1 ('Type the app name as shown: ' + $script:app.Name); return }
  & $ui.SetCard @{ View = 'toolrun'; Kicker = [string]$ui.Kick.Text; Sentence = 'Restore is running.'; P = @('It saves a fresh backup, then puts the missing rows back. Do not close RADE.') }
  $ui.Busy = $true; [System.Windows.Forms.Application]::DoEvents(); $res = $null
  try { $res = Invoke-Restore (Get-BasePath) $ui.RestoreDir $ui.RestoreDry { [System.Windows.Forms.Application]::DoEvents() } }
  catch { $res = @{ State = 'failed'; Path = ''; Lines = @(('Restore stopped with an error [' + $_.Exception.GetType().Name + '].'), 'Run Restore again: it puts back only what is still missing.') } }
  finally { $ui.Busy = $false; $ui.RestoreDry = $null }
  if ($ui.Form.IsDisposed -or $script:closing) { return }
  & $ui.ToolResult 'Restore' $res }

$ui.VUninstall = {
  <#
  .SYNOPSIS
  Uninstall, the first card: the test-site gate, then the Backups card (view unbackups; engine-v48, the orchestrator's
  choice of 2026-11-27 for DECISIONS 2026-11-26: keep the Backups folder, or remove it too).
  .DESCRIPTION
  Test sites only (the Restore gate: a site that only lacks the local mark goes to the mark card first, then back here).
  The Backups card asks one question with two buttons: "Keep the Backups folder" (the main button, Enter) and "Remove
  the Backups folder too"; each one goes to the confirm card ($ui.VUninstallConfirm). Back (Esc) goes to Maintenance.
  Takes no parameter.
  #>
  if ($ui.Busy) { return }
  $spMode = [bool]($script:spEnabled -and $script:app.Restore)
  if (-not $spMode) {
    $ui.UninstallSite = ''
    $ui.UninstallKeep = $false
    & $ui.VUninstallConfirm
    return
  }
  $siteCheck = Test-UninstallSite (Get-BasePath)
  # The mark card goes on to this card, and its Back returns to the Maintenance card.
  if ($siteCheck.NeedMark) { $ui.MarkNext = $ui.VUninstall; $ui.MarkBack = $ui.ToolsBack; & $ui.VRestoreMark; return }
  if (-not $siteCheck.Ok) { & $ui.ToolResult 'Uninstall' @{ State = 'refused'; Path = ''; Lines = @($siteCheck.Lines) }; return }
  $ui.UninstallSite = [string]$siteCheck.Name
  & $ui.SetCard @{ View = 'unbackups'; Light = 'you'; Kicker = [string]$ui.Kick.Text; Sentence = 'Keep the Backups folder?'
    P = @(('The Backups folder holds the backups of ' + (Get-AppWord) + '. Restore needs them.'))
    Buttons = @(@{ Text = 'Remove the Backups folder too'; Kind = ''; Act = { $ui.UninstallKeep = $false; & $ui.VUninstallConfirm } },
      @{ Text = 'Keep the Backups folder'; Kind = 'primary'; Act = { $ui.UninstallKeep = $true; & $ui.VUninstallConfirm } }); Back = { & $ui.VMaint $ui.MaintInst } } }

$ui.VUninstallConfirm = {
  <#
  .SYNOPSIS
  Uninstall, the confirm card (view unconfirm; engine-v40, 90-161.Z R43 E3, the Administrator, 2026-11-25).
  .DESCRIPTION
  The card names the test site, the backup, the app's Uninstall steps (a hand step says so), what goes to the Recycle
  Bin after them and the Backups choice of the card before ($ui.UninstallKeep; engine-v48); the person types the app
  name, then "Uninstall" (dark red: the one destructive action) runs it. Back goes to the Backups card (or Maintenance for local-only). Takes no parameter.
  #>
  if ($ui.Busy) { return }
  $spMode = [bool]($script:spEnabled -and $script:app.Restore)
  $all = @($script:app.Uninstall); $n = @($script:app.Backup).Count
  $rows = @(for ($i = 0; $i -lt $all.Count; $i++) { $st = $steps[[int]$all[$i]]
      ([string]($i + 1) + '. ' + (Get-StepTitle $st) + $(if ($st.Kind -eq 'guide') { ' (you do this step)' } else { '' })) })
  if ($spMode) {
    $what = 'RADE first backs up ' + $n + ' list(s). Then it runs ' + $(if ($all.Count -eq 1) { 'this step' } else { 'these ' + $all.Count + ' steps' }) + ' of ' + $script:app.Name + '.'
    $what += ' They remove what the install made on the site.'
    $clean = $(if ($ui.UninstallKeep) { 'After the steps, RADE moves the app files, the runner copy, the shortcut and the install record to the Recycle Bin. Your choice: keep the Backups folder.' }
      else { 'After the steps, RADE moves the app folder, the runner copy, the shortcut and the install record to the Recycle Bin. Your choice: remove the Backups folder too.' })
  } else {
    $what = $(if ($all.Count -gt 0) {
        'RADE runs ' + $(if ($all.Count -eq 1) { 'this step' } else { 'these ' + $all.Count + ' steps' }) + ' of ' + $script:app.Name + '.'
      } else { 'RADE removes the local files of ' + $script:app.Name + '.' })
    $clean = 'RADE moves the app folder, the runner copy, the shortcut and the install record to the Recycle Bin.'
  }
  if (-not @(Get-OtherRecordKey (Get-InstalledKey $script:app)).Count) { $clean += ' No other app has an install record on this computer, so RADE\Config and RADE\runners go to the Recycle Bin too.' }
  $pList = $(if ($spMode) { @(('Test site: ' + $ui.UninstallSite), $what, $clean) } else { @($what, $clean) })
  $sent = $(if ($spMode) { 'Uninstall ' + $script:app.Name + ' from the test site?' } else { 'Uninstall ' + $script:app.Name + ' from this computer?' })
  $backAct = $(if ($spMode) { { & $ui.VUninstall } } else { { & $ui.VMaint $ui.MaintInst } })
  & $ui.SetCard @{ View = 'unconfirm'; Light = 'you'; Kicker = [string]$ui.Kick.Text; Sentence = $sent
    P = $pList; Lines = $rows
    Field = @{ Label = ('Type ' + $script:app.Name + ' to confirm'); Text = ''; Name = 'The app name, to confirm Uninstall' }; Focus = 'field'
    Buttons = @(@{ Text = 'Uninstall'; Kind = 'danger'; Act = { & $ui.UninstallGo } }); Back = $backAct } }

$ui.UninstallGo = {
  <#
  .SYNOPSIS
  Uninstall, the run: checks the typed app name, runs Invoke-Uninstall (part 17) with the Backups choice, then shows the result card.
  .DESCRIPTION
  The name must match exactly, capitals too. The run card names each step; a hand step shows its own card. Takes no
  parameter.
  #>
  if ($ui.Busy) { return }
  if ($ui.Field.Text.Trim() -cne [string]$script:app.Name) { & $ui.Say1 ('Type the app name as shown: ' + $script:app.Name); return }
  $spMode = [bool]($script:spEnabled -and $script:app.Restore)
  $siteLine = $(if ($spMode) { 'Test site: ' + $ui.UninstallSite } else { 'Local uninstall (no SharePoint site).' })
  # The run card with one sentence: what Uninstall does now. Takes the sentence.
  $card = { param($Text) & $ui.SetCard @{ View = 'toolrun'; Kicker = [string]$ui.Kick.Text; Sentence = $Text; P = @($siteLine, 'Do not close RADE. ' + $ui.SignInHint) } }
  & $card $(if ($spMode) { 'Uninstall is saving a backup.' } else { 'Uninstall is removing local files.' })
  $ui.Busy = $true; [System.Windows.Forms.Application]::DoEvents(); $res = $null
  # Before each step: the run card names it. Takes the step, its number and the count.
  $onStep = { param($St, $I, $N) & $card ('Uninstall step ' + $I + ' of ' + $N + ': ' + (Get-StepTitle $St)); [System.Windows.Forms.Application]::DoEvents() }
  try { $res = Invoke-Uninstall (Get-BasePath) { [System.Windows.Forms.Application]::DoEvents() } $onStep ([bool]$ui.UninstallKeep) }   # the Backups card's choice
  catch { $why = 'Uninstall stopped with an error [' + $_.Exception.GetType().Name + '].'
    $res = @{ State = 'failed'; Path = ''; Lines = @($why, 'Select "Uninstall" again: its steps remove only what is still there.') } }
  finally { $ui.Busy = $false }
  if ($ui.Form.IsDisposed -or $script:closing) { return }
  & $ui.ToolResult 'Uninstall' $res }

$ui.Form.Add_Shown({
  & $ui.WheelOn $ui.Form
  $ui.Opened = $true; & $ui.FormDpi; $ui.Scaled = $true   # the form has its scale now: from here the size handlers work (each runs once below or on the first card)
  foreach ($b in @($ui.BtnKind.Keys)) { & $ui.FitBtn $b }   # UI standard v1: every button at its fixed size for this scale
  & $ui.Place
  & $ui.Fit; $ui.ShownAt = & $ui.WinNow; & $ui.LogScale; $ui.Anim.Start()   # E4: this window's SCALE line for the round's results
  & $ui.Boot })
$ui.Form.Add_SystemColorsChanged({ & $ui.Recolor $false })   # a contrast theme came on or went off (UI standard v1, B11): the window's own thread
$ui.Form.Add_FormClosing({
  # The window's X (there is no Exit button): ask first only while a step runs, because closing stops it (R17).
  if ($ui.Running -and -not $script:closing) {
    $exitMsg = 'A step is running. If you exit now, RADE stops it and the round ends as STOPPED (the report in the results folder says so). Exit now?'
    $a = [System.Windows.Forms.MessageBox]::Show(
      $ui.Form, $exitMsg, 'RADE - Exit',
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Warning,
      [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ([string]$a -ne 'Yes') { $_.Cancel = $true; return }
  }
  $script:closing = $true; try { $ui.Anim.Stop(); $ui.ResizeT.Stop(); $ui.TimeT.Stop() } catch { $null = $_ }
  try { $f = $ui.Form; $ui.CloseAt = & $ui.WinNow; $st = [string]$f.WindowState; if ($st -eq 'Minimized') { $st = 'Normal' }
    $b = $(if ([string]$f.WindowState -eq 'Normal') { $f.Bounds } else { $f.RestoreBounds })
    $cp = ($ui.CloseAt -split '/'); $cs = ([string]$cp[0] -split 'x')   # split on / first: "Maximized" holds an x
    Save-WindowState $b.X $b.Y $b.Width $b.Height $st ([int]$ui.Dpi) ([int]$cs[0]) ([int]$cs[1]) ([string]$cp[1])
    Write-Host ('RADE window at close: client ' + ($ui.CloseAt -replace '/', ', ') + '.') } catch { $null = $_ }
  if ($script:child -and -not $script:child.HasExited) { try { $script:child.Kill() } catch { $null = $_ } } })
# The window is the main form of this thread, with no owner (R24: shown with ShowDialog from PowerShell ISE, ISE owned
# it, so it had no taskbar button and could not be restored after it was minimized). When a message loop already runs
# on this thread, Application.Run cannot start one: then ShowDialog, as before. Run disposes the form when it closes.
$ui.Opened = $false
try { [System.Windows.Forms.Application]::Run($ui.Form) }
catch {
  $ex = $_.Exception; while ($ex -and -not ($ex -is [System.InvalidOperationException])) { $ex = $ex.InnerException }
  if (-not $ex -or $ui.Opened -or $ui.Form.IsDisposed) { throw }   # only a loop that could not start: the window never showed
  [void]$ui.Form.ShowDialog()
}
foreach ($o in @($ui.Trash)) { try { $o.Dispose() } catch { $null = $_ } }   # after the window has closed: no handler is running
return
