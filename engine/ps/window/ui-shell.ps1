# RADE window part 02, the fixed parts: the band with the stage now, the light line under it, the bottom line (Details
# and Help links) and the progress bars with the timer that eases them. Builds on 01-setup.ps1.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.
# Network: none.
# Writes: none.
# Credentials: none.

# ---- The fixed parts: the band, the light line under it, the card, the bottom line and the bar on the bottom edge.
# The band (plan engine-v48 D5, "B + C"; the Administrator, 2026-11-27): 56 px in the band color, the logo at 36 px, the word in
# capitals and "in RADE" under it; at the right the stage now (Choose, Check or Install: a disc with its number, a tick when
# the run passed, and a 3 px underline, $ui.PaintStage). Full size also shows the subtitle line and, at the right, the
# version and round; half size (a window narrower than $ui.Z.Narrow at 100 %) shows only the logo, the word, "in RADE" and
# the stage ($ui.BandFit). It replaces the logo block of engine-v43 to v47 (logo 64 px, word, line, subtitle).
$ui.Band = New-Object System.Windows.Forms.Panel
$ui.Band.Dock = 'Top'; $ui.Band.Height = $ui.Z.BandH; $ui.Band.BackColor = $ui.C.Band; $ui.Band.AccessibleName = 'Band'
$ui.BandRaw = @{}   # the whole text of each band label (its shown text can be shortened)
# Makes one text of the band: a label in the band colors; $ui.BandFit shortens its text ($ui.Shorten: no tooltip) when its
# room is short. Takes the font, the color and the screen-reader name; gives back the label.
$ui.BandText = { param($Font, $Color, [string]$Name) $l = New-Object System.Windows.Forms.Label; $l.AutoSize = $false
  $l.UseMnemonic = $false; $l.Font = $Font; $l.ForeColor = $Color; $l.BackColor = $ui.C.Band; $l.TextAlign = 'MiddleLeft'; $l.AccessibleName = $Name; $l }
# Reads one logo from base64 PNG text. Takes the text; gives back the image, or $null (no text, or not readable).
$ui.LogoImg = { param([string]$Png) if (-not $Png) { return $null }
  try { return [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(, [System.Convert]::FromBase64String($Png)))) } catch { return $null } }   # no logo: the band shows its text only
$ui.RadeImg = & $ui.LogoImg $logoPng; $ui.AppImg = & $ui.LogoImg $ui.AppPng   # RADE's logo; the app's logo of the theme (01-setup.ps1)
$ui.Logo = New-Object System.Windows.Forms.PictureBox
$ui.Logo.Size = New-Object System.Drawing.Size($ui.Z.BandLogo, $ui.Z.BandLogo); $ui.Logo.SizeMode = 'Zoom'; $ui.Logo.BackColor = $ui.C.Band; $ui.Logo.AccessibleName = 'RADE logo'
$ui.BandWord = & $ui.BandText $ui.F.Word $ui.C.BandInk 'Name'
$ui.BandSub = & $ui.BandText $ui.F.Small $ui.C.BandMuted 'in RADE'
$ui.BandLine = & $ui.BandText $ui.F.Small $ui.C.BandMuted 'Subtitle'
$ui.BandVer = & $ui.BandText $ui.F.Small $ui.C.BandMuted 'Version and round'; $ui.BandVer.TextAlign = 'MiddleRight'
$ui.Stage = New-Object System.Windows.Forms.Panel
$ui.Stage.BackColor = $ui.C.Band; $ui.Stage.AccessibleRole = 'StaticText'; $ui.Stage.AccessibleName = 'Stage now'
$ui.StageNow = @{ N = 1; Word = 'Choose'; Done = $false }
foreach ($c in @($ui.Logo, $ui.BandWord, $ui.BandSub, $ui.BandLine, $ui.BandVer, $ui.Stage)) { [void]$ui.Band.Controls.Add($c) }
# A contrast theme that changes while the window is open ($ui.Recolor) finds a part's token by its color; BandInk and White
# have one color in the light set, so the band's parts are given their tokens here (the chip's: 03-card.ps1).
foreach ($c in @($ui.Logo, $ui.Stage)) { $ui.Roles[$c] = @{ BackColor = 'Band' } }; $ui.Roles[$ui.BandWord] = @{ ForeColor = 'BandInk'; BackColor = 'Band' }
foreach ($c in @($ui.BandSub, $ui.BandLine, $ui.BandVer)) { $ui.Roles[$c] = @{ ForeColor = 'BandMuted'; BackColor = 'Band' } }; $ui.Roles[$ui.Band] = @{ BackColor = 'Band' }
# The stage of each card: 1 Choose (what to install or do), 2 Check (the checks and Ready), 3 Install (the run and its end).
$ui.StageViews = @{ site = 2; checking = 2; fail = 2; need = 2; ready = 2; nodrive = 2; run = 3; hand = 3; handfail = 3; answer = 3; answerfail = 3; feedback = 3
  done = 3; review = 3; stopped = 3; stepfail = 3; cancelq = 3 }
$ui.StageWords = @('Choose', 'Check', 'Install')
# Sets the stage now for a card. Takes the view and whether the run passed (a tick in the disc); repaints the stage.
$ui.SetStage = { param([string]$View, [bool]$Done) $n = $(if ($ui.StageViews.ContainsKey($View)) { [int]$ui.StageViews[$View] } else { 1 })
  $ui.StageNow = @{ N = $n; Word = [string]$ui.StageWords[$n - 1]; Done = $Done }
  $ui.Stage.AccessibleName = 'Stage now: ' + $ui.StageNow.Word + ', ' + $n + ' of 3' + $(if ($Done) { ', passed' } else { '' }); & $ui.BandFit; $ui.Stage.Invalidate() }
$ui.PaintStage = {
  <#
  .SYNOPSIS
  Draws the stage now: a disc in the band's text color with the number (a tick when the run passed), the word, and a 3 px
  underline as wide as the stage (Cards v2 mock).
  .PARAMETER P
  The stage panel.
  .PARAMETER G
  Its graphics.
  .OUTPUTS
  Nothing; a failure draws nothing (the band keeps its color).
  #>
  param($P, $G)
  try {
    $G.Clear($ui.C.Band); $G.SmoothingMode = 'AntiAlias'; $d = & $ui.Sc $ui.Z.Disc
    $h = $P.ClientSize.Height; $y = [int](($h - $d) / 2); $u = & $ui.Sc 3
    $br = New-Object System.Drawing.SolidBrush($ui.C.BandInk); $G.FillEllipse($br, 0, $y, $d, $d); $br.Dispose()
    if ($ui.StageNow.Done) {
      $pt = [System.Drawing.PointF[]]@(
        @(0.28, 0.52), @(0.44, 0.68), @(0.74, 0.34) |
          ForEach-Object { New-Object System.Drawing.PointF([single]($d * $_[0]), [single]($y + $d * $_[1])) }
      )
      $pn = New-Object System.Drawing.Pen($ui.C.Band, [single](& $ui.Sc 2)); $G.DrawLines($pn, $pt); $pn.Dispose()   # the tick: the run passed
    }
    else { & $ui.Word $G ([string]$ui.StageNow.N) $ui.F.SmallB $ui.C.Band 0 $y $d $d 'HorizontalCenter, VerticalCenter, NoPrefix, SingleLine' }
    $sx = $d + (& $ui.Sc 8); $sw = $P.ClientSize.Width - $sx
    & $ui.Word $G ([string]$ui.StageNow.Word) $ui.F.SmallB $ui.C.BandInk $sx 0 $sw $h 'Left, VerticalCenter, NoPrefix, SingleLine'
    $ub = New-Object System.Drawing.SolidBrush($ui.C.BandInk)
    $G.FillRectangle($ub, 0, ($h - $u), $P.ClientSize.Width, $u); $ub.Dispose()
  } catch { $null = $_ } }   # a stage that cannot be drawn: the band shows the rest
$ui.Stage.Add_Paint({ & $ui.PaintStage $this $_.Graphics })
$ui.BandFit = {
  <#
  .SYNOPSIS
  Places the parts of the band for the window's width: the logo and the name column at the left, the stage at the right,
  and at full size the subtitle line after the name and the version and round before the stage.
  .DESCRIPTION
  Half size (a window narrower than $ui.Z.Narrow at 100 %, plan engine-v48 step 2) hides the subtitle line and the
  version. Each text is one line, as tall as its font, and ends with "..." when its room is short.
  .OUTPUTS
  Nothing. Does nothing before the window has its scale.
  #>
  if (-not $ui.Scaled) { return }
  try { $W = [int]$ui.Band.ClientSize.Width; $H = [int]$ui.Band.ClientSize.Height; $pad = & $ui.Sc $ui.Z.G4; $gap = & $ui.Sc $ui.Z.G3
    $ui.Narrow = ([int]$ui.Form.ClientSize.Width -lt (& $ui.Sc $ui.Z.Narrow)); $lg = & $ui.Sc $ui.Z.BandLogo
    $ui.Logo.Visible = [bool]$ui.Logo.Image; $x0 = $pad; if ($ui.Logo.Visible) { $ui.Logo.Bounds = New-Object System.Drawing.Rectangle($pad, [int](($H - $lg) / 2), $lg, $lg); $x0 = $pad + $lg + $gap }
    $sw = (& $ui.Sc ($ui.Z.Disc + $ui.Z.G2)) + [int](& $ui.Meas ([string]$ui.StageNow.Word) $ui.F.SmallB 100000).Width + (& $ui.Sc $ui.Z.G1)
    $ui.Stage.Bounds = New-Object System.Drawing.Rectangle(($W - $pad - $sw), 0, $sw, $H); $rx = $W - $pad - $sw - $gap
    foreach ($l in @($ui.BandWord, $ui.BandSub, $ui.BandLine, $ui.BandVer)) { if ([string]$l.Text -cne [string]$ui.BandRaw[$l]) { $l.Text = [string]$ui.BandRaw[$l] } }   # the whole texts first
    $ui.BandVer.Visible = [bool](-not $ui.Narrow -and [string]$ui.BandVer.Text)
    if ($ui.BandVer.Visible) {
      $vw = [int](& $ui.Meas ([string]$ui.BandVer.Text) $ui.F.Small 100000).Width + (& $ui.Sc 4)
      $vh = & $ui.BandLH $ui.BandVer
      $ui.BandVer.Bounds = New-Object System.Drawing.Rectangle(($rx - $vw), [int](($H - $vh) / 2), $vw, $vh); $rx -= $vw + $gap
    }
    $wh = & $ui.BandLH $ui.BandWord; $sh = $(if ([string]$ui.BandSub.Text) { & $ui.BandLH $ui.BandSub } else { 0 }); $ui.BandSub.Visible = [bool]$sh
    $bh = [int][math]::Max((& $ui.Sc $ui.Z.BandH), $wh + $sh); if ($bh -ne $H) { $H = $bh; $ui.Band.Height = $bh }   # 56 px at 100 %, or what the word and "in RADE" need when that is more (each fit)
    $top = [int](($H - $wh - $sh) / 2)
    $wWord = (& $ui.Meas ([string]$ui.BandWord.Text) $ui.F.Word 100000).Width
    $wSub = (& $ui.Meas ([string]$ui.BandSub.Text) $ui.F.Small 100000).Width
    $cw = [math]::Max($wWord, $wSub) + (& $ui.Sc 4); $cw = [int][math]::Max((& $ui.Sc 40), [math]::Min($cw, $rx - $x0))
    $ui.BandWord.Bounds = New-Object System.Drawing.Rectangle($x0, $top, $cw, $wh); if ($sh) { $ui.BandSub.Bounds = New-Object System.Drawing.Rectangle($x0, ($top + $wh), $cw, $sh) }
    foreach ($l in @($ui.BandWord, $ui.BandSub)) { & $ui.Shorten $l ([string]$ui.BandRaw[$l]) $cw }   # a word wider than its room ends with "..." (no tooltip)
    $lx = $x0 + $cw + (& $ui.Sc $ui.Z.G4); $lh = & $ui.BandLH $ui.BandLine
    $ui.BandLine.Visible = [bool](-not $ui.Narrow -and [string]$ui.BandLine.Text -and ($rx - $lx) -ge (& $ui.Sc 60))
    if ($ui.BandLine.Visible) {
      $ui.BandLine.Bounds = New-Object System.Drawing.Rectangle($lx, [int](($H - $lh) / 2), ($rx - $lx), $lh)
      & $ui.Shorten $ui.BandLine ([string]$ui.BandRaw[$ui.BandLine]) ($rx - $lx)
    }
  } catch { $null = $_ } }   # no measure yet: the next fit places them
$ui.Band.Add_SizeChanged({ & $ui.BandFit })
# The height a band label needs for its text, as Windows Forms measures a label (GetPreferredSize: the text with the
# label's own padding; the self-check compares the same number), else one line of its font. Takes the label.
$ui.BandLH = { param($L) $h = 0; try { $h = [int]$L.GetPreferredSize((New-Object System.Drawing.Size(0, 0))).Height } catch { $null = $_ }   # no measure: one line of the font
  if ($h -le 0) { $h = [int](& $ui.LineH $L.Font) }; return $h }
# Sets the texts and the logo of the band. Takes $true once an application is chosen (its logo, word and subtitle), else
# RADE's own (the word RADE, RADE's full name as the subtitle). An app with productName and a logo shows its own from the
# first screen (engine-v47, the Administrator, 2026-11-26: "it should be the KANON logo").
$ui.SetBand = { param([bool]$App)
  $own = [bool]($App -or ([string]$appProduct -and $ui.AppImg)); $img = $(if ($own -and $ui.AppImg) { $ui.AppImg } else { $ui.RadeImg })
  if (-not [object]::ReferenceEquals($ui.Logo.Image, $img)) { $ui.Logo.Image = $img }; $ui.Logo.AccessibleName = $(if ($own -and $ui.AppImg) { (Get-AppWord) + ' logo' } else { 'RADE logo' })
  $ui.BandRaw[$ui.BandWord] = $(if ($own) { (Get-AppWord).ToUpperInvariant() } else { 'RADE' }); $ui.BandRaw[$ui.BandSub] = $(if ($own) { 'in RADE' } else { '' })
  $ui.BandRaw[$ui.BandLine] = $(if ($own) { [string](Get-AppSubtitle) } else { $ui.Tagline }); $r = $(if (Test-RunnerStart) { '' } else { [string]$round })
  $ui.BandRaw[$ui.BandVer] = (@($(if ($App -and [string]$script:app.Version) { [string]$script:app.Version }), $r) | Where-Object { $_ }) -join $dot
  foreach ($l in @($ui.BandWord, $ui.BandSub, $ui.BandLine, $ui.BandVer)) { $l.Text = [string]$ui.BandRaw[$l] }; & $ui.BandFit }
# The light line under the band (plan engine-v48 step 2): 4 px in the line color when nothing is asked, 4 px green when a
# run passed, 8 px yellow on your turn (yellow means only that), 8 px in the error color on a failure. The card's words
# always say it too.
$ui.Light = New-Object System.Windows.Forms.Panel
$ui.Light.Dock = 'Top'; $ui.Light.Height = $ui.Z.LineIdle; $ui.Light.BackColor = $ui.C.Hair; $ui.Light.AccessibleRole = 'StaticText'; $ui.Light.AccessibleName = 'Status light: off'
# Sets the light line. Takes the card's Light: 'you', 'bad', 'pass' or none.
$ui.SetLight = { param([string]$State)
  $loud = ($State -in 'you', 'bad'); $h = $(if ($loud) { $ui.Z.LineLoud } else { $ui.Z.LineIdle }); if ($ui.Scaled) { $h = & $ui.Sc $h }; if ($ui.Light.Height -ne $h) { $ui.Light.Height = $h }
  $ui.Light.BackColor = $(if ($State -eq 'you') { $ui.C.Yellow } elseif ($State -eq 'bad') { $ui.C.Red } elseif ($State -eq 'pass') { $ui.C.Green } else { $ui.C.Hair })
  $ui.Light.AccessibleName = 'Status light: ' + $(if ($State -eq 'you') { 'your turn' } elseif ($State -eq 'bad') { 'failed' } elseif ($State -eq 'pass') { 'passed' } else { 'off' }) }
$ui.Bottom = New-Object System.Windows.Forms.TableLayoutPanel
$ui.Bottom.Dock = 'Bottom'; $ui.Bottom.Height = 46; $ui.Bottom.AutoSize = $true; $ui.Bottom.AutoSizeMode = 'GrowAndShrink'
$ui.Bottom.MinimumSize = New-Object System.Drawing.Size(0, 46); $ui.Bottom.ColumnCount = 5; $ui.Bottom.RowCount = 1
$ui.Bottom.Padding = (& $ui.Pad ($ui.Z.Inset - $ui.Z.M) 3 $ui.Z.Inset 3); $ui.Bottom.BackColor = $ui.C.White
foreach ($cs in @('AutoSize', 'AutoSize', 'AutoSize', 'Percent', 'AutoSize')) { [void]$ui.Bottom.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle($cs, 100))) }
[void]$ui.Bottom.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))   # as tall as the links with their margin and focus ring, 46 at least (R24: 1 px cut at 150 %)
$ui.RecB = & $ui.LinkBtn 'Details (F2)'; $ui.RecB.AccessibleName = 'Details: all checks, steps, files and the log (F2)'
# UI standard v1 (B6, the Administrator, 2026-11-20): one Back pattern, a "Back (Esc)" button (40 high: one height, Cards v2) at the left end of the
# card's action row (03-card.ps1 puts it there); Details (F2), Help (F1) and Feedback are the only links of the bottom line.
$ui.BackB = & $ui.Btn 'action'; $ui.BackB.Text = 'Back (Esc)'; $ui.BackB.AccessibleName = 'Back (Esc)'; $ui.BackB.Visible = $false
# Feedback (B13): the same place on every card of a test round; it opens the feedback card for the card on screen ($ui.VNote).
$ui.FeedB = & $ui.LinkBtn 'Feedback'; $ui.FeedB.AccessibleName = 'Feedback: a comment and a picture of this window for the round'; $ui.FeedB.Visible = $false
$ui.RightL = & $ui.Label $ui.F.Small $ui.C.Gray 0; $ui.RightL.Anchor = 'Right'; $ui.RightL.Visible = $true; $ui.RightL.TextAlign = 'MiddleRight'
# Its widest values (the percent of a run, the count of the checks, a result word, the time a run took: $ui.FixW): one size.
$ui.Most[$ui.RightL] = @('100 %', 'Check 999 of 999', 'Needs review', 'Stopped', '999m 59s'); $ui.RightL.Add_TextChanged({ & $ui.FixW $this })
# L6 (the Administrator, 2026-11-19): "Help (F1)" opens the RADE tour again; shown on a card that is not busy ($ui.HelpViews).
$ui.TourB = & $ui.LinkBtn 'Help (F1)'; $ui.TourB.AccessibleName = 'Help: the RADE tour (F1)'; $ui.TourB.Visible = $false
# R32: no top anchor, so a link sits on the middle of the line, as the text at the right does (they were 3.5 px apart at 150 %)
foreach ($b in @($ui.RecB, $ui.TourB, $ui.FeedB)) { $b.Anchor = 'Left' }
$ui.Bottom.Controls.Add($ui.RecB, 0, 0); $ui.Bottom.Controls.Add($ui.TourB, 1, 0); $ui.Bottom.Controls.Add($ui.FeedB, 2, 0); $ui.Bottom.Controls.Add($ui.RightL, 4, 0); & $ui.Ring $ui.Bottom
$ui.Edge = & $ui.MkBar 'all' 'Progress of all steps'; $ui.Edge.Dock = 'Bottom'
$ui.Anim = New-Object System.Windows.Forms.Timer
$ui.Anim.Interval = 30
$ui.Anim.Add_Tick({
  if ([bool]$ui.Busy -ne [bool]$ui.BusyShown) { $ui.BusyShown = [bool]$ui.Busy; try { $ui.Form.Invalidate($true) } catch { $null = $_ } }
  foreach ($b in @($ui.Bars.Values)) {
    $d = $b.Target - $b.Shown
    if ([math]::Abs($d) -gt 0.0005) { $b.Shown = $(if ($ui.Calm) { $b.Target } else { $b.Shown + $d * 0.18 }); $b.Panel.Invalidate() }
  }
})

# RADE window part 05, alignment and layout: centers a row of controls, breaks and fits long text, keeps the
# card inside the window (Squeeze) and runs the layout self-check. Builds on 03-card.ps1.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# ---- Alignment (the Administrator, 2026-11-15, after the R24 pictures; docs/window-design.md "Sizes"). An aligned row:
# its parts share one vertical midpoint (each part's top margin is set from the tallest part). One left edge per card:
# a label draws its text after a padding that grows with its font (Windows text padding: about 1/6 of the line), so a
# 22 pt headline started about 3 px right of a 9 pt line and of the buttons. Each part moves by its own padding.
# Where a part's ink starts, measured: the part drawn into a bitmap by Windows (DrawToBitmap: the same drawing as on
# screen, with its own flags, padding and the first glyph's side bearing), the first column that differs from its back
# color. A button with an edge starts at its edge. Without a bitmap (the test stand-ins), the text padding Windows adds
# (1/6 em, rounded up). R24 job: a formula and a with/without-NoPadding measure both missed by 3 to 6 px.
# One edge per card at $ui.Sc 10 from the card's column: room for the largest text inset (a 22 pt headline: about 7)
# and for a button's 4 px margin, because a negative margin is taken as 0 in a table cell (R24 job).
$ui.FitEdges = {
  <#
  .SYNOPSIS
  Puts the ink of each part of the card on one edge, $ui.Sc 10 into the card's column (the help above).
  .DESCRIPTION
  Texts by their measured ink; the buttons by their own 4 px margin; a list or a box (the Run card's lists and bar, the
  WHAT TO DO box) by its own edge; the YOUR TURN chip by its yellow box, else the line in capitals by its ink.
  .OUTPUTS
  Nothing. Changes left margins; a part that cannot be measured keeps its margin until the next fit.
  #>
  try {
    $mm = & $ui.Sc $ui.Z.M; $x = & $ui.Sc 10; $ui.EdgeX = $x
    foreach ($l in @($ui.P[0], $ui.P[1], $ui.P[2], $ui.P[3], $ui.PathL, $ui.PathT, $ui.Note, $ui.Help, $ui.Foot, $ui.Close, $ui.FieldL, $ui.TestL)) { & $ui.SetLeft $l ($x - (& $ui.Ink $l)) }
    & $ui.SetLeft $ui.TickP 0; & $ui.SetLeft $ui.SentRow ($x - $(if ($ui.TickP.Visible) { & $ui.Ink $ui.TickP } else { & $ui.Ink $ui.Sent }))
    & $ui.SetLeft $ui.PctRow ($x - (& $ui.Ink $ui.PctL)); foreach ($b in @($ui.RunBar, $ui.RunA, $ui.RunRow, $ui.RunB, $ui.Todo)) { & $ui.SetLeft $b $x }   # a list or a box: its edge on the card edge
    & $ui.SetLeft $ui.ErrRow ($x - $ui.ErrBox.Margin.Left)
    & $ui.SetLeft $ui.BtnRow ($x - $mm)   # a button's own 4 px margin (room for the ring)
    $l1 = @($ui.LinkRow.Controls | Where-Object { $_.Visible })[0]; if ($l1) { & $ui.SetLeft $ui.LinkRow ($x - $mm - (& $ui.Ink $l1)) }   # a link's text is in the middle of its box
    if ($ui.Guide.Visible) { & $ui.SetLeft $ui.Guide ($x - (& $ui.GuideInk)) }   # the widest number sits on the edge; shorter ones are right-aligned to it
    & $ui.SetLeft $ui.Opts $x
    # The header row: the chip's box starts on the edge (its yellow is the part a person sees), else the kicker's ink does.
    if ($ui.Chip.Visible) { & $ui.SetLeft $ui.Chip $x; & $ui.SetLeft $ui.Kick 0 } else { & $ui.SetLeft $ui.Kick ($x - (& $ui.Ink $ui.Kick)) } } catch { $null = $_ } }
# The x of a control inside one of its parents (the sum of the lefts on the way up). Takes the control and the parent;
# gives back the pixels.
$ui.LeftIn = { param($C, $P) $x = 0; $c = $C; while ($c -and -not [object]::ReferenceEquals($c, $P)) { $x += [int]$c.Left; $c = $c.Parent }; $x }
# The step bar's own top margin, scaled ($ui.Z.BarTop at 100 %). Takes nothing; gives back the pixels.
$ui.BarTop = { & $ui.Sc $ui.Z.BarTop }
# The height a label has with a text in it. An empty label asks for less (31 against 33 px at 150 %; R32), so a row aligned
# before its first text was 1.5 px off the bar afterwards. Takes the label; gives back the pixels.
$ui.LabelH = { param($L)
  try {
    if (-not [string]$L.Text) { $ui.Probe.Font = $L.Font; $ui.Probe.Text = '0'; return [int]$ui.Probe.PreferredSize.Height }
  } catch { $null = $_ }   # no probe: the label's own answer
  return [int]$L.PreferredSize.Height }
# R29b N3: the time in this step and its count sit on the vertical midpoint of the step's bar (the same flow line: each
# part's top is the line's top plus its top margin). A text taller than the bar's place moves the bar down; that lift is
# worked out from $ui.BarTop each time, so it never adds up. Takes nothing; changes the top margins of $ui.StepBar,
# $ui.StepTime and $ui.StepFrac.
$ui.AlignTick = { try {
    $b0 = [int](& $ui.BarTop)
    $h = [int](& $ui.LabelH $ui.StepTime); $lift = [int][math]::Max(0, [math]::Ceiling($h / 2.0 - ($b0 + [double]$ui.StepBar.Height / 2.0)))   # a text taller than the bar's place: the bar moves down
    $m = $ui.StepBar.Margin; if ($m.Top -ne $b0 + $lift) { $ui.StepBar.Margin = New-Object System.Windows.Forms.Padding($m.Left, ($b0 + $lift), $m.Right, $m.Bottom) }
    $bm = [double]$ui.StepBar.Margin.Top + [double]$ui.StepBar.Height / 2.0
    foreach ($l in @($ui.StepTime, $ui.StepFrac)) { $hl = [int](& $ui.LabelH $l); $t = [int][math]::Max(0, [math]::Round($bm - $hl / 2.0, [System.MidpointRounding]::AwayFromZero)); $m = $l.Margin
      if ($m.Top -ne $t) { $l.Margin = New-Object System.Windows.Forms.Padding($m.Left, $t, $m.Right, $m.Bottom) } } } catch { $null = $_ } }   # no bar yet: the next fit aligns the row
$ui.FitBar = {
  <#
  .SYNOPSIS
  Sizes the Run card's parts for the card's width (Cards v2): the bar of the whole run and the step lists as wide as the
  card's text; in the running step's row the name with RUNNING at the right end, the summary and the now-doing line
  wrapped to the row, and the step bar as wide as the room beside the time and the count (R47: it starts where the name does).
  .OUTPUTS
  Nothing. Changes widths, wrap widths and margins; a size that cannot be read waits for the next fit.
  #>
  try { $cw = [int]$ui.ContentW; if ($cw -le 0) { return }; $pad = & $ui.Sc $ui.Z.G2; $in = $cw - 2 * $pad
    $ui.RunBar.Width = $cw; foreach ($r in @($ui.RunA, $ui.RunB)) { $r.Width = $cw; & $ui.SizeRuns $r }
    foreach ($r in @($ui.RunRow, $ui.Todo)) { $r.MinimumSize = New-Object System.Drawing.Size($cw, 0); $r.MaximumSize = New-Object System.Drawing.Size($cw, 0) }
    $ww = [int]$ui.RunWord.PreferredSize.Width; & $ui.SetWrap $ui.StepName ($in - $ww - (& $ui.Sc $ui.Z.G3))
    & $ui.SetWrap $ui.StepSum $in; & $ui.SetWrap $ui.Now $in; & $ui.SetWrap $ui.TodoT ($cw - 2 * (& $ui.Sc $ui.Z.G3))
    $m = $ui.StepName.Margin; $gr = [int][math]::Max(0, $in - [int]$ui.StepName.Width - $ww)
    if ($m.Right -ne $gr) { $ui.StepName.Margin = New-Object System.Windows.Forms.Padding(0, $m.Top, $gr, $m.Bottom) }   # RUNNING at the right end
    $ui.StepRow.MaximumSize = New-Object System.Drawing.Size($in, 0); $bm = $ui.StepBar.Margin
    $w = $in - $bm.Left - $bm.Right - [int]$ui.StepTime.Width - [int]$ui.StepFrac.Width - $ui.StepFrac.Margin.Left - (& $ui.Sc 2)
    $w = [int][math]::Max((& $ui.Sc 60), $w); if ($ui.StepBar.Width -ne $w) { $ui.StepBar.Width = $w } } catch { $null = $_ } }   # no measure yet: the next fit sets it
# Centers a row of controls up and down by changing their top and bottom margins. Takes the controls and the top margin
# of the row; gives back nothing.
$ui.AlignRow = { param($Parts, [int]$Base)
  try { $hs = @($Parts | ForEach-Object { if ($_.AutoSize) { [int]$_.PreferredSize.Height } else { [int]$_.Height } }); $hh = [int]($hs | Measure-Object -Maximum).Maximum
    for ($i = 0; $i -lt $Parts.Count; $i++) { $m = $Parts[$i].Margin; $t = $Base + [int][math]::Floor(($hh - $hs[$i]) / 2); $b = $Base + $hh - $hs[$i] - ($t - $Base)
      if ($m.Top -ne $t -or $m.Bottom -ne $b) { $Parts[$i].Margin = New-Object System.Windows.Forms.Padding($m.Left, $t, $m.Right, $b) } } } catch { $null = $_ } }
# Returns the controls of one aligned row (Top, FieldRow, ...). Takes the row name.
$ui.RowParts = { param([string]$Row)
  switch ($Row) {
    'Head' { @(@($ui.Chip, $ui.Kick) | Where-Object { $_.Visible }) }
    'FieldRow' { @($ui.FieldL, $ui.FieldBox) + @($(if ($ui.FieldBOn) { $ui.FieldB })) }
    'TestRow' { @($ui.TestL, $ui.ToBoxF, $ui.DraftB, $ui.OkBox) }
  } }
# Lines up every fixed row: box heights, the text box in its frame, then each row on one center line.
$ui.AlignRows = {
  <#
  .SYNOPSIS
  Aligns all fixed input and display rows (Head, TestRow, FieldRow) vertically and fits text boxes.
  .DESCRIPTION
  Syncs box container heights to compact button height, invokes BoxFit, aligns row controls by midpoint,
  and positions FieldRow label/box either stacked (FieldAbove) or inline.
  .OUTPUTS
  None.
  #>
  try {
    $bh = [int]$ui.FieldB.Height
    if ($bh -gt 0) { foreach ($p in $ui.Boxes) { if ($p.Height -ne $bh) { $p.Height = $bh } } }
  } catch { $null = $_ }   # a box is as tall as the compact button, measured
  foreach ($p in $ui.Boxes) { & $ui.BoxFit $p }   # the text box fills its frame (R24 job: a frame whose size never changed kept a 100 px text box at its top)
  & $ui.AlignRow (& $ui.RowParts 'Head') 0   # the chip and the line in capitals on one midpoint
  $mm = & $ui.Sc $ui.Z.M; & $ui.AlignRow (& $ui.RowParts 'TestRow') $mm; & $ui.AlignTick
  # L3 (the Administrator, 2026-11-19): a label above its box (a text answer). The box is on the next line, on the card's edge, 4 px under the label.
  if ($ui.FieldAbove) {
    $ui.FieldL.Margin = New-Object System.Windows.Forms.Padding($ui.FieldL.Margin.Left, $mm, 0, 0)
    $ui.FieldBox.Margin = New-Object System.Windows.Forms.Padding([int]$ui.EdgeX, (& $ui.Sc $ui.Z.G1), $mm, $mm)
  } else {
    $bx = $ui.FieldBox.Margin; $g2 = & $ui.Sc $ui.Z.G2
    if ($bx.Left -ne $g2) { $ui.FieldBox.Margin = New-Object System.Windows.Forms.Padding($g2, $bx.Top, $mm, $bx.Bottom) }
    & $ui.AlignRow (& $ui.RowParts 'FieldRow') $mm
  } }
# The question headline (the prompt's first sentence, manifest "answers") shrinks to fit one line: from the headline size
# in 0.5 pt steps to 60 % of it (never under the body size); only at that size does it wrap. Other cards keep the headline size.
$ui.SentFonts = @{}
# Every text the window puts into a wrapping label of the card: a word wider than the line is broken (M3 review). A
# label's text set elsewhere since the last break (for example a note) is taken as its new text.
$ui.Raw = @{}
# Re-breaks the long words of every card text so each line fits its width. Takes nothing; changes the label texts (the
# raw text is kept in $ui.Raw).
$ui.BreakAll = { foreach ($l in @($ui.Kick, $ui.P[0], $ui.P[1], $ui.P[2], $ui.P[3], $ui.PathT, $ui.StepName, $ui.Note, $ui.Help, $ui.Foot, $ui.Close)) {
    try { $w = [int](& $ui.GetWrap $l); if ($w -le 0 -or -not $l.Text) { continue }
      $e = $ui.Raw[$l]; $raw = $(if ($e -and [string]$l.Text -ceq [string]$e.Out) { [string]$e.Raw } else { [string]$l.Text })
      $b = & $ui.BreakLong $raw $l.Font $w; $ui.Raw[$l] = @{ Raw = $raw; Out = $b }; if ([string]$l.Text -cne $b) { $l.Text = $b } } catch { $null = $_ } }
  & $ui.CutNow }   # the now-doing line is cut again from its whole text at the new width (review of PR 121)
# Fits the headline: on an answer card the font shrinks, not below the body size, until the text fits one line; then it
# breaks long words and calls $ui.BreakAll. Takes nothing; changes $ui.Sent.
$ui.FitSent = { try {
    $f = $ui.F.Sent; $w = [int](& $ui.GetWrap $ui.Sent); $t = [string]$ui.SentRaw
    if ($ui.View -eq 'answer') { $pt = [double]$ui.F.Sent.SizeInPoints / $ui.FontK; $floor = [math]::Max($pt * 0.6, [double]$ui.F.Body.SizeInPoints / $ui.FontK)
      while ($w -gt 0 -and $pt -gt $floor -and [System.Windows.Forms.TextRenderer]::MeasureText($t, $f).Width -gt $w) {
        $pt = [math]::Max($floor, $pt - 0.5); $k = [string]$pt; if (-not $ui.SentFonts.ContainsKey($k)) { $ui.SentFonts[$k] = & $ui.Font ([string]$ui.F.Sent.Name) $pt $null }; $f = $ui.SentFonts[$k] }
    }
    if (-not [object]::ReferenceEquals($ui.Sent.Font, $f)) { $ui.Sent.Font = $f }
    $b = & $ui.BreakLong $t $f $w; if ($ui.Sent.Text -ne $b) { $ui.Sent.Text = $b } } catch { $null = $_ }
  & $ui.BreakAll }
$ui.FitRow = {
  # The box of a box row takes the width that is left beside its label and its button (at most 420). A box under its
  # label (L3) is as wide as the card's text: from the card's edge to the end of the text column.
  try { $cw = $ui.ContentW
    if ($ui.FieldAbove) { $ui.FieldBox.Width = [math]::Max((& $ui.Sc 160), ($cw - (& $ui.Sc 10))); return }
    $left = $cw - $ui.FieldL.PreferredSize.Width - (& $ui.Sc 20)
    if ($ui.FieldBOn) { $left -= ($ui.FieldB.Width + (& $ui.Sc 8)) }
    $ui.FieldBox.Width = [math]::Max((& $ui.Sc 160), [math]::Min((& $ui.Sc $ui.Z.FieldM), [int]$left)) } catch { $null = $_ } }
$ui.Apart = {
  <#
  .SYNOPSIS
  Lays out the action row buttons with Back on the left, primary isolated on the right, or stacked in a narrow window.
  .DESCRIPTION
  Orders buttons via $ui.BtnOrder, stacks vertically via $ui.StackBtns when $ui.Narrow is true, otherwise places at least
  24 px before the primary button (or wraps it onto its own row if space is insufficient).
  .OUTPUTS
  None.
  #>
  try { $mm = & $ui.Sc $ui.Z.M; $n = -1; $prev = -1; $used = 0
    for ($k = 0; $k -lt $ui.NB; $k++) {
      $ui.BtnRow.SetFlowBreak($ui.B[$k], $false); $ui.B[$k].Margin = (& $ui.Pad $mm $mm $mm $mm)
      if ($ui.BOn[$k] -and $ui.BMain[$k]) { $n = $k }   # every button: a hidden one keeps no old margin
    }
    $anyOn = @($ui.BOn | Where-Object { $_ }).Count
    $bt = $mm + $(if ($anyOn) { [int][math]::Floor(((& $ui.Sc $ui.Z.ActionH) - $ui.BackB.Height) / 2) } else { 0 })   # Back (Esc) on the midpoint of the 40 px buttons
    $ui.BackB.Margin = (& $ui.Pad $mm $bt $mm $mm); $ui.BtnRow.SetFlowBreak($ui.BackB, $false)
    & $ui.BtnOrder ([bool]$ui.Narrow) $n; if ($ui.Narrow) { & $ui.StackBtns $n; return }
    foreach ($b in @(@($ui.B) + @($ui.BackB))) { if ($ui.Wide[$b]) { $ui.Wide.Remove($b); & $ui.FitBtn $b } }
    if ($n -lt 0) { try { $ui.BtnRow.PerformLayout() } catch { $null = $_ }; return }   # no layout yet: the card's layout does it
    if ($ui.BackOn) { $prev = -2; $used += $ui.BackB.Width + 2 * $mm }   # a flag, not .Visible: the row can still be hidden from the card before
    for ($k = 0; $k -lt $n; $k++) { if ($ui.BOn[$k]) { $prev = $k; $used += $ui.B[$k].Width + 2 * $mm } }
    if ($prev -eq -1) { $used = 0 }
    $room = $(if ($ui.BtnRow.MaximumSize.Width -gt 0) { [int]$ui.BtnRow.MaximumSize.Width } else { $ui.ContentW + 2 * $mm }) - (& $ui.Sc 2)   # the width the row really wraps at, 2 px slack
    $left = $room - $used - $ui.B[$n].Width - $mm
    if ($left -lt (& $ui.Sc $ui.Z.G6)) {
      if ($prev -ge 0) { $ui.BtnRow.SetFlowBreak($ui.B[$prev], $true) }
      elseif ($prev -eq -2) { $ui.BtnRow.SetFlowBreak($ui.BackB, $true) }
      $left = $room - $ui.B[$n].Width - $mm   # too narrow: its own row
    }
    $ui.B[$n].Margin = (& $ui.Pad ([int][math]::Max($mm, $left)) $mm $mm $mm); $ui.BtnRow.PerformLayout()
    $f = $(if ($ui.BackOn) { $ui.BackB } else { @(for ($k = 0; $k -lt $n; $k++) { if ($ui.BOn[$k]) { $ui.B[$k] } })[0] })   # the row still wrapped: the primary at the right end of its own row
    if ($f -and -not [object]::ReferenceEquals($f, $ui.B[$n]) -and $ui.B[$n].Top -gt $f.Top + $f.Height) {
      $ui.B[$n].Margin = (& $ui.Pad ([int][math]::Max($mm, $room - $ui.B[$n].Width - $mm)) $mm $mm $mm)
    }
    $ui.BtnRow.PerformLayout()   # the row's height is right before the frame is placed ($ui.Squeeze)
  } catch { $null = $_ } }
# The order of the action row's buttons (D4, the Administrator, 2026-11-27): in a row Back first and the primary last; in the stack
# of a narrow window the primary first and Back last. Tab follows the order. Takes whether it is the stack and the index
# of the primary (-1: none); a host that cannot reorder keeps the row order.
$ui.BtnOrder = { param([bool]$Stack, [int]$N)
  try {
    $all = @($ui.B | ForEach-Object { $_ })
    $o = $(
      if ($Stack -and $N -ge 0) { @($ui.B[$N]) + @($all | Where-Object { -not [object]::ReferenceEquals($_, $ui.B[$N]) }) + @($ui.BackB) }
      elseif ($Stack) { $all + @($ui.BackB) }
      else { @($ui.BackB) + $all }
    )
    for ($i = 0; $i -lt $o.Count; $i++) { $ui.BtnRow.Controls.SetChildIndex($o[$i], $i); $o[$i].TabIndex = $i }
  } catch { $null = $_ } }   # the stand-ins cannot reorder: the row keeps its order
# Stacks the action row at the right edge of the card's text (D4; Cards v2): each button 240 px wide, one under the
# other, the primary on top and 16 px under it the others, 8 apart. Takes the index of the primary (-1: none).
$ui.StackBtns = { param([int]$N)
  $mm = & $ui.Sc $ui.Z.M
  foreach ($b in @(@($ui.B) + @($ui.BackB))) { $ui.Wide[$b] = $true; & $ui.FitBtn $b }
  $room = $(if ($ui.BtnRow.MaximumSize.Width -gt 0) { [int]$ui.BtnRow.MaximumSize.Width } else { $ui.ContentW + 2 * $mm }) - (& $ui.Sc 2)
  foreach ($b in @(@($ui.B) + @($ui.BackB))) {
    $x = [int][math]::Max($mm, $room - $b.Width - $mm)
    $low = $(if ($N -ge 0 -and [object]::ReferenceEquals($b, $ui.B[$N])) { (& $ui.Sc $ui.Z.G4) - $mm } else { $mm })
    $b.Margin = (& $ui.Pad $x $mm $mm $low); try { $ui.BtnRow.SetFlowBreak($b, $true) } catch { $null = $_ }   # the stand-ins have no flow breaks
  }
  try { $ui.BtnRow.PerformLayout() } catch { $null = $_ } }   # no layout yet: the card's layout does it
# Places the card frame (L1) and lets the card's text scroll when the card is taller than the window (the help below).
$ui.Squeeze = {
  <#
  .SYNOPSIS
  Places the card frame (L1) and lets the card's text scroll when the card is taller than the window, so the buttons stay in view.
  .DESCRIPTION
  The frame's top is fixed for a window size; a card too tall for the room under it moves up before it scrolls. A short
  card gets a gap above its buttons, so the frame is its minimum height.
  .OUTPUTS
  Nothing. Sets the card's top row, the size of $ui.Scroll and $ui.Gap, $ui.Scrolls and $ui.Frame (what the self-check compares).
  #>
  if (-not $ui.Scaled) { return }
  if ($ui.InSqueeze) { return }; $ui.InSqueeze = $true
  try { $bh = [int]$ui.Body.Height; $bw = [int]$ui.Body.Width; $H = [int]$ui.Card.ClientSize.Height; $hh = [int]$ui.Head.Height; $th = [int]$ui.Tail.Height
    $min = [math]::Min((& $ui.Sc $ui.Layout.FrameMin), $H); $want = [int][math]::Floor(($H - $min) * 0.4); $top = $want
    $need = $hh + $bh + $th; if ($need -gt $H - $top) { $top = [math]::Max(0, $H - $need) }   # a tall card moves up before it gets a scroll bar
    $avail = $H - $top - $hh - $th; $sh = $bh; $bar = 0
    if ($bh -gt $avail) { $sh = [math]::Max((& $ui.Sc 80), $avail); $bar = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth + (& $ui.Sc 4) }
    $ui.Scrolls = [bool]$bar; $gap = $(if ($ui.Narrow) { 0 } else { [math]::Max(0, $min - $hh - $sh - $th) })   # D4: in a narrow window the buttons stand right under the text
    $ui.Frame = @{ WantTop = $want; MinH = $(if ($ui.Narrow) { 0 } else { $min }); Moved = ($top -ne $want) }
    if ($ui.Scroll.Width -ne ($bw + $bar) -or $ui.Scroll.Height -ne $sh) { $ui.Scroll.Size = New-Object System.Drawing.Size(($bw + $bar), $sh) }
    if ($ui.Gap.Height -ne $gap) { $ui.Gap.Height = $gap }; if ($ui.Gap.Visible -ne [bool]$gap) { $ui.Gap.Visible = [bool]$gap }
    try { if ([int]$ui.CardRows[0].Height -ne $top) { $ui.CardRows[0].Height = $top } } catch { $null = $_ }   # stand-in types: no row styles
  } catch { $null = $_ } finally { $ui.InSqueeze = $false } }   # a size that cannot be read: the next fit places the frame
# Counts how many lines a text takes at a width, at least 1 and at most a limit (0 for no text). Takes the text, font,
# width, one line's height and the limit; gives back the number.
$ui.Rows = { param([string]$Text, $Font, [int]$W, [int]$LineH, [int]$Most)
  if (-not $Text) { return 0 }
  [math]::Min($Most, [math]::Max(1, [int][math]::Round((& $ui.Meas $Text $Font $W).Height / [math]::Max(1, $LineH)))) }
# Computes inline or stacked layout metrics for one choice option on Choose or Maintenance.
$ui.OptPlan = {
  <#
  .SYNOPSIS
  Computes row layout dimensions and wrapping plan for one choice option on Choose or Maintenance.
  .DESCRIPTION
  Measures title, version, right facts, summary, and notice to pick inline Maintenance or stacked Choose layout.
  .PARAMETER o
  Option hashtable.
  .PARAMETER w
  Row width in pixels.
  .OUTPUTS
  Hashtable with layout metrics.
  #>
  param($o, [int]$w)
  $pad = & $ui.Sc 16; $x = $pad + (& $ui.Sc 38); $inner = $w - $x - $pad; $gap = & $ui.Sc 12
  $h1 = [System.Windows.Forms.TextRenderer]::MeasureText('Ag', $ui.F.Body).Height; $h2 = [System.Windows.Forms.TextRenderer]::MeasureText('Ag', $ui.F.Small).Height
  $vw = $(if ($o.Ver) { [System.Windows.Forms.TextRenderer]::MeasureText([string]$o.Ver, $ui.F.Small).Width } else { 0 })
  $nw = [System.Windows.Forms.TextRenderer]::MeasureText([string]$o.Name, $ui.F.Body).Width
  $rw = 0; foreach ($r in @($o.R1, $o.R2)) { if ($r) { $rw = [math]::Max($rw, [System.Windows.Forms.TextRenderer]::MeasureText([string]$r, $ui.F.SmallB).Width) } }
  $under = [bool]($rw -and -not $o.Off -and ($nw + $vw + $gap + $rw) -gt $inner)
  $tw = $(if ($rw -and -not $under) { $inner - $rw - $gap } else { $inner })
  if ($o.Inline -and $rw) {
    foreach ($fc in @($o.Facts)) { if ($fc) { $rw = [math]::Max($rw, [System.Windows.Forms.TextRenderer]::MeasureText([string]$fc, $ui.F.SmallB).Width) } }
    $nc = $gap; foreach ($nm in @($o.Names)) { $nc = [math]::Max($nc, [System.Windows.Forms.TextRenderer]::MeasureText([string]$nm, $ui.F.Body).Width + $gap) }
    $sw = $inner - $rw - $gap - $nc; $fits = ($sw -ge (& $ui.Sc 120))
    if ($fits) { foreach ($sb in @($o.Subs)) { if ($sb -and (& $ui.Rows ([string]$sb) $ui.F.Small $sw $h2 3) -gt 2) { $fits = $false; break } } }
    if ($fits) {
      $sl = & $ui.Rows ([string]$o.Sub) $ui.F.Small $sw $h2 2; $hi = [math]::Max((& $ui.Sc 40), ([math]::Max($h1, $sl * $h2) + (& $ui.Sc 16)))
      return @{ Inline = $true; H = [int]$hi; Pad = $pad; X = $x; Tw = [int]($inner - $rw - $gap); Rw = $rw
        Under = $false; S1 = $sl; S2 = 0; NL = 0; H1 = $h1; H2 = $h2; Vw = 0; Nw = $nw; Nc = [int]$nc; Sw = [int]$sw; Y = 0 }
    }
  }
  if ($o.Inline -and $rw) { $under = $true; $tw = $inner }
  $sf = $(if ($o.Off) { $ui.F.SmallB } else { $ui.F.Small }); $s1 = & $ui.Rows ([string]$o.Sub) $sf $tw $h2 4
  if ($rw -and -not $under -and -not $o.Off -and -not $o.Inline -and ($s1 -gt 2 -or $tw -lt [int]($inner * 0.6))) {
    $under = $true; $tw = $inner; $s1 = & $ui.Rows ([string]$o.Sub) $sf $tw $h2 4
  }
  $s2 = & $ui.Rows ([string]$o.Sub2) $ui.F.Small $tw $h2 2; $nl = & $ui.Rows ([string]$o.Note) $ui.F.SmallB $tw $h2 3
  $need = $h1 + ($s1 + $s2 + $nl + [int]$under) * $h2
  $hh = [math]::Max((& $ui.Sc $(if ($o.Off -and -not ($o.Sub -or $o.Sub2 -or $o.Note)) { 40 } else { 66 })), ($need + (& $ui.Sc 20)))
  return @{ H = [int]$hh; Pad = $pad; X = $x; Tw = [int]$tw; Rw = $rw; Under = $under; S1 = $s1; S2 = $s2; NL = $nl; H1 = $h1; H2 = $h2; Vw = $vw; Nw = $nw; Y = [int](($hh - $need) / 2) } }
# Paints one choice row control using $ui.OptPlan layout metrics.
$ui.PaintOpt = {
  <#
  .SYNOPSIS
  Draws a single choice row (active button or disabled/blocked item) using $ui.OptPlan metrics.
  .DESCRIPTION
  Renders border/hairline, key badge or status icon, title, version, summary, notice, and right facts.
  .PARAMETER P
  The row Panel or Button control.
  .PARAMETER G
  The Graphics surface for painting.
  .OUTPUTS
  None.
  #>
  param($P, $G)
  try {
    $o = $P.Tag; $w = $P.ClientSize.Width; $h = $P.ClientSize.Height; $G.Clear($ui.C.White)
    $pl = & $ui.OptPlan $o $w; $pad = $pl.Pad; $x = $pl.X; $y = $pl.Y; $h1 = $pl.H1; $h2 = $pl.H2; $tw = $pl.Tw; $rw = $pl.Rw
    $one = 'Left, Top, NoPrefix, SingleLine, EndEllipsis'; $wrap = 'Left, Top, NoPrefix, WordBreak, EndEllipsis, TextBoxControl'
    if ($o.Off) {
      $pn = New-Object System.Drawing.Pen($ui.C.Hair); $G.DrawLine($pn, 0, 0, $w, 0); $pn.Dispose()
      $cp = New-Object System.Drawing.Pen($(if ($o.Soon) { $ui.C.Gray } else { $ui.C.Red }), [single](& $ui.Sc 2)); $d = & $ui.Sc 12; $cx = $pad + (& $ui.Sc 6); $cy = [int](($h - $d) / 2)
      if ($o.Soon) { $G.DrawLine($cp, $cx, ($cy + [int]($d / 2)), ($cx + $d), ($cy + [int]($d / 2))) }
      else { $G.DrawLine($cp, $cx, $cy, ($cx + $d), ($cy + $d)); $G.DrawLine($cp, ($cx + $d), $cy, $cx, ($cy + $d)) }; $cp.Dispose()
    } else {
      $foc = [bool]$P.Focused; $t = $(if ($foc) { & $ui.Sc 2 } else { 1 }); $bc = $(if ($foc) { $ui.C.Navy } elseif ($o.Danger) { $ui.C.Red } else { $ui.C.Edge })
      $pn = New-Object System.Drawing.Pen($bc, [single]$t); $i = [int]($t / 2); $G.DrawRectangle($pn, $i, $i, ($w - 1 - 2 * $i), ($h - 1 - 2 * $i)); $pn.Dispose()
      $k = & $ui.Sc 24; $ky = [int](($h - $k) / 2); $kp = New-Object System.Drawing.Pen($ui.C.Edge); $G.DrawRectangle($kp, $pad, $ky, $k, $k); $kp.Dispose()
      & $ui.Word $G ([string]$o.Key) $ui.F.SmallB $ui.C.Gray $pad $ky $k $k 'HorizontalCenter, VerticalCenter, NoPrefix, SingleLine'
    }
    $tc = $(if ($o.Off) { $ui.C.Gray } elseif ($o.Danger) { $ui.C.Red } else { $ui.C.Navy })
    $rc = $(if ($o.Soon) { $ui.C.Gray } elseif ($o.Off -or $o.Danger) { $ui.C.Red } else { $ui.C.Navy })
    if ($pl.Inline) {
      & $ui.Word $G ([string]$o.Name) $ui.F.Body $tc $x ([int](($h - $h1) / 2)) ($pl.Nc - (& $ui.Sc 4)) $h1 $one
      $sh = $pl.S1 * $h2; & $ui.Word $G ([string]$o.Sub) $ui.F.Small $ui.C.Gray ($x + $pl.Nc) ([int](($h - $sh) / 2)) $pl.Sw $sh $wrap
      & $ui.Word $G ([string]$o.R1) $ui.F.Small $rc ($w - $pad - $rw) ([int](($h - $h2) / 2)) $rw $h2 'Right, Top, NoPrefix, SingleLine'; return }
    $nw = [math]::Max((& $ui.Sc 40), [math]::Min($pl.Nw, ($tw - $pl.Vw)))
    & $ui.Word $G ([string]$o.Name) $ui.F.Body $tc $x $y $nw $h1 $one
    if ($o.Ver) { & $ui.Word $G ([string]$o.Ver) $ui.F.Small $ui.C.Gray ($x + $nw) $y ([math]::Max(1, ($tw - $nw))) $h1 $one }
    $yy = $y + $h1
    if ($o.Sub) {
      $sf = $(if ($o.Off) { $ui.F.SmallB } else { $ui.F.Small }); $sc = $(if ($o.Off -and -not $o.Soon) { $ui.C.Navy } else { $ui.C.Gray })
      & $ui.Word $G ([string]$o.Sub) $sf $sc $x $yy $tw ($pl.S1 * $h2) $wrap; $yy += $pl.S1 * $h2
    }
    if ($o.Sub2) { & $ui.Word $G ([string]$o.Sub2) $ui.F.Small $ui.C.Navy $x $yy $tw ($pl.S2 * $h2) $wrap; $yy += $pl.S2 * $h2 }
    if ($pl.Under) { $facts = (@($o.R1, $o.R2) | Where-Object { $_ }) -join $dot; & $ui.Word $G $facts $ui.F.Small $rc $x $yy $tw $h2 $one; $yy += $h2 }
    if ($o.Note) { & $ui.Word $G ([string]$o.Note) $ui.F.SmallB $ui.C.Navy $x $yy $tw ($pl.NL * $h2) $wrap }
    if ($rw -and -not $pl.Under) { $rx = $w - $pad - $rw; $rf = $(if ($o.Off) { $ui.F.SmallB } else { $ui.F.Small })
      if ($o.R1) { & $ui.Word $G ([string]$o.R1) $rf $rc $rx ($y + (& $ui.Sc 2)) $rw $h2 'Right, Top, NoPrefix, SingleLine' }
      if ($o.R2) { & $ui.Word $G ([string]$o.R2) $ui.F.Small $ui.C.Gray $rx ($y + $h1) $rw $h2 'Right, Top, NoPrefix, SingleLine' } }
  } catch { $null = $_ } }
# Fills the choice list with one button for each item (the old ones are kept to dispose after the window closes).
# Takes the list of items (name, version, notes).
$ui.FillOpts = {
  <#
  .SYNOPSIS
  Populates $ui.Opts with one Button or disabled Panel for each item in $List.
  .DESCRIPTION
  Moves prior choice controls to $ui.Trash for deferred disposal, assigns keyboard choice numbers, wires click and
  focus handlers, and sizes each control via $ui.OptPlan.
  .PARAMETER List
  Array of option hashtables to display.
  .OUTPUTS
  None.
  #>
  param($List)
  $ui.Trash = @($ui.Trash) + @($ui.Opts.Controls); $ui.Opts.Controls.Clear()   # old choices are disposed after the window has closed: a button is never disposed inside its own Click
  $n = 0
  foreach ($o in @($List | Where-Object { $_ })) {
    $said = (@($o.Name, $o.Ver, $o.Sub, $o.Sub2, $o.Note, $o.R1, $o.R2) | Where-Object { $_ }) -join '. '
    if ($o.Off) { $c = New-Object System.Windows.Forms.Panel; $c.AccessibleRole = 'StaticText'; $c.AccessibleName = $said }
    else {
      $n++; $o.Key = $n
      $c = New-Object System.Windows.Forms.Button; $c.FlatStyle = 'Flat'; $c.FlatAppearance.BorderSize = 0
      $c.UseVisualStyleBackColor = $false; $c.Text = ''; $c.AccessibleName = ('Choice ' + $n + ': ' + $said)
      $c.Add_Click({ if ($ui.OnOpt -and -not $ui.Busy -and (& $ui.Settled)) { & $ui.OnOpt ([int]$this.Tag.Index) } }); $c.Add_GotFocus({ $this.Invalidate() }); $c.Add_LostFocus({ $this.Invalidate() })
    }
    $gap = & $ui.Sc $(if ($o.Inline) { $ui.Z.G1 } else { $ui.Z.G2 })   # one-line rows (Maintenance) 4 apart: 6 rows fit (Windows job of PR 211)
    $c.Tag = $o; $c.BackColor = $ui.C.White; $c.Margin = (& $ui.Pad 0 0 0 $gap)
    $hh = & $ui.Sc $(if ($o.Note -or $o.Sub2) { 86 } else { 66 }); try { $hh = (& $ui.OptPlan $o $ui.ContentW).H } catch { $null = $_ }   # as tall as its lines, 66 at least
    $c.Size = New-Object System.Drawing.Size($ui.ContentW, $hh)
    $c.Add_Paint({ & $ui.PaintOpt $this $_.Graphics })
    [void]$ui.Opts.Controls.Add($c)
  } }
# Collects layout rule defect strings for row midpoints, box heights, frame placement, and left ink edges.
$ui.Measure = {
  <#
  .SYNOPSIS
  Collects layout rule defect strings for row midpoints, box heights, frame placement, and left ink edges.
  .DESCRIPTION
  Evaluates RowBad, AboveBad, FrameBad, TickBad, and EdgeBad on visible controls in screen pixels.
  .PARAMETER Card
  Current card view name used as a prefix in defect messages.
  .OUTPUTS
  Array of layout defect strings.
  #>
  param([string]$Card)
  $out = @()
  # Returns screen rectangle of a control.
  $sr = { param($C) $C.RectangleToScreen($C.ClientRectangle) }
  foreach ($row in 'Head', 'FieldRow', 'TestRow') {
    $ps = @(& $ui.RowParts $row); if ($ps.Count -lt 2 -or -not $ps[0].Parent.Visible) { continue }
    $items = @($ps | ForEach-Object { $rr = & $sr $_
      $k = $(if ($ui.Boxes -contains $_) { 'box' } elseif ($_ -is [System.Windows.Forms.Button] -and $_.FlatAppearance.BorderSize -gt 0) { 'button' } else { 'other' })
      @{ N = (& $ui.NameOf $_); Top = $rr.Top; H = $rr.Height; Line = $rr.Top - $_.Margin.Top; Kind = $k } })
    $out += & $ui.RowBad $Card $row $items
  }
  if ($ui.RecB.Visible -and $ui.RightL.Visible -and [string]$ui.RightL.Text) {
    $botItems = @(@($ui.RecB, $ui.RightL) | ForEach-Object { $rr = & $sr $_; @{ N = (& $ui.NameOf $_); Top = $rr.Top; H = $rr.Height; Line = 0; Kind = 'other' } })
    $out += & $ui.RowBad $Card 'Bottom' $botItems
  }
  # Returns left ink coordinate of a control in screen pixels.
  $tx = { param($C) (& $sr $C).Left + (& $ui.Ink $C) }
  if ($ui.FieldRow.Visible -and $ui.FieldAbove -and -not $ui.RecOn) { $rl = & $sr $ui.FieldL; $rb = & $sr $ui.FieldBox
    $out += & $ui.AboveBad $Card @{ LabelBottom = $rl.Bottom; BoxTop = $rb.Top; BoxLeft = $rb.Left; BoxW = $rb.Width; Edge = (& $tx $ui.FieldL); TextW = ($ui.ContentW - (& $ui.Sc 10)) } }
  if ($ui.Frame -and -not $ui.RecOn) { $rh = & $sr $ui.Head; $rt = & $sr $ui.Tail; $rc = & $sr $ui.Card
    $out += & $ui.FrameBad $Card @{ Top = $rh.Top - $rc.Top; WantTop = $ui.Frame.WantTop; H = $rt.Bottom - $rh.Top; MinH = $ui.Frame.MinH; Moved = $ui.Frame.Moved } }
  if ($ui.StepRow.Visible -and -not $ui.RecOn) { $rb = & $sr $ui.StepBar
    foreach ($l in @($ui.StepTime, $ui.StepFrac)) { $rl = & $sr $l
      if (($rl.Top - $l.Margin.Top) -eq ($rb.Top - $ui.StepBar.Margin.Top) -and $rl.Left -gt $rb.Left) {
        $out += & $ui.TickBad $Card @{ Top = $rb.Top; H = $rb.Height } @{ N = (& $ui.NameOf $l); Top = $rl.Top; H = $rl.Height } } } }
  if (-not $ui.RecOn) {
    $es = @()
    if ($ui.Chip.Visible) { $es += @{ N = 'Chip'; X = (& $sr $ui.Chip).Left } }
    elseif ($ui.Kick.Visible -and $ui.Kick.Text) { $es += @{ N = 'Kick'; X = (& $tx $ui.Kick) } }
    if ($ui.TickP.Visible) { $es += @{ N = 'TickP'; X = (& $tx $ui.TickP) } } elseif ($ui.Sent.Visible -and $ui.Sent.Text) { $es += @{ N = 'Sent'; X = (& $tx $ui.Sent) } }
    foreach ($l in @(@($ui.P) + @($ui.PathL, $ui.PathT, $ui.Close, $ui.PctL, $ui.FieldL, $ui.Note, $ui.Help, $ui.Foot, $ui.TestL))) {
      if ($l.Visible -and $l.Text -and $l.Parent.Visible) { $es += @{ N = (& $ui.NameOf $l); X = (& $tx $l) } } }
    foreach ($b in @($ui.RunBar, $ui.RunA, $ui.RunRow, $ui.RunB, $ui.Todo)) { if ($b.Visible) { $es += @{ N = (& $ui.NameOf $b); X = (& $sr $b).Left } } }
    if ($ui.Guide.Visible) { $es += @{ N = 'Guide'; X = (& $sr $ui.Guide).Left + (& $ui.GuideInk) } }
    if ($ui.ErrBox.Visible) { $es += @{ N = 'ErrBox'; X = (& $sr $ui.ErrBox).Left } }
    $k1 = @($ui.LinkRow.Controls | Where-Object { $_.Visible })[0]
    if ($k1) { $d = 'link ink ' + (& $ui.Ink $k1) + ', width ' + $k1.Width + ', margin ' + $k1.Margin.Left + ', row margin ' + $ui.LinkRow.Margin.Left
      $es += @{ N = (& $ui.NameOf $k1); X = (& $tx $k1); D = $d } }
    $o1 = @($ui.Opts.Controls | Where-Object { $_.Visible })[0]; if ($o1) { $es += @{ N = 'choice 1'; X = (& $sr $o1).Left } }
    $b1 = @(@($ui.BackB) + @($ui.B | Where-Object { [string]$ui.Kinds[$_] -ne 'primary' }) | Where-Object { $_.Visible })[0]
    if ($b1 -and -not $ui.Narrow) { $es += @{ N = (& $ui.NameOf $b1); X = (& $tx $b1) } }
    $out += & $ui.EdgeBad $Card $es
  }
  return $out }
$ui.Scale = {
  <#
  .SYNOPSIS
  Formats a single-line diagnostic string with current DPI, scaling, screen, and window dimensions.
  .DESCRIPTION
  Reads DeviceDpi, CurrentAutoScaleDimensions, DpiHelper awareness, screen bounds, and form size without
  exposing PII or compiling native code.
  .OUTPUTS
  SCALE diagnostic string.
  #>
  # The scaling facts, numbers only (R24: the screen dpi said 100 % while every size was 1.5 x). DeviceDpi exists from .NET 4.7.
  try { $f = $ui.Form; $dd = 'n/a'; try { $pp = $f.GetType().GetProperty('DeviceDpi'); if ($pp) { $dd = [string]$pp.GetValue($f, $null) } } catch { $null = $_ }
    $as = $f.CurrentAutoScaleDimensions; $sn = [System.Windows.Forms.Screen]::FromControl($f)
    # The process dpi awareness, read from Windows Forms itself (its internal DpiHelper, .NET 4.7+); no native call: that
    # would need C# compiled on the work computer. PerMonitorV2 with dpiX 96 and autoScale 144 is the R24 case.
    $aw = 'n/a'
    try {
      $dh = $f.GetType().Assembly.GetType('System.Windows.Forms.DpiHelper')
      if ($dh) {
        $bf = [System.Reflection.BindingFlags]'NonPublic, Public, Static'; $pm = $dh.GetProperty('IsPerMonitorV2Awareness', $bf)
        if ($pm) { $aw = $(if ([bool]$pm.GetValue($null, $null)) { 'PerMonitorV2' } else { 'not-PerMonitorV2' }) }
      }
    } catch { $null = $_ }
    $sd = $f.AutoScaleDimensions; $rd = 'n/a'
    $lg = $(if ($ui.Logo) { [string]$ui.Logo.Width + 'x' + $ui.Logo.Height } else { 'n/a' })
    $b1 = @($ui.B | Where-Object { $_.Visible })[0]; $bt = $(if ($b1) { [string]$b1.Width + 'x' + $b1.Height } else { 'n/a' })
    $shownAt = $(if ($ui.ShownAt) { $ui.ShownAt } else { 'n/a' })
    $lastClose = $(if ($ui.LastClose) { $ui.LastClose } else { 'n/a' })
    $l = ('SCALE dpiX=' + [int]$ui.ScreenDpi + ' deviceDpi=' + $dd + ' mode=' + [string]$f.AutoScaleMode +
      ' asd=' + [int]$sd.Width + 'x' + [int]$sd.Height + ' autoScale=' + [int]$as.Width + 'x' + [int]$as.Height +
      ' font=' + [int]$f.Font.Height + ' fontPt=' + $f.Font.SizeInPoints + ' fontScale=' + $ui.FontK +
      ' ctlScale=' + [math]::Round($ui.Dpi / 96.0, 2) + ' realDpi=' + $rd + ' aware=' + $aw +
      ' screen=' + $sn.Bounds.Width + 'x' + $sn.Bounds.Height +
      ' work=' + $sn.WorkingArea.Width + 'x' + $sn.WorkingArea.Height +
      ' client=' + $f.ClientSize.Width + 'x' + $f.ClientSize.Height + ' state=' + [string]$f.WindowState +
      ' logo=' + $lg + ' btn=' + $bt + ' shown=' + $shownAt + ' placed=' + $ui.Placed + ' lastClose=' + $lastClose)
    $sy = 'n/a'
    return ($l + ' thread=' + $script:dpiThread + ' sysDpi=' + $sy)
  } catch { return ('SCALE could not be read: ' + (ConvertTo-Masked ([string]$_.Exception.Message))) } }
$ui.ScaleKeep = 20   # the SCALE lines rade-window-scale.txt keeps (E4)
# E4 (R42 plan; the Administrator, 2026-11-21): each RADE window writes its SCALE line, with the time, its own host name and
# its own process name (no other process is read), to RADE\Config\rade-window-scale.txt when it is shown, so a round's
# results hold the line of every RADE window, also one opened from the RADE shortcut in another process. The file keeps
# the last $ui.ScaleKeep lines. Numbers and names of programs only: no path, user or site. A failure is ignored. Takes nothing.
$ui.LogScale = {
  try { $p = Get-RadeConfigFile 'rade-window-scale.txt'; $d = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { [void](New-Item -ItemType Directory -Path $d -Force) }
    $exe = 'n/a'; try { $exe = [System.Diagnostics.Process]::GetCurrentProcess().ProcessName } catch { $null = $_ }   # no name: the line says n/a
    # engine-v46: the start (child, shortcut) and the taskbar identity of this window
    $line = ((Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') + ' host=' + ([string]$Host.Name -replace '\s', '') +
      ' exe=' + $exe + ' rade=' + [string]$env:RADE_HOST + ' taskbar=' + [string]$script:taskbarId + ' build=' + $buildId + ' ' + (& $ui.Scale))
    $old = @(); if (Test-Path -LiteralPath $p -PathType Leaf) { $old = @(Get-Content -LiteralPath $p | Where-Object { $_ }) }
    Write-FileWhole $p ((@(@($old) + @($line)) | Select-Object -Last $ui.ScaleKeep) -join "`r`n") } catch { $null = $_ } }   # not written: the round has no line of this window
# The SCALE lines of the RADE windows shown since this window opened ($ui.OpenedAt), this one included, for the round's
# results (E4). Takes nothing; gives back the lines (none when the file cannot be read).
$ui.ScaleLines = {
  try { $p = Get-RadeConfigFile 'rade-window-scale.txt'; if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return @() }
    $since = $ui.OpenedAt.ToString('yyyy-MM-ddTHH:mm:ss')
    $rows = @(Get-Content -LiteralPath $p | Where-Object { $_ -match '^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d) ' -and [string]::CompareOrdinal($Matches[1], $since) -ge 0 })
    return @($rows | ForEach-Object { 'WINDOW ' + $_ }) } catch { return @() } }
# Gives the result of the layout self-check: its pass line, or the defects found, with the window size and scale. Takes
# nothing; gives back the text.
$ui.LayLine = {
  & $ui.Check
  $pct = [int][math]::Round($ui.Dpi / 96.0 * 100); $sp = [int][math]::Round($ui.ScreenDpi / 96.0 * 100)   # the form's scale (the one source); the screen dpi beside it when it differs
  $size = ([string]$ui.Form.ClientSize.Width + ' x ' + $ui.Form.ClientSize.Height + ' at ' + [string]$pct + ' %' +
    $(if ($sp -ne $pct) { ' (the form auto-scale; the screen dpi says ' + $sp + ' %)' } else { '' }))
  $sc = $(if ($ui.LayScroll.Count) { '; the text scrolls on: ' + ((@($ui.LayScroll.Keys) | Sort-Object) -join ', ') } else { '' })
  if ($ui.LayBad.Count) {
    return ('Layout self-check: ' + $ui.LayBad.Count + ' defects in ' + $ui.LayCards.Count + ' cards (' + $size + ')' + $sc + "`r`n" + (& $ui.Scale) + "`r`n" + (@($ui.LayBad) -join "`r`n"))
  }
  return ('Layout self-check: PASS layout, ' + $ui.LayCards.Count + ' cards (' + $size + ')' + $sc + "`r`n" + (& $ui.Scale)) }
# Sets a label's text and shows it only when the text is not empty. Takes the label and the text; gives back nothing.
$ui.Show = { param($C, [string]$Text) $C.Text = $Text; $C.Visible = [bool]$Text }
# A script whose hash does not match its own hash line (the Administrator, 2026-11-19; docs/specs/bundle-hash.md R3): on the
# boot, choose and ready cards the last line says so in dark red, in place of the card's own last line, with the full
# "Script check:" line under it (E1, R42 plan, the Administrator, 2026-11-21: the values to compare, before Run). The Ready card
# (the card with Run) always shows the full "Script check:" line under its own last line: checked, does not match, or not
# available. A match and a hash that cannot be read show nothing on the boot and choose cards. Takes the card; changes the
# color and text of $ui.Foot.
$ui.ScriptWarn = { param($c)
  $bad = [bool]($script:scriptCheck.Short -and -not $script:scriptCheck.Ok); $line = [string]$script:scriptCheck.Line
  if ($bad -and [string]$c.View -in 'boot', 'choose', 'ready') {
    & $ui.Show $ui.Foot ('This script does not match its hash. Do not run it.' + $(if ($line) { "`r`n" + $line } else { '' })); $ui.Foot.ForeColor = $ui.C.Red
    if ([string]$c.View -eq 'ready') { foreach ($b in $ui.B) { if ($b.Visible -and [string]$b.Tag.Kind -eq 'primary') { $b.Enabled = $false } } }
  }
  else { $ui.Foot.ForeColor = $ui.C.Gray
    if ([string]$c.View -eq 'ready' -and $line) { & $ui.Show $ui.Foot (@(@([string]$c.Foot, $line) | Where-Object { $_ }) -join "`r`n") } } }
# Sets what each card text box with changing values can show on the card that comes ($ui.Range): the card's Range names
# them (Kick, P0, StepName: lists of texts); a part the card does not name has no range. Takes the card's Range (or $null).
$ui.SetRange = { param($R) foreach ($k in 'Kick', 'P0', 'StepName') { $box = $(if ($k -eq 'P0') { $ui.P[0] } else { $ui[$k] })
    $v = $(if ($R -and $R[$k]) { @($R[$k] | ForEach-Object { [string]$_ }) } else { $null }); if ($v) { $ui.Range[$box] = $v } else { $ui.Range.Remove($box) }; & $ui.Reflow $box } }
$ui.SetCard = {
  <#
  .SYNOPSIS
  Configures and displays one card view on the main form.
  .DESCRIPTION
  Updates light, stage, kicker, headline, paragraphs, options, guide steps, path/field/error boxes, links,
  notes, buttons, focus target, and layout alignment.
  .PARAMETER c
  Card definition hashtable describing the view and controls to display.
  .OUTPUTS
  None.
  #>
  param($c)
  & $ui.Check
  $ui.Hot = $null; $ui.Down = $null
  if ($ui.RecOn -and ($c.Light -or $c.View -eq 'done')) { $ui.RecOn = $false; $ui.Rec.Visible = $false; $ui.Card.Visible = $true; $ui.RecB.Visible = $true }
  $ui.View = [string]$c.View; $ui.Card.SuspendLayout(); & $ui.Dress $c; & $ui.SetRange $c.Range
  $ui.Kick.Text = ([string]$c.Kicker).ToUpperInvariant(); $ui.SentRaw = [string]$c.Sentence; $ui.Sent.Text = $ui.SentRaw; $ui.TickP.Visible = [bool]$c.Tick
  $ps = @($c.P | Where-Object { $_ }); for ($k = 0; $k -lt 4; $k++) { & $ui.Show $ui.P[$k] $(if ($k -lt $ps.Count) { [string]$ps[$k] } else { '' }) }
  $ui.OnOpt = $c.OnOption; & $ui.FillOpts $c.Options; $ui.Opts.Visible = [bool]$ui.Opts.Controls.Count
  & $ui.SetSteps $c.Lines; $ui.PathL.Visible = [bool]$c.Path; & $ui.Show $ui.PathT ([string]$c.Path)
  $ui.NowRaw = ''; $ui.Now.Text = ''; if ($c.StepRow) { $ui.StepTime.Text = '' }
  $ui.FieldRow.Visible = [bool]$c.Field; $ui.FieldDo = $null
  $ui.FieldAbove = [bool]($c.Field -and $c.Field.Above); try { $ui.FieldRow.SetFlowBreak($ui.FieldL, $ui.FieldAbove) } catch { $null = $_ }   # L3: the box goes under its label
  if ($c.Field) {
    $ui.FieldL.Text = [string]$c.Field.Label; $ui.Field.Text = [string]$c.Field.Text; $ui.Field.AccessibleName = [string]$c.Field.Name
    $ui.FieldB.Visible = [bool]$c.Field.Button; $ui.FieldBOn = [bool]$c.Field.Button; $ui.FieldB.Text = [string]$c.Field.Button
    $ui.FieldDo = $c.Field.Act; $ui.Field.MaxLength = $(if ($c.Field.Max) { [int]$c.Field.Max } else { 32767 }); & $ui.FitRow
  }
  $ui.ErrRow.Visible = [bool]$c.Err; if ($c.Err) { $ui.ErrBox.Text = '' }
  $ui.LinkRow.Visible = [bool]($c.Links -or $c.PageLink); $ui.CopyPathB.Visible = [bool]$c.Links; $ui.ShowFileB.Visible = [bool]$c.Links; $ui.PageB.Visible = [bool]$c.PageLink
  & $ui.Show $ui.Note ([string]$c.Note); & $ui.Show $ui.Help ([string]$c.Help); & $ui.Show $ui.Foot ([string]$c.Foot); & $ui.Show $ui.Close ([string]$c.Close)
  & $ui.ScriptWarn $c
  $bm = & $ui.Sc $(if ($c.Close) { $ui.Z.G2 - $ui.Z.M } else { $ui.Z.G4 - $ui.Z.M })
  $bn = $ui.BtnRow.Margin; if ($bn.Top -ne $bm) { $ui.BtnRow.Margin = New-Object System.Windows.Forms.Padding($bn.Left, $bm, $bn.Right, $bn.Bottom) }
  & $ui.SetButtons $c; $ui.TestRow.Visible = [bool]$c.Test
  $ui.CardNow = $c; $ui.TourB.Visible = ($ui.HelpViews -contains [string]$c.View -and -not $ui.RecOn)
  $ui.FeedB.Visible = [bool]((& $ui.NoteOn) -and -not $ui.RecOn -and [string]$c.View -notin $ui.NoNoteViews)
  $ui.RightL.Text = $(if ($c.Right) { [string]$c.Right } else { '' })
  & $ui.FitSent; & $ui.FitEdges; & $ui.FitBar; & $ui.AlignRows; $ui.Card.ResumeLayout()
  try { $ui.Card.PerformLayout() } catch { $null = $_ }
  if ($ui.Guide.Visible) { try { $ui.Guide.Refresh() } catch { $null = $_ }; & $ui.GuideFit; & $ui.FitEdges }   # the rich text box finishes its layout when it paints
  try { $ui.Scroll.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) } catch { $null = $_ }; & $ui.Squeeze   # a new card starts at its top
  $f = $(if ($c.Focus -eq 'field') { $ui.Field } elseif ($c.Focus -eq 'fieldbutton') { $ui.FieldB } elseif ($c.Focus -eq 'err') { $ui.ErrBox }
    elseif ($c.Focus -eq 'text') { $(if ($ui.Guide.Visible) { $ui.Guide } else { $ui.Sent }) }
    elseif ($c.Focus -eq 'button' -and $ui.Accept) { $ui.Accept }
    elseif ($c.Focus -eq 'main') { $(if ($ui.Accept) { $ui.Accept } elseif ($ui.Guide.Visible) { $ui.Guide } else { $ui.Sent }) }
    elseif ($ui.Opts.Controls.Count) { @($ui.Opts.Controls | Where-Object { -not $_.Tag.Off })[0] } else { $null })
  if (-not $f) { $f = $ui.Accept }; if (-not $f) { $f = $ui.First }; if (-not $f) { $f = $ui.RecB }
  if (-not $ui.RecOn) { try { [void]$f.Focus() } catch { $null = $_ } }
  if ([object]::ReferenceEquals($f, $ui.Guide) -or [object]::ReferenceEquals($f, $ui.Sent)) {
    try { $ui.Scroll.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) } catch { $null = $_ }   # no scroll position yet: the card is at its top
  }
  $ui.CardAt = $ui.Clock.Elapsed.TotalMilliseconds; [System.Windows.Forms.Application]::DoEvents() }
# Brings the window to the front (restores it when minimized) without keeping it on top.
$ui.ToFront = {
  try {
    if ([string]$ui.Form.WindowState -eq 'Minimized') { $ui.Form.WindowState = 'Normal' }
    $ui.Form.TopMost = $true; $ui.Form.Activate(); $ui.Form.TopMost = $false
  } catch { $null = $_ } }
# Shows one gray line under the card's box or buttons, or hides it for empty text. Takes the text.
$ui.Say1 = { param([string]$Text) $ui.Note.Text = $Text; $ui.Note.Visible = [bool]$Text }   # one gray line under the card's box or buttons

# RADE window part 06, the opening views: boot, Choose (pick an application), the site address card, and the
# check cards (needs you, failed). Uses the card of 03-card.ps1 and the engine checks.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# ---- When the window opens: the Local checks of every application in the paste run once (base checks before Choose).
# An application with a FAILED one cannot be chosen. A newer version on the RADE page is read here too (test and deploy).
$ui.RunBase = {
  <#
  .SYNOPSIS
  Runs local automatic checks for all bundled apps and checks for newer versions on startup.
  .DESCRIPTION
  Collects unique local automatic check IDs across $apps, evaluates each using cache or Invoke-Check,
  records results in $ui.BaseRes, and probes Get-NewerVersion and Get-NewerRound.
  .OUTPUTS
  None.
  #>
  $ui.BaseIds = @()
  foreach ($a in $apps) {
    foreach ($id in @($a.Checks)) {
      $d = Get-CheckDef $id
      if ($d -and $d.Group -eq 'Local' -and $d.Kind -eq 'auto' -and $ui.BaseIds -notcontains $id) { $ui.BaseIds += $id }
    }
  }
  $cache = Read-CheckCache; $bp = Get-BasePath; $site = Get-SiteUrl $bp; $i = 0; $ui.Busy = $true; $ui.BaseRes = @{}
  try {
    foreach ($id in $ui.BaseIds) {
      if ($ui.Form.IsDisposed -or $script:closing) { return }
      $i++; $d = Get-CheckDef $id; $ui.RightL.Text = 'Check ' + $i + ' of ' + $ui.BaseIds.Count
      $r = Get-CheckToRun $d $cache $bp $site $false
      if (-not $r) { $r = Invoke-Check $d $bp $site { [System.Windows.Forms.Application]::DoEvents() } }
      $ui.BaseRes[$id] = $r; & $ui.RecRefresh   # an open Record shows the new result
    }
    # One read per application (4 s at most each); after one slow read the others are not tried.
    $slow = $false
    for ($j = 0; $j -lt $apps.Count; $j++) {
      if ($slow -or $ui.Newer.ContainsKey($j)) { continue }
      $t0 = Get-Date; $script:app = $apps[$j]; $ui.Newer[$j] = [string](Get-NewerVersion); if (((Get-Date) - $t0).TotalSeconds -gt 3) { $slow = $true }
    }
    if (-not $ui.ContainsKey('NewRound')) { $ui.NewRound = [string](Get-NewerRound) }
  } finally { $ui.Busy = $false; Select-App 0 } }
$ui.VNoApps = {
  # R28: a paste that lists no application (a manifest or build fault): say so, with what to do, instead of an empty list.
  $p2 = 'What to do: close this window and copy the paste again from the RADE page. If it is still empty, ask in the Teams channel.'
  & $ui.SetCard @{ View = 'noapps'; Light = 'bad'; Kicker = 'Nothing to choose'; Sentence = 'No application is listed in this paste.'
    P = @('This paste has nothing that RADE can install or run.', $p2); Help = (Get-HelpLine)
    Buttons = @(@{ Text = 'Close'; Kind = 'primary'; Act = { $ui.Form.Close() } }) } }
$ui.VBootErr = { param([string]$Why)
  # R28: the checks that run when the window opens stopped with an error: a card, not a blank window.
  & $ui.SetCard @{ View = 'booterr'; Light = 'bad'; Kicker = 'Stopped'; Sentence = 'RADE could not check this computer.'
    P = @($Why, 'Nothing was changed.', 'What to do: select "Try again". If it stops again, ask in the Teams channel.'); Help = (Get-HelpLine)
    Buttons = @(@{ Text = 'Try again'; Kind = 'primary'; Act = { & $ui.Boot } }, @{ Text = 'Close'; Act = { $ui.Form.Close() } }) }
  & $ui.ToFront }
# engine-v47 (the Administrator, 2026-11-26): for an app with application.productName every choice is a version of one product, so a
# choice reads "<word> <version>" ("Kanon 0.1.0") or, for a round, "<word> <round>" ("Kanon R46"), and the headline asks for
# the version. Without a productName: the choice's name and its version, as before. Takes the choice; gives @{ Name; Ver }.
$ui.ChoiceName = { param($A)
  if (-not [string]$appProduct) { return @{ Name = [string]$A.Name; Ver = $(if ($A.Version) { ' ' + $A.Version } else { '' }) } }
  $n = [string]$A.Name
  $hasVer = [string]$A.Version
  $hasPre = ([string]$appName -and $n.StartsWith([string]$appName + ' '))
  $tail = $(if ($hasVer) { $hasVer } elseif ($hasPre) { $n.Substring(([string]$appName).Length + 1) } else { [string]$round })
  return @{ Name = ([string]$appProduct + ' ' + $tail); Ver = '' } }   # "90-161.Z R46" gives "Kanon R46"; another name gives the round
# The Choose headline. Takes whether a choice installs (deploy); gives the sentence.
$ui.ChooseSentence = { param([bool]$Dep)
  $verb = $(if ($Dep) { 'install' } else { 'run' })
  if ([string]$appProduct) { return ('What version of ' + [string]$appProduct + ' do you want to ' + $verb + '?') }
  return ('Which application do you want to ' + $verb + '?') }
# Shows the Choose card: one option for each application, off when one of its checks failed. Takes nothing; selects the
# first application and sets the card.
$ui.VChoose = {
  <#
  .SYNOPSIS
  Shows the Choose card listing every bundled application or version with its status and summary.
  .DESCRIPTION
  Resets selection state, marks options whose local checks failed as disabled with guidance, shows newer version or
  round notices, and configures the Choose card.
  .OUTPUTS
  None.
  #>
  if (@($apps).Count -eq 0) { & $ui.VNoApps; return }
  Select-App 0; $ui.Picked = $false; $ui.Plan = $null; $ui.StartAfter = $false; & $ui.SetBand $false
  $ui.Form.Text = & $ui.TitleText $null; $list = @(); $dep = $false; $ui.Blocked = @{}; $ui.BlockedFix = @{}
  for ($j = 0; $j -lt $apps.Count; $j++) {
    foreach ($id in @($apps[$j].Checks)) {
      $r = $ui.BaseRes[$id]
      if ($r -and $r.State -eq 'FAILED') {
        $ui.Blocked[$j] = ((Get-CheckDef $id).Name + ': ' + $r.Detail)
        $ui.BlockedFix[$j] = $(if ($r.Fix) { 'What to do: ' + $r.Fix } else { '' })
        break
      }
    }
  }
  for ($j = 0; $j -lt $apps.Count; $j++) {
    $a = $apps[$j]; if ([string]$a.Mode -eq 'deploy') { $dep = $true }
    if ($ui.Blocked.ContainsKey($j)) {
      $nv = & $ui.ChoiceName $a
      $list += @{ Off = $true; Index = $j; Name = $nv.Name; Ver = $nv.Ver; Sub = [string]$ui.Blocked[$j]; Sub2 = [string]$ui.BlockedFix[$j]; R1 = 'FAILED' }
      continue
    }
    $f = Get-AppFact $a $ui.Hist; $nv = & $ui.ChoiceName $a
    $list += @{ Index = $j; Name = $nv.Name; Ver = $nv.Ver; Sub = [string]$a.Summary; R1 = $f.Steps; R2 = $f.Installed
      Note = $(if ($ui.Newer[$j]) { 'Version ' + $ui.Newer[$j] + ' is on the RADE page. This paste installs ' + $a.Version + '.' } else { '' }) }
  }
  $nr = [string]$ui.NewRound
  # no "Remove RADE" (engine-v48; the Administrator, 2026-11-26): the last app's Uninstall clears RADE's shared folder
  $btns = @($(if ($ui.Blocked.Count) { @{ Text = 'Check this computer again'; Kind = 'primary'; Act = { & $ui.Boot } } } else { $null }))
  $nrText = $(if ($nr) { 'A newer round, ' + $nr + ', is in the repository. Close this window and run ' + $nr + ' instead.' } else { '' })
  & $ui.SetCard @{ View = 'choose'; Sentence = (& $ui.ChooseSentence $dep)
    P = @($nrText); Options = $list; OnOption = { param($j) & $ui.Pick $j }
    PageLink = [bool](@($ui.Newer.Values | Where-Object { $_ }).Count)
    Buttons = $btns
    Foot = $(if ($dep) { '' } else { Get-LastRoundText $ui.Hist }) } }
# Shows "Checking this computer", runs the base checks and then shows Choose; shows the error card when they stop. Takes
# nothing.
$ui.Boot = {
  & $ui.SetBand $false   # the band from the first card: RADE's (or the app's, for an app with productName and a logo)
  & $ui.SetCard @{ View = 'boot'; Sentence = 'Checking this computer.'; P = @('This takes a few seconds. Nothing is changed.') }
  try { & $ui.RunBase } catch { if (-not ($ui.Form.IsDisposed -or $script:closing)) { & $ui.VBootErr (ConvertTo-Masked ([string]$_.Exception.Message)) }; return }
  if ($ui.Form.IsDisposed -or $script:closing) { return }
  if (Test-TourSeen) { & $ui.VChoose } else { $ui.TourFrom = $null; & $ui.VTour 0 } }   # L6: the tour comes one time, before the first Choose
# L6 (the Administrator, 2026-11-19): the RADE tour, 5 cards: what RADE does, your turn and RADE's turn, what Done,
# It failed and Skip mean, where the results go, and the Record. Shown one time for a Windows profile, before the first
# Choose (RADE\Config\rade-tour.txt), and again from "Help (F1)". S = the headline of a card, P = its paragraphs.
$ui.TourCards = @(
  @{ S = 'RADE installs and tests applications on this computer.'
     P = @('You choose an application. RADE checks this computer, then does the work as a list of steps.', 'A test of an application is called a round.') },
  @{ S = 'RADE does most steps. Some steps are yours.'
     P = @('When RADE does a step, the card shows its progress. Keep the window open.', 'A yellow line at the top: RADE waits for you. The card says what to do.') },
  @{ S = 'A step that you do has up to three answers.'
     P = @('"Done": you did the step and it worked.', '"It failed": the step did not work. RADE then asks what the error said.',
       '"Skip": you did not do the step. A card shows only the answers that fit its step.') },
  @{ S = 'The results stay on this computer.'
     P = @('RADE writes a report into its results folder. RADE sends nothing.',
       'After a test round RADE makes an e-mail draft with the results. You read it, and you send it.') },
  @{ S = 'Details shows everything.'; P = @('Select "Details" or press F2 to see all checks, steps, files and the log.', 'Select "Help" or press F1 to see this tour again.') })
# The cards that "Help (F1)" can leave and show again: no step or check runs on them, and none waits inside the engine.
$ui.HelpViews = @(
  'choose', 'maint', 'notinst', 'stepfail', 'toolres', 'restmark', 'restpick', 'restconfirm',
  'site', 'fail', 'need', 'ready', 'nodrive', 'done', 'review', 'stopped', 'noapps', 'booterr')
# Shows card $I of the tour (0 = the first). "Next" and "Back" move; "Skip the tour" and the last card's button end it.
# Takes the card number.
$ui.VTour = { param([int]$I)
  $n = $ui.TourCards.Count; $ui.TourI = [math]::Max(0, [math]::Min($n - 1, $I)); $tc = $ui.TourCards[$ui.TourI]; $last = ($ui.TourI -eq $n - 1)
  # Advances to the next tour card or closes the tour on the final card.
  $nextAct = { if ($ui.TourI -ge $ui.TourCards.Count - 1) { & $ui.EndTour } else { & $ui.VTour ($ui.TourI + 1) } }
  & $ui.SetCard @{ View = 'tour'; Kicker = ('RADE tour' + $dot + ($ui.TourI + 1) + ' of ' + $n); Sentence = [string]$tc.S; P = @($tc.P)
    Buttons = @(@{ Text = $(if ($last) { 'Close the tour' } else { 'Next' }); Kind = 'primary'; Act = $nextAct },
      $(if ($last) { $null } else { @{ Text = 'Skip the tour'; Act = { & $ui.EndTour } } }))
    Back = $(if ($ui.TourI) { { & $ui.VTour ($ui.TourI - 1) } } else { $null }) } }   # B6: the one Back pattern
# Ends the tour: remembers that it was shown (Save-TourSeen) and shows the card it came from (Choose on the first run).
# Takes nothing.
$ui.EndTour = { Save-TourSeen; $from = $ui.TourFrom; $ui.TourFrom = $null; if ($from) { & $ui.SetCard $from } else { & $ui.VChoose } }
# "Help (F1)": opens the tour from a card of $ui.HelpViews while nothing runs; the tour's end shows that card again
# (a box on it has its first text again). Takes nothing.
$ui.OpenTour = {
  if ($ui.Busy -or $ui.Running -or $ui.RecOn -or $ui.HelpViews -notcontains [string]$ui.View) { return }
  $ui.TourFrom = $ui.CardNow; & $ui.VTour 0 }
$ui.TourB.Add_Click({ & $ui.OpenTour })
# Resets what the user chose: each step to its default, clean-up on, no step states. Takes nothing.
$ui.InitSel = { $ui.Sel = @{}; foreach ($k in $script:appSteps) { $ui.Sel[[int]$k] = [bool](Get-StepDefault $k) }; $ui.Clean = $true; $ui.StepState = @{} }
# Takes the application the user chose: selects it, reuses base check results that can be reused, and shows Maintenance
# (already installed) or the checks. Takes the application number.
$ui.Pick = {
  <#
  .SYNOPSIS
  Selects the chosen bundled application and opens Maintenance, NotInstalled, or Checks view.
  .DESCRIPTION
  Reuses non-volatile base check results, updates window band and title, resets step selection, and dispatches
  by deployment state.
  .PARAMETER J
  Zero-based application index in $apps.
  .OUTPUTS
  None.
  #>
  param([int]$J)
  Select-App $J; $ui.Picked = $true
  # The base checks are not run twice, except the ones whose answer can change at any time ($checkNoSave: Word open, disk, write).
  foreach ($id in $script:appChecks) {
    if ($ui.BaseRes.ContainsKey($id) -and $checkNoSave -notcontains $id -and $ui.BaseRes[$id].State -in 'PASSED', 'WARNING') { $script:checkResults[$id] = $ui.BaseRes[$id] }
  }
  & $ui.SetBand $true   # the band: the app's logo, its word in capitals ("KANON"), "in RADE", its subtitle, version and round
  $ui.Form.Text = & $ui.TitleText $script:app   # engine-v47: "Kanon - 0.1.0" or "Kanon - R46"
  & $ui.InitSel
  $e = $null; if (Test-Deploy) { $e = (Read-Installed (Get-InstalledKey $script:app)) }
  if ($e -and $e.installed) { & $ui.VMaint $e.installed } elseif (Test-Deploy) { & $ui.VNotInst } else { & $ui.Checks $false } }
# The Maintenance card of an app that is not installed (plan engine-v48 D8, the Administrator, 2026-11-27; Cards v2): one Install
# button; the other options come only after an install. Install runs the checks, then the Ready card. Takes nothing.
$ui.VNotInst = { $w = Get-AppWord; $v = [string]$script:app.Version
  & $ui.SetCard @{ View = 'notinst'; Kicker = ($w + ' ' + $v); Sentence = ($w + ' is not installed.')
    P = @(('Install puts ' + $w + ' on this computer' + $(if (& $ui.NeedSite) { ' and on your site' } else { '' }) + '. RADE runs the checks first.'))
    Note = 'Repair, Diagnose, Back up, Restore and Uninstall are available after the install.'
    Buttons = @(@{ Text = ('Install ' + $v); Kind = 'primary'; Act = { & $ui.Checks $false } }); Back = { & $ui.VChoose } } }
# The name of the row that installs this paste's version (D1): "Install <v>" when nothing is installed, "Update to <v>"
# when an older version is, "Repair" when this one is. Takes the install record's installed part (or $null); gives the name.
$ui.RowVerb = { param($Inst) $v = [string]$script:app.Version; if (-not $Inst) { return ('Install ' + $v) }
  try {
    $c = ([version]$v).CompareTo([version][string]$Inst.version); if ($c -gt 0) { return ('Update to ' + $v) } elseif ($c -eq 0) { return 'Repair' }
  } catch { $null = $_ }   # a version that is not a number: Install
  return ('Install ' + $v) }
# Shows the Maintenance card of an installed application. Takes its install record (version and date).
$ui.VMaint = {
  <#
  .SYNOPSIS
  Shows the Maintenance card for an already-installed application.
  .DESCRIPTION
  Builds the Repair/Update, tool, and Uninstall option rows plus an optional Start button and configures the card.
  .PARAMETER Inst
  The installed application record containing the installed version and date.
  .OUTPUTS
  None.
  #>
  param($Inst)
  $ui.MaintInst = $Inst   # Back from a tool's cards shows this card again
  $verb = & $ui.RowVerb $Inst
  $ui.StartAfter = $false; $startB = $null
  if ([string]$script:app.Start -and (Get-StartPath)) {
    $startKind = $(if ([string]$Inst.version -eq [string]$script:app.Version) { 'primary' } else { '' })
    $startB = @{ Text = 'Start ' + (Get-AppWord); Kind = $startKind; Act = { $ui.StartAfter = $true; & $ui.Checks $false } }
  }
  $ui.MaintVerb = $verb   # read when a row is clicked (a scriptblock does not keep this card's local variables)
  $off = @{ Off = $true; Soon = $true; Index = 0; Name = ('Install ' + $script:app.Version); Ver = ''; Sub = ''; R1 = '' }
  $fixSub = $(if ($verb -eq 'Repair') { 'Adds what is missing. Keeps your data.' } else { 'Installs ' + $script:app.Version + ' and keeps your data.' })
  $fix = @{ Index = 10; Name = $verb; Ver = ''; Sub = $fixSub; R1 = 'Runs the checks' }
  $canUn = (@($script:app.Uninstall).Count -gt 0) -or ((Test-Deploy) -and -not $script:spEnabled)
  $un = $(if ($canUn) {
      $unSub = $(if ($script:spEnabled -and $script:app.Restore) { 'Makes a backup, then removes the app.' } else { 'Removes this app from this computer.' })
      $unR1 = $(if ($script:spEnabled -and $script:app.Restore) { 'Changes the site' } else { 'Removes local files' })
      @{ Index = 20; Name = 'Uninstall'; Ver = ''; Danger = $true; Sub = $unSub; R1 = $unR1 }
    } else {
      @{ Off = $true; Soon = $true; Index = 20; Name = 'Uninstall'; Ver = ''; Sub = 'This app has no Uninstall steps.'; R1 = 'Not set up' }
    })
  $appWord = Get-AppWord
  & $ui.SetCard @{ View = 'maint'; Kicker = ($appWord + ' ' + [string][char]0x2022 + ' ' + $Inst.version); Sentence = ($appWord + ' ' + $Inst.version + ' is installed.')
    Options = (& $ui.InlineRows (@($off, $fix) + @(& $ui.ToolRows) + @($un))); OnOption = { param($j) & $ui.MaintPick $j }
    Buttons = @($startB); Focus = 'button'; Back = { & $ui.VChoose } } }
# Marks the rows of a list as inline rows (one line each: name, text, fact; $ui.OptPlan) and gives each the names of the
# list and their facts, so the name and fact columns are as wide as the widest of the list (every row takes the same
# layout). Takes the rows; gives them back.
$ui.InlineRows = { param($Rows)
  $r = @($Rows | Where-Object { $_ })
  $names = @($r | ForEach-Object { [string]$_.Name }); $facts = @($r | ForEach-Object { [string]$_.R1 }); $subs = @($r | ForEach-Object { [string]$_.Sub })
  foreach ($o in $r) { $o.Inline = $true; $o.Names = $names; $o.Facts = $facts; $o.Subs = $subs }; return , $r }   # one name and one fact column for the whole list
# A click on a row of the Maintenance card: 10 = Update or Repair (the checks, then the install run), 20 = Uninstall (its
# confirm card, part 11), else a tool row (Diagnose, Back up, Restore: $ui.RunTool, part 11). Takes the row's index.
$ui.MaintPick = { param([int]$J)
  if ($J -eq 10) { & $ui.Checks $false } elseif ($J -eq 20) { & $ui.VUninstall } else { & $ui.RunTool $J } }
# The Back target of the tool cards: the Maintenance card. Takes nothing.
$ui.ToolsBack = { & $ui.VMaint $ui.MaintInst }
# Says whether the chosen application has a check that needs the site address. Takes nothing; gives back $true or
# $false.
$ui.NeedSite = { [bool](@($script:appChecks | Where-Object { $_ -in 'net-site', 'site-rights' }).Count) }
# Shows the card that asks for the site address (filled with the saved one, or the DAF SharePoint start).
$ui.VSite = {
  $v = Get-SiteUrl (Get-BasePath); if (-not $v) { $v = $sitePrefix }   # PFM 14 Nov 26: the box starts with the DAF SharePoint address
  & $ui.SetCard @{ View = 'site'; Sentence = 'Which site does the application go to?'; P = @('RADE writes to this SharePoint site. The address is saved for next time.')
    Field = @{ Label = 'Site address'; Text = $v; Name = 'Site address, starts with https://' }; Focus = 'field'
    Buttons = @(@{ Text = 'Continue'; Kind = 'primary'; Act = { & $ui.SaveSite } }); Back = { & $ui.VChoose } }
  try { $ui.Field.SelectionStart = $ui.Field.Text.Length; $ui.Field.SelectionLength = 0 } catch { $null = $_ } }
# Saves the address in the box when it is a valid site address, drops the site checks' old results and runs the checks
# again; else says what is wrong. Takes nothing.
$ui.SaveSite = {
  $v = $ui.Field.Text.Trim()
  if (-not (Test-SiteUrl $v)) { & $ui.Say1 ('The address must look like ' + $sitePrefix + 'name'); return }
  try { $null = Save-SiteUrl (Get-BasePath) $v } catch { $null = $_ }
  foreach ($id in 'net-site', 'site-rights') { if ($script:checkResults.ContainsKey($id)) { $script:checkResults.Remove($id) } }
  & $ui.Checks $false }
# Runs automatic prerequisite checks for the selected application and routes to the next card.
$ui.Checks = {
  <#
  .SYNOPSIS
  Runs automatic prerequisite checks for the selected application and routes to the next card.
  .DESCRIPTION
  Prompts for a site address if needed, executes pending automatic checks while updating progress UI,
  saves the check cache, and advances via $ui.Next unless cancelled.
  .PARAMETER Force
  When true, re-runs checks even if cached results exist in the current window session.
  .OUTPUTS
  None.
  #>
  param([bool]$Force)
  $bp = Get-BasePath; $site = Get-SiteUrl $bp
  if ((& $ui.NeedSite) -and -not (Test-SiteUrl $site)) { & $ui.VSite; return }
  $ids = @($script:appChecks); $cache = Read-CheckCache; $script:savedWhy = @{}
  $ui.Cancel = $false
  $checkNames = @($ids | ForEach-Object { [string](Get-CheckDef $_).Name })
  & $ui.SetCard @{ View = 'checking'; Sentence = 'Checking this computer and your access.'; P = @('Read-only. Nothing is changed.')
    Range = @{ P0 = $checkNames }; Buttons = @(@{ Text = 'Cancel'; Always = $true; Act = { & $ui.CancelChecks } }) }
  & $ui.SetBar 'all' 0 $true; $ui.Bars['all'].Fill = $ui.C.Info; $ui.Busy = $true
  try {
    for ($i = 0; $i -lt $ids.Count; $i++) {
      if ($ui.Form.IsDisposed -or $script:closing) { return }
      if ($ui.Cancel) { break }
      $id = $ids[$i]; $d = Get-CheckDef $id; $have = $script:checkResults[$id]
      if ($d.Kind -ne 'auto') {   # a sign-in or look check: its saved result, else it asks later
        if (-not $have) { $sv = Get-CheckToRun $d $cache $bp $site $false; if ($sv) { $script:checkResults[$id] = $sv } }
        continue
      }
      if ($have -and -not $Force) { continue }
      $sv = Get-CheckToRun $d $cache $bp $site $Force
      if ($sv) { $script:checkResults[$id] = $sv; & $ui.RecRefresh; continue }
      $ui.P[0].Text = [string]$d.Name; $ui.RightL.Text = 'Check ' + ($i + 1) + ' of ' + $ids.Count; & $ui.SetBar 'all' ($i / [math]::Max(1, $ids.Count)) $true
      [System.Windows.Forms.Application]::DoEvents()
      $script:checkResults[$id] = Invoke-Check $d $bp $site { [System.Windows.Forms.Application]::DoEvents() }
      if ($ui.BaseRes.ContainsKey($id)) { $ui.BaseRes[$id] = $script:checkResults[$id] }   # Choose shows the newest result of a base check
      & $ui.RecRefresh   # an open Record shows the new result
    }
  } finally { $null = Save-CheckCache $script:checkResults $bp $site; $ui.Busy = $false; & $ui.SetBar 'all' 0 $false }
  if ($ui.Cancel) { $ui.Cancel = $false; & $ui.VChoose; return }   # Cancel: back to Choose, nothing changed (a check that ran is kept)
  & $ui.Next }
$ui.CancelChecks = {
  # The check that is running ends first (a sign-in window cannot be closed from here); then RADE goes back to Choose.
  $ui.Cancel = $true; & $ui.Say1 'RADE stops after the check that is running.' }
$ui.Next = {
  # One question at a time: the first FAILED check, else the first check that waits for you, else the plan.
  if ($ui.Form.IsDisposed -or $script:closing) { return }
  $ids = @($script:appChecks); $fails = @(); $needs = @()
  for ($i = 0; $i -lt $ids.Count; $i++) { $r = $script:checkResults[$ids[$i]]; if (-not $r -or $r.State -in 'NOT RUN', 'RUNNING') { $needs += $i } elseif ($r.State -eq 'FAILED') { $fails += $i } }
  if ($fails.Count) { & $ui.VFail $fails[0] $fails.Count; return }
  if ($needs.Count) { & $ui.VNeed $needs[0]; return }
  & $ui.VReady }
# Shows the card of a failed check with what to do and a button to run it again. Takes the check number and the count of
# failed checks.
$ui.VFail = {
  <#
  .SYNOPSIS
  Displays the failure details card for a failed prerequisite check and offers retry/site actions.
  .DESCRIPTION
  Renders check name, failure detail, remediation guidance, pass count footer, and retry button matching check kind.
  .PARAMETER I
  Zero-based index of the failed check in $script:appChecks.
  .PARAMETER Count
  Total number of failed checks remaining.
  .OUTPUTS
  None.
  #>
  param([int]$I, [int]$Count)
  $ids = @($script:appChecks); $ui.CurId = [string]$ids[$I]; $d = Get-CheckDef $ids[$I]; $r = $script:checkResults[$ids[$I]]
  $again = $(if ($d.Kind -eq 'signin') { @{ Text = 'Sign in and check site rights'; Kind = 'primary'; Act = { & $ui.One } } }
    elseif ($d.Kind -eq 'guide') { @{ Text = 'Check Power Automate'; Kind = 'primary'; Act = { & $ui.One } } }
    else { @{ Text = 'Run checks again'; Kind = 'primary'; Act = { & $ui.Checks $true } } })
  $ok = @($ids | Where-Object { $script:checkResults[$_] -and $script:checkResults[$_].State -in 'PASSED', 'WARNING' }).Count
  $failSent = $(if ($Count -eq 1) { 'One check failed.' } else { [string]$Count + ' checks failed. This is the first.' })
  & $ui.SetCard @{ View = 'fail'; Light = 'bad'; Kicker = ('Check ' + ($I + 1) + ' of ' + $ids.Count + $dot + 'FAILED'); Sentence = $failSent
    P = @([string]$d.Name, [string]$r.Detail, $(if ($r.Fix) { 'What to do: ' + $r.Fix } else { '' }))
    Buttons = @($again, $(if (& $ui.NeedSite) { @{ Text = 'Change the site address'; Act = { & $ui.VSite } } } else { $null }))
    Foot = ([string]$ok + ' of ' + (& $ui.Counted $ids.Count 'check') + ' passed. RADE changes nothing until every check passes.'); Back = { & $ui.VChoose } }
  & $ui.ToFront }
# Shows the card of a check that needs the user (a sign-in, a look-and-answer, or not run yet). Takes the check number.
$ui.VNeed = { param([int]$I)
  $ids = @($script:appChecks); $ui.CurId = [string]$ids[$I]; $d = Get-CheckDef $ui.CurId; $r = $script:checkResults[$ui.CurId]
  $how = $(if ($d.Kind -eq 'signin') { 'CAC sign-in, read-only' } elseif ($d.Kind -eq 'guide') { 'You look and answer, read-only' } else { 'Not run yet' })
  $text = $(if ($d.Kind -eq 'signin') { 'Sign in and check site rights' } elseif ($d.Kind -eq 'guide') { 'Check Power Automate' } else { 'Run checks again' })
  $mid = $(if ($r -and $r.Detail) { [string]$r.Detail } elseif ($script:savedWhy[$ui.CurId]) { [string]$script:savedWhy[$ui.CurId] } else { $how })
  & $ui.SetCard @{ View = 'need'; Light = 'you'; Kicker = ('Check ' + ($I + 1) + ' of ' + $ids.Count); Sentence = 'One check needs you.'
    P = @([string]$d.Name, $mid, $(if ($r -and $r.Fix) { 'What to do: ' + $r.Fix } else { '' }))
    Buttons = @(@{ Text = $text; Kind = 'primary'; Act = $(if ($d.Kind -eq 'auto') { { & $ui.Checks $true } } else { { & $ui.One } }) }); Back = { & $ui.VChoose } } }
# Runs a single interactive check ($ui.CurId) that requires sign-in or manual observation.
$ui.One = {
  <#
  .SYNOPSIS
  Runs the active interactive check (CAC sign-in or manual guide) and advances to the next card.
  .DESCRIPTION
  Displays the waiting/checking card, invokes Invoke-Check for $ui.CurId, saves cache, and calls $ui.Next unless cancelled.
  .OUTPUTS
  None.
  #>
  $d = Get-CheckDef $ui.CurId; $bp = Get-BasePath; $site = Get-SiteUrl $bp
  $ui.Cancel = $false
  $oneSent = $(if ($d.Kind -eq 'signin') { 'Waiting for your sign-in.' } else { 'Checking.' })
  & $ui.SetCard @{ View = 'checking'; Light = 'you'; Sentence = $oneSent; P = @([string]$d.Name)
    Buttons = @(@{ Text = 'Cancel'; Always = $true; Act = { & $ui.CancelChecks } }) }
  $ui.Busy = $true
  try { $script:checkResults[$ui.CurId] = Invoke-Check $d $bp $site { [System.Windows.Forms.Application]::DoEvents() } }
  finally { $null = Save-CheckCache $script:checkResults $bp $site; $ui.Busy = $false; & $ui.RecRefresh }
  & $ui.ToFront; if ($ui.Cancel) { $ui.Cancel = $false; & $ui.VChoose; return }; & $ui.Next }
$ui.VReady = {
  <#
  .SYNOPSIS
  Displays the Ready summary card after all checks pass, or the OneDrive missing card.
  .DESCRIPTION
  Computes planned writes, steps, warnings, saved site name, resume state, and Start action, then renders the card.
  .OUTPUTS
  None.
  #>
  if ($ui.Form.IsDisposed -or $script:closing) { return }
  $plan = Get-RoundPlan; $ui.Plan = $plan; $dep = Test-Deploy
  if (-not $plan.Found) {
    $noDriveP = @('RADE saves its files in your OneDrive folder.', 'What to do: open OneDrive from the Start menu and sign in. Then select "Look again".')
    & $ui.SetCard @{ View = 'nodrive'; Light = 'bad'; Sentence = 'Your OneDrive folder was not found.'; P = $noDriveP
      Buttons = @(@{ Text = 'Look again'; Kind = 'primary'; Act = { & $ui.VReady } }); Back = { & $ui.VChoose } }; return
  }
  $new = @($plan.Lines | Where-Object { $_ -match '^  New ' }).Count; $rep = @($plan.Lines | Where-Object { $_ -match '^  Replace ' }).Count
  $rec = 0; $in = $false; foreach ($l in $plan.Lines) { if ($l -match '^Clean-up \(runs first') { $in = $true } elseif ($in) { if ($l) { $rec++ } else { $in = $false } } }
  $n = [int][bool]($cleanup.Count -and $ui.Clean); $est = 0; $you = ''; $done = 0   # Clean-up counts as a step, as in the run's "Step k of n"
  foreach ($k in $script:appSteps) {
    if (-not $ui.Sel[[int]$k]) { if ($dep -and -not [bool]$steps[$k].Optional -and -not (Get-StepDefault $k)) { $done++ }; continue }
    $n++; $est += (Get-StepWeight $ui.Hist $steps[$k]).Seconds; if (-not $you -and $steps[$k].Kind -eq 'guide') { $you = 'Step ' + $n + ' needs you.' }
  }
  $ids = @($script:appChecks); $warn = @($ids | Where-Object { $script:checkResults[$_].State -eq 'WARNING' })
  $w1 = ''; if ($warn.Count) {
    $wMore = $(if ($warn.Count -gt 1) { ' (and ' + ($warn.Count - 1) + ' more in Details)' } else { '' })
    $w1 = 'Warning: ' + (Get-CheckDef $warn[0]).Name + '. ' + $script:checkResults[$warn[0]].Detail + $wMore
  }
  $siteName = ''; if ((& $ui.NeedSite) -and (Test-SiteUrl (Get-SiteUrl (Get-BasePath)))) { $siteName = ([string](Get-SiteUrl (Get-BasePath))).TrimEnd('/') -replace '^.*/', '' }
  $startB = $null; $startPrimary = $false
  $rs = Read-RoundState (Get-BasePath); $rsNote = ''
  if ($rs.State -eq 'bad') { $null = Clear-RoundState (Get-BasePath); $rsNote = 'The saved progress of this round could not be read (' + $rs.Why + '), so the round starts over.' }
  elseif ($rs.State -eq 'other') { $null = Clear-RoundState (Get-BasePath); $rsNote = 'Saved progress of another build of this round was not used. The round starts over.' }
  $resB = $(if ($rs.State -eq 'ok') { @{ Text = 'Resume at step ' + $rs.Next + ' of ' + $rs.Total; Kind = 'primary'; Act = { & $ui.ResumeRun } } } else { $null })
  if ($dep -and [string]$script:app.Start) {
    $inst = Read-Installed (Get-InstalledKey $script:app)
    if ($inst -and $inst.installed -and (Get-StartPath)) {
      $startPrimary = ([string]$inst.installed.version -eq [string]$script:app.Version)
      $startB = @{ Text = 'Start ' + (Get-AppWord); Kind = $(if ($startPrimary) { 'primary' } else { '' }); Act = { & $ui.StartApp } }
    }
  }
  if ($resB -and $startB) { $startB.Kind = '' }   # Resume is the one main button (B4, UI standard v1: one primary)
  $hasWork = [bool]($n -or ($cleanup.Count -and $ui.Clean)); $runKind = $(if ($hasWork -and -not $startPrimary) { 'primary' } elseif ($hasWork) { '' } else { 'off' })
  $runB = $(if ($resB) { @{ Text = 'Start over'; Act = { & $ui.StartOver } } } else { @{ Text = $(if ($dep) { 'Install' } else { 'Run' }); Kind = $runKind; Act = { & $ui.Run } } })
  $kicker = $(if ($warn.Count) { (& $ui.Counted ($ids.Count - $warn.Count) 'check') + ' passed' + $dot + (& $ui.Counted $warn.Count 'warning') }
    elseif ($ids.Count -eq 1) { 'The check passed' } else { 'All ' + $ids.Count + ' checks passed' })
  $readySent = $(if ($dep) { 'Ready to install ' + $script:app.Name + ' ' + $script:app.Version + '.' } else { 'Ready to run round ' + $round + '.' })
  $stepLine = ([string]$n + $(if ($n -eq 1) { ' step' } else { ' steps' }) + ', about ' + [math]::Max(1, [int][math]::Round($est / 60)) + ' min. ' + $you +
    $(if ($done) { ' ' + $done + ' already done for this version and off.' } else { '' }))
  $readyField = $(if ($dep -and -not (Test-ShortcutMade)) {
      @{ Label = 'Shortcut in'; Text = (Get-ShortcutDir); Name = 'Folder for the shortcut'; Button = 'Browse'; Act = { & $ui.BrowseDir } } } else { $null })
  $wrLine = 'Writes to ' + $plan.Shown + ': ' + $new + ' new files, ' + $rep + ' replaced, ' + $rec + ' moved to the Recycle Bin.'
  & $ui.SetCard @{ View = 'ready'; Kicker = $kicker; Sentence = $readySent; P = @($wrLine, $stepLine, $w1, $rsNote)
    Buttons = @($resB, $startB, $runB, $(if ($siteName) { @{ Text = 'Change the site address'; Act = { & $ui.VSite } } } else { $null }))
    Foot = $(if ($siteName) { 'Site: ' + $siteName } else { '' }); Field = $readyField; Back = { & $ui.VChoose } }
  if ($ui.StartAfter) {
    $ui.StartAfter = $false
    $noStart = 'The checks passed, but ' + $script:app.Name + ' cannot be started: it is not recorded as installed, or its start file was not found. Select "Install" to install it again.'
    if ($startB) { & $ui.StartApp } else { & $ui.Say1 $noStart }
  } }   # Start on Maintenance: the checks passed, so the application starts
# R29 N8 (the Administrator, 17 Nov 26): the install asks where the app's shortcut goes (engine-v42: one for each app); the box starts with the Desktop folder.
$ui.BrowseDir = {
  $pick = New-Object System.Windows.Forms.FolderBrowserDialog
  try {
    $pick.Description = 'Choose the folder for the shortcut.'; $pick.ShowNewFolderButton = $true
    $v = $ui.Field.Text.Trim(); if ($v -and (Test-Path -LiteralPath $v -PathType Container)) { $pick.SelectedPath = $v }
    if ([string]$pick.ShowDialog($ui.Form) -eq 'OK') { $ui.Field.Text = [string]$pick.SelectedPath }
  } catch { & $ui.Say1 'The folder window could not open. Type the folder in the box.' } finally { $pick.Dispose() } }

# RADE window part 10, keys and form events: the key handlers (F2, Esc, Enter, Ctrl+C, Ctrl+V in the answer box), the window place
# saved and restored, and the call that shows the form. It is the last window part.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# ---- Keys: F1 = Help (the RADE tour); F2 = the Record (Page Down and Page Up move its check list, and on a card that is taller than the window its text);
# Esc = close the Record, else Back where $ui.EscViews says, the Cancel question on Run, and on Choose (no Back) it exits; Enter = the main button; 1 to 9 = a choice.
$ui.Form.Add_KeyDown({
  $k = [string]$_.KeyCode
  if ($_.Control -and $k -eq 'C' -and (& $ui.CopyText $ui.Form.ActiveControl)) { $_.SuppressKeyPress = $true }   # Ctrl+C copies the selected card text
  elseif ((($_.Control -and $k -eq 'V') -or ($_.Shift -and $k -eq 'Insert')) -and
    [object]::ReferenceEquals($ui.Form.ActiveControl, $ui.Field) -and (& $ui.PasteLine $ui.Field)) {
    $_.SuppressKeyPress = $true   # R34: a pasted block goes into the one-line answer box whole
  }
  elseif ($k -eq 'F1') { $_.SuppressKeyPress = $true; & $ui.OpenTour }   # L6: Help = the RADE tour
  elseif ($k -eq 'F2') { $_.SuppressKeyPress = $true; if ($ui.RecOn) { & $ui.CloseRecord } else { & $ui.VRecord } }
  elseif ($ui.RecOn -and $k -in 'PageDown', 'Next', 'PageUp', 'Prior' -and -not (& $ui.InField)) {
    # the check list by keyboard when it is taller than the window; Windows names these keys Next and Prior
    $_.SuppressKeyPress = $true
    $stepY = $(if ($k -in 'PageDown', 'Next') { 1 } else { -1 }) * [math]::Max((& $ui.Sc 40), $ui.RecScroll.ClientSize.Height - (& $ui.Sc 40))
    try { $y = [math]::Abs($ui.RecScroll.AutoScrollPosition.Y) + $stepY; $ui.RecScroll.AutoScrollPosition = New-Object System.Drawing.Point(0, [math]::Max(0, $y)) } catch { $null = $_ }
  }
  elseif (-not $ui.RecOn -and $ui.Scrolls -and $k -in 'PageDown', 'Next', 'PageUp', 'Prior' -and -not (& $ui.InField)) {   # the text of a card that is taller than the window, by keyboard
    $_.SuppressKeyPress = $true
    $stepY = $(if ($k -in 'PageDown', 'Next') { 1 } else { -1 }) * [math]::Max((& $ui.Sc 40), $ui.Scroll.ClientSize.Height - (& $ui.Sc 40))
    try { $y = [math]::Abs($ui.Scroll.AutoScrollPosition.Y) + $stepY; $ui.Scroll.AutoScrollPosition = New-Object System.Drawing.Point(0, [math]::Max(0, $y)) } catch { $null = $_ }
  }
  elseif ($k -eq 'Escape') { $_.SuppressKeyPress = $true   # Cards v2: Back only where it is safe ($ui.EscViews); on the Run card the Cancel question; else nothing
    if ($ui.RecOn) { & $ui.CloseRecord }
    elseif ($ui.View -eq 'run' -and $ui.Running) { & $ui.VCancelQ }
    elseif ($ui.Back -and $ui.EscViews -contains $ui.View -and -not $ui.Busy -and -not $ui.Running) { & $ui.Back }
    elseif ($ui.View -eq 'choose' -and -not $ui.Busy) { $ui.Form.Close() } }
  elseif ($k -in 'Return', 'Enter' -and -not $ui.RecOn -and $ui.Form.AcceptButton -and -not ($ui.BoxNoEnter -and (& $ui.InField)) -and
    -not (($ui.Form.ActiveControl -is [System.Windows.Forms.TextBoxBase]) -and -not $ui.Form.ActiveControl.ReadOnly -and $ui.Form.ActiveControl.Multiline)) {
    $_.SuppressKeyPress = $true; $ui.Form.AcceptButton.PerformClick() }   # Enter = the main button also when the card's text has the focus (a box that takes several lines keeps its Enter)
  elseif ($k -match '^(D|NumPad)([1-9])$' -and -not $ui.RecOn -and -not $ui.Busy -and $ui.Opts.Visible -and -not (& $ui.InField)) {
    $n = [int]$Matches[2]; foreach ($o in @($ui.Opts.Controls)) { if (-not $o.Tag.Off -and [int]$o.Tag.Key -eq $n) { $_.SuppressKeyPress = $true; $o.PerformClick(); break } } } })
# Window size and place (R28, the Administrator, 2026-11-17): the window opens where the user last closed it (RADE\Config\rade-window.json;
# bounds that are off every current screen are ignored); the first time it is maximized on the screen that shows the mouse. The
# minimum size is engine/window.json minSize (640 x 480 at 100 %, so Windows Snap can offer its zones; the Administrator, 2026-11-18;
# 1280 x 720 before), cut to the work area of a small screen. The size and the state at Shown and at close are
# recorded, and the layout self-check runs again after each resize (debounced: 400 ms after the last size change).
$ui.Place = {
  <#
  .SYNOPSIS
  Restores the saved window bounds or maximizes on the active cursor screen, and sets MinimumSize.
  .DESCRIPTION
  Reads saved coordinates, adjusts for DPI changes if still visible on any screen, clamps to the working area,
  falls back to maximized default placement, and constrains MinimumSize to the working area.
  .OUTPUTS
  None.
  #>
  $f = $ui.Form; $saved = Read-WindowState; $ui.Placed = 'first run'; $ui.LastClose = $(if ($saved) { [string]$saved.Closed } else { '' })
  try {
    $use = $null; $wa = $null
    if ($saved) { $r = New-Object System.Drawing.Rectangle($saved.X, $saved.Y, $saved.W, $saved.H)
      foreach ($sc in @([System.Windows.Forms.Screen]::AllScreens)) {
        $i = [System.Drawing.Rectangle]::Intersect($sc.WorkingArea, $r)
        if ($i.Width -ge (& $ui.Sc 120) -and $i.Height -ge (& $ui.Sc 60)) { $use = $r; $wa = $sc.WorkingArea; break }
      } }
    if ($use) {
      $w = $use.Width; $h = $use.Height
      if ($saved.Dpi -gt 0 -and [int]$ui.Dpi -ne $saved.Dpi) { $w = [int]($w * $ui.Dpi / $saved.Dpi); $h = [int]($h * $ui.Dpi / $saved.Dpi) }   # the screen scale changed since: the size follows
      $w = [math]::Min($w, $wa.Width); $h = [math]::Min($h, $wa.Height)
      $x = [math]::Max($wa.Left, [math]::Min($use.X, $wa.Right - $w)); $y = [math]::Max($wa.Top, [math]::Min($use.Y, $wa.Bottom - $h))
      $f.Bounds = New-Object System.Drawing.Rectangle($x, $y, $w, $h); $ui.Placed = 'saved'
      if ($saved.State -eq 'Maximized') { $f.WindowState = 'Maximized' }
    } else {
      $sc = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position); $wa = $sc.WorkingArea
      $f.Width = [int]($wa.Width * 0.95); $f.Height = [int]($wa.Height * 0.95)
      $f.Left = $wa.Left + [int](($wa.Width - $f.Width) / 2); $f.Top = $wa.Top + [int](($wa.Height - $f.Height) / 2)   # where Restore goes
      $f.WindowState = 'Maximized'
    }
    $f.MinimumSize = New-Object System.Drawing.Size([math]::Min((& $ui.Sc $ui.Layout.MinW), $wa.Width), [math]::Min((& $ui.Sc $ui.Layout.MinH), $wa.Height))
  } catch { $null = $_ } }
# Gives the form's client size and window state as text like "1020x760/Normal". Takes nothing.
$ui.WinNow = {
  $f = $ui.Form; $s = [string]$f.WindowState
  if ($s -notin 'Normal', 'Maximized', 'Minimized') { $s = 'Normal' }
  return ([string]$f.ClientSize.Width + 'x' + $f.ClientSize.Height + '/' + $s) }
$ui.ResizeT = New-Object System.Windows.Forms.Timer; $ui.ResizeT.Interval = 400
$ui.ResizeT.Add_Tick({ $ui.ResizeT.Stop(); try { if ($ui.Scaled -and [string]$ui.Form.WindowState -ne 'Minimized') { & $ui.Fit; & $ui.Check } } catch { $null = $_ } })
$ui.Form.Add_Resize({ try { if ($ui.Scaled) { $ui.ResizeT.Stop(); $ui.ResizeT.Start() } } catch { $null = $_ } })
# The mouse wheel (R32, the Administrator, 2026-11-18: "scroll works only when hovering the scroll bar"). Windows sends the
# wheel to the control that has the focus, and a text of the card or a button does not pass it on. So every control of the
# window hands the wheel to $ui.Wheel: it moves the Record's list when the Record is open, else the card's text, 3 lines for
# each notch, when that area has more than it shows. A box that scrolls its own text (the log) keeps the wheel.
# Takes the control that got the wheel and the event; marks the event as handled when it moved an area.
$ui.Wheel = { param($S, $E)
  try {
    if (($S -is [System.Windows.Forms.TextBoxBase]) -and $S.Multiline -and [string]$S.ScrollBars -ne 'None') { return }
    if ($S -is [System.Windows.Forms.ScrollableControl] -and $S.AutoScroll -and $S.VerticalScroll.Visible) { return }   # an area that scrolls moves itself
    $a = $(if ($ui.RecOn) { $ui.RecScroll } else { $ui.Scroll }); if (-not $a -or -not $a.VerticalScroll.Visible) { return }
    $y = [math]::Abs($a.AutoScrollPosition.Y) - [int][math]::Round($E.Delta / 120.0 * 3 * $ui.F.Body.Height)
    $a.AutoScrollPosition = New-Object System.Drawing.Point(0, ([int][math]::Max(0, $y)))
    if ($E -is [System.Windows.Forms.HandledMouseEventArgs]) { $E.Handled = $true }
  } catch { $null = $_ } }   # the wheel never stops the window
# Hooks the wheel on a control and on every control inside it (a control added later hands the wheel to its parent, which
# has the hook). Takes the control.
$ui.WheelOn = { param($C) try { $C.Add_MouseWheel({ & $ui.Wheel $this $_ }) } catch { $null = $_ }; foreach ($k in @($C.Controls)) { & $ui.WheelOn $k } }   # a control with no wheel event: skipped
