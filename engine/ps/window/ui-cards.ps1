# RADE window part 03, the card: the one block that shows a statement or a question, with its parts (line,
# sentence, paragraphs, choices, box, hand-step text, step line, buttons) and the one-line text box helper.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.
# Network: none.
# Writes: none.
# Credentials: none.

# ---- The card: one block, its text column centered (76.5 % of the width, at most 680 px: engine/window.json), 40 % of the spare height above it. Top to bottom: a small
# line in capitals (the header row), the sentence, up to four paragraphs, the choices, a box with its label, the lines of a hand step (one
# selectable text: the numbered lines, then the unnumbered ones), the file path of a hand step, the step line (name, bar,
# time in the step, count), the last log line, the error box, two file links, a note, the help line, the closing line of
# a hand step, the buttons, a last gray line, and the Administrator's test extras. A card shows only the parts it names ($ui.SetCard).
$ui.Card = New-Object System.Windows.Forms.TableLayoutPanel
$ui.Card.Dock = 'Fill'; $ui.Card.ColumnCount = 3; $ui.Card.RowCount = 3; $ui.Card.BackColor = $ui.C.White
# Three columns: a side, the text column, a side. The text column is $ui.Layout.Share % of the width and at most $ui.Layout.MaxW
# (engine/window.json); the two sides share what is left, so the column is centered ($ui.Fit sets the sizes).
$ui.CardCols = @(); $sd = (100 - $ui.Layout.Share) / 2
foreach ($w in @($sd, $ui.Layout.Share, $sd)) { $cs = New-Object System.Windows.Forms.ColumnStyle('Percent', $w); $ui.CardCols += $cs; [void]$ui.Card.ColumnStyles.Add($cs) }
# Three rows: the room above the frame (a fixed height, set by $ui.Squeeze), the frame, the rest (L1, the Administrator, 2026-11-19).
$ui.CardRows = @(
  (New-Object System.Windows.Forms.RowStyle('Absolute', 0)),
  (New-Object System.Windows.Forms.RowStyle('AutoSize')),
  (New-Object System.Windows.Forms.RowStyle('Percent', 100)))
foreach ($rs in $ui.CardRows) { [void]$ui.Card.RowStyles.Add($rs) }
# The card frame (L1, the Administrator, 2026-11-19): its top is fixed (40 % of the spare height above a frame of
# $ui.Layout.FrameMin, engine/window.json), it is that tall at least and grows down to the bottom line at most. It is a
# stack of four: the header row (the line in capitals, "Step x of n": it never scrolls and never moves), the body, a gap
# that fills a short card up to the minimum height, and the tail, so the buttons sit at the bottom of the frame.
# The card is a stack: the body (every part above the buttons) and the tail (the buttons, the last gray line
# and the test extras). The body sits in a panel that scrolls only when the card is taller than the window, so the
# buttons are always in view (the Administrator, 2026-11-15; $ui.Squeeze). No scroll at 1020 x 616 and larger.
$ui.MkStack = {
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.AutoSize = $true; $t.AutoSizeMode = 'GrowAndShrink'; $t.ColumnCount = 1; $t.Margin = (& $ui.Pad 0 0 0 0); $t.BackColor = $ui.C.White
  [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize'))); $t }
$ui.Stack = & $ui.MkStack; $ui.Stack.Anchor = 'Top, Left'; $ui.Body = & $ui.MkStack; $ui.Tail = & $ui.MkStack
$ui.Scroll = New-Object System.Windows.Forms.Panel
$ui.Scroll.AutoScroll = $true; $ui.Scroll.Margin = (& $ui.Pad 0 0 0 0); $ui.Scroll.BackColor = $ui.C.White; $ui.Scroll.AccessibleName = 'Card text'
$ui.Body.Location = New-Object System.Drawing.Point(0, 0); [void]$ui.Scroll.Controls.Add($ui.Body)
$ui.Kick = & $ui.Text $ui.F.SmallB $ui.C.Gray 0 'Card line'; $ui.Kick.Visible = $true; $ui.MinLines[$ui.Kick] = 1   # one line tall also when the card has no line
# The YOUR TURN chip (plan engine-v48 step 3; critique change 1, the Administrator, 2026-11-27): on a card where RADE waits for the
# person (the yellow light), a yellow chip "YOUR TURN" stands before the line in capitals; the separate "Your turn" line of
# R35 is gone. Yellow means only this (and the light line).
$ui.Chip = & $ui.Label $ui.F.SmallB $ui.C.OnYellow 0; $ui.Chip.BackColor = $ui.C.Yellow; $ui.Chip.Text = 'YOUR TURN'; $ui.Chip.AccessibleName = 'Your turn'
# its tokens for $ui.Recolor
$ui.Chip.Padding = (& $ui.Pad $ui.Z.G2 $ui.Z.G1 $ui.Z.G2 $ui.Z.G1)
$ui.Chip.Margin = (& $ui.Pad 0 0 $ui.Z.G3 0); $ui.Roles[$ui.Chip] = @{ ForeColor = 'OnYellow'; BackColor = 'Yellow' }
# The header row: the chip (on your turn), then the line in capitals, on one line. It never scrolls and never moves.
$ui.Head = & $ui.Flow 0; $ui.Head.Visible = $true; $ui.Head.AccessibleName = 'Card header'
[void]$ui.Head.Controls.Add($ui.Chip); [void]$ui.Head.Controls.Add($ui.Kick)
$ui.Body.Add_SizeChanged({ & $ui.Squeeze }); $ui.Tail.Add_SizeChanged({ & $ui.Squeeze }); $ui.Head.Add_SizeChanged({ & $ui.Squeeze })
$ui.Card.Add_SizeChanged({ try { & $ui.Fit } catch { $null = $_ } })
$ui.Gap = New-Object System.Windows.Forms.Panel; $ui.Gap.Size = New-Object System.Drawing.Size(1, 0); $ui.Gap.Margin = (& $ui.Pad 0 0 0 0); $ui.Gap.BackColor = $ui.C.White; $ui.Gap.Visible = $false
$ui.SentRow = & $ui.Flow $ui.Z.G1; $ui.SentRow.Visible = $true
$ui.TickP = New-Object System.Windows.Forms.Panel
$ui.TickP.Size = New-Object System.Drawing.Size(30, 30); $ui.TickP.Margin = (& $ui.Pad 0 9 12 0)
$ui.TickP.Visible = $false; $ui.TickP.AccessibleRole = 'StaticText'; $ui.TickP.AccessibleName = 'Passed'
$ui.TickP.Add_Paint({
  try {
    $g = $_.Graphics; $g.SmoothingMode = 'AntiAlias'; $w = $this.ClientSize.Width
    $pn = New-Object System.Drawing.Pen($ui.C.Green, [single]($w * 0.14)); $pn.StartCap = 'Round'; $pn.EndCap = 'Round'
    $pts = [System.Drawing.PointF[]]@(
      (New-Object System.Drawing.PointF([single](0.16 * $w), [single](0.54 * $w))),
      (New-Object System.Drawing.PointF([single](0.40 * $w), [single](0.76 * $w))),
      (New-Object System.Drawing.PointF([single](0.84 * $w), [single](0.26 * $w))))
    $g.DrawLines($pn, $pts); $pn.Dispose()
  } catch { $null = $_ } })
$ui.Sent = & $ui.Text $ui.F.Sent $ui.C.Navy 0 'Card headline'; $ui.Sent.Visible = $true
[void]$ui.SentRow.Controls.Add($ui.TickP); [void]$ui.SentRow.Controls.Add($ui.Sent)
$ui.P = @(); foreach ($k in 0..3) { $ui.P += (& $ui.Text $ui.F.Body $ui.C.Navy $(if ($k) { $ui.Z.G1 } else { $ui.Z.G3 }) ('Card text ' + ($k + 1))) }
$ui.Opts = & $ui.Flow $ui.Z.G6; $ui.Opts.FlowDirection = 'TopDown'; $ui.Opts.AccessibleName = 'Choices'
# The lines of a hand step (R28 N4, the Administrator, 2026-11-17: the text can be selected across many lines): ONE read-only
# rich text box. A numbered line has its number right-aligned in a column and its text, wrapped, in the text column (a
# figure spaces in front of a shorter number, a tab and a hanging indent); a line with no number follows the list, small and gray. Filled by $ui.SetSteps.
$ui.Guide = New-Object System.Windows.Forms.RichTextBox
$ui.Guide.ReadOnly = $true; $ui.Guide.BorderStyle = 'None'; $ui.Guide.ScrollBars = 'None'
$ui.Guide.WordWrap = $true; $ui.Guide.DetectUrls = $false; $ui.Guide.TabStop = $false; $ui.Guide.Multiline = $true
$ui.Guide.BackColor = $ui.C.White; $ui.Guide.ForeColor = $ui.C.Navy; $ui.Guide.Font = $ui.F.Body
$ui.Guide.Margin = (& $ui.Pad 0 $ui.Z.G3 0 0); $ui.Guide.Visible = $false; $ui.Guide.ContextMenuStrip = $ui.Menu; $ui.Guide.AccessibleName = 'Steps to do'
$ui.Guide.Add_ContentsResized({ try { $ui.GuideH = [int]$_.NewRectangle.Height; & $ui.GuideFit } catch { $null = $_ } })
$ui.Guide.Add_GotFocus({ & $ui.NoCaret $this }); $ui.Guide.Add_MouseUp({ & $ui.NoCaret $this }); $ui.Guide.Add_KeyUp({ & $ui.NoCaret $this })
$ui.GuideNums = @(); $ui.GuideTexts = @(); $ui.GuideRest = @(); $ui.GuideH = 0; $ui.GuideInkAt = 0
# The file a hand step made, by its full path (R28 N6: a step that pastes the path from the clipboard shows it, to check it).
$ui.PathL = & $ui.Label $ui.F.SmallB $ui.C.Gray $ui.Z.G3; $ui.PathL.Text = 'File path'
$ui.PathT = & $ui.Text $ui.F.Small $ui.C.Navy $ui.Z.G1 'File path'
# ---- The Run card (plan engine-v48 step 3, Cards v2): one percent and one bar for the whole run, then the step list: the
# steps before the running one ($ui.RunA), the running step ($ui.RunRow), the steps after it ($ui.RunB). The rows of the
# other steps are drawn ($ui.PaintRuns, 07-run.ps1): the name, a second line in 2 lines at most, the status as icon and word.
$ui.PctRow = & $ui.Flow $ui.Z.G3; $ui.PctRow.AccessibleName = 'Progress of the run'
$ui.PctL = & $ui.Label $ui.F.Word $ui.C.Navy 0; $ui.PctL.Visible = $true
$ui.PctL.AccessibleName = 'Percent of the run'; $ui.Most[$ui.PctL] = @('100 %'); $ui.PctL.Add_TextChanged({ & $ui.FixW $this })
$ui.RunBar = & $ui.MkBar 'run' 'Progress of all steps'; $ui.RunBar.Height = 6; $ui.RunBar.Margin = (& $ui.Pad 0 $ui.Z.G1 0 $ui.Z.G3)
[void]$ui.PctRow.Controls.Add($ui.PctL)
# Makes one drawn list of step rows (above or below the running step). Takes the name; gives back the panel.
$ui.MkRuns = { param([string]$Name) $p = New-Object System.Windows.Forms.Panel; $p.Margin = (& $ui.Pad 0 0 0 0); $p.BackColor = $ui.C.White; $p.AccessibleRole = 'StaticText'; $p.AccessibleName = $Name
  $p.Tag = @(); $p.Visible = $false; $p.Add_Paint({ & $ui.PaintRuns $this $_.Graphics }); $p }
$ui.RunA = & $ui.MkRuns 'Steps before this one'; $ui.RunB = & $ui.MkRuns 'Steps after this one'
# The running step: a tinted row with its name and RUNNING at the right, its summary (the step's doing text), its bar with
# the time in the step and the count, and the now-doing line under the bar (2 lines; it wraps).
$ui.RunRow = & $ui.Flow 0; $ui.RunRow.FlowDirection = 'TopDown'; $ui.RunRow.BackColor = $ui.C.Tint
$ui.RunRow.Padding = (& $ui.Pad $ui.Z.G2 $ui.Z.G2 $ui.Z.G2 $ui.Z.G2); $ui.RunRow.AccessibleName = 'The running step'
$ui.RunHead = & $ui.Flow 0; $ui.RunHead.Visible = $true; $ui.RunHead.BackColor = $ui.C.Tint
$ui.StepName = & $ui.Text $ui.F.SmallB $ui.C.Navy 0 'Step name'; $ui.StepName.Visible = $true; $ui.StepName.BackColor = $ui.C.Tint
$ui.RunWord = & $ui.Label $ui.F.SmallB $ui.C.Info 0; $ui.RunWord.Text = 'RUNNING'; $ui.RunWord.Visible = $true; $ui.RunWord.BackColor = $ui.C.Tint; $ui.RunWord.AccessibleName = 'Status: running'
[void]$ui.RunHead.Controls.Add($ui.StepName); [void]$ui.RunHead.Controls.Add($ui.RunWord)
$ui.StepSum = & $ui.Text $ui.F.Small $ui.C.Navy $ui.Z.G1 'What the step does'; $ui.StepSum.BackColor = $ui.C.Tint
$ui.StepRow = & $ui.Flow $ui.Z.G1; $ui.StepRow.Visible = $true; $ui.StepRow.BackColor = $ui.C.Tint
$ui.StepBar = & $ui.MkBar 'step' 'Progress of this step'; $ui.StepBar.Width = 200; $ui.StepBar.Margin = (& $ui.Pad 0 $ui.Z.BarTop $ui.Z.G2 0)
# R28 N10: the time in this step, at the right end of its bar ("4m 12s"), every second ($ui.TimeT). The log keeps "Started".
$ui.StepTime = & $ui.Label $ui.F.Small $ui.C.Gray 2; $ui.StepTime.Visible = $true; $ui.StepTime.AccessibleName = 'Time in this step'; $ui.StepTime.BackColor = $ui.C.Tint
$ui.StepFrac = & $ui.Label $ui.F.Small $ui.C.Gray 2; $ui.StepFrac.Visible = $true; $ui.StepFrac.Margin = (& $ui.Pad $ui.Z.G3 2 0 0); $ui.StepFrac.BackColor = $ui.C.Tint
# The time ("4m 12s", "1h 04m 12s") and the count ("3 of 12") keep one size from their widest value ($ui.FixW), so the bar
# beside them never changes its width as they count (the Administrator, 2026-11-19).
$ui.Most[$ui.StepTime] = @('9h 59m 59s'); $ui.Most[$ui.StepFrac] = @('999 of 999')
foreach ($c in @($ui.StepTime, $ui.StepFrac)) { $c.Add_TextChanged({ & $ui.FixW $this }) }
foreach ($c in @($ui.StepBar, $ui.StepTime, $ui.StepFrac)) { [void]$ui.StepRow.Controls.Add($c) }
# The now-doing line (L7, the Administrator, 2026-11-19): what the running step does now ($ui.ShowNow). It has a fixed room
# of $ui.NowLines lines, shown also with no text, so Cancel under it never moves; a text wraps to those 2 lines (Cards v2).
$ui.Now = & $ui.Text $ui.F.Small $ui.C.Gray $ui.Z.G1 'Now doing'; $ui.Now.BackColor = $ui.C.Tint; $ui.Now.Visible = $true
$ui.NowLines = 2; $ui.Hold[$ui.Now] = $ui.NowLines
foreach ($c in @($ui.RunHead, $ui.StepSum, $ui.StepRow, $ui.Now)) { [void]$ui.RunRow.Controls.Add($c) }
# The WHAT TO DO box of the step-failed card (Cards v2): a 1 px edge around the label and the text.
$ui.Todo = & $ui.Flow $ui.Z.G3; $ui.Todo.FlowDirection = 'TopDown'; $ui.Todo.Padding = (& $ui.Pad $ui.Z.G3 $ui.Z.G2 $ui.Z.G3 $ui.Z.G2); $ui.Todo.AccessibleName = 'What to do'
$ui.TodoL = & $ui.Label $ui.F.SmallB $ui.C.Gray 0; $ui.TodoL.Text = 'WHAT TO DO'; $ui.TodoL.Visible = $true
$ui.TodoT = & $ui.Text $ui.F.Body $ui.C.Navy $ui.Z.G1 'What to do'; $ui.TodoT.Visible = $true
[void]$ui.Todo.Controls.Add($ui.TodoL); [void]$ui.Todo.Controls.Add($ui.TodoT)
$ui.Todo.Add_Paint({
  try {
    $pn = New-Object System.Drawing.Pen($ui.C.Edge); $_.Graphics.DrawRectangle($pn, 0, 0, ($this.ClientSize.Width - 1), ($this.ClientSize.Height - 1)); $pn.Dispose()
  } catch { $null = $_ } })   # no edge drawn: the box still shows its text
$ui.FieldRow = & $ui.Flow $ui.Z.G2; $ui.FieldRow.WrapContents = $true; & $ui.Ring $ui.FieldRow
$ui.FieldL = & $ui.Label $ui.F.SmallB $ui.C.Gray 9; $ui.FieldL.Visible = $true
# A one-line box: a frame as tall as a compact button with RADE's own 1 px edge, the text box inside it with no border,
# in the middle (a text box cannot be made taller with its text in the middle). The ring goes around the frame.
$ui.Boxes = @()
# Sizes and centers the text box inside its one-line frame. Takes the frame panel; does nothing before the window has
# its scale; gives back nothing.
# The text box is one line of its font tall, as Windows draws the text ($ui.LineH; R35: a box that sized itself was 27 high
# where a line needs 32 at 150 %), and never taller than the frame inside its edge.
$ui.BoxFit = { param($P) if (-not $ui.Scaled) { return }
  try { $tb = $P.Controls[0]; $in = & $ui.Sc 6; $h = [math]::Max(1, [math]::Min((& $ui.LineH $tb.Font), ($P.ClientSize.Height - (& $ui.Sc 2)))); if ($tb.Height -ne $h) { $tb.Height = $h }
    $tb.Width = [math]::Max(10, $P.ClientSize.Width - 2 * $in)
    $tb.Location = New-Object System.Drawing.Point($in, [int][math]::Floor(($P.ClientSize.Height - $tb.Height) / 2)) } catch { $null = $_ } }
# Wraps a text box in a one-line frame with its own 1 px edge and a focus ring. Takes the text box and the frame width;
# gives back the frame panel and remembers it in $ui.Boxes.
$ui.MkBox = { param($Tb, [int]$W)
  $p = New-Object System.Windows.Forms.Panel; $p.Size = New-Object System.Drawing.Size($W, $ui.Z.CompactH); $p.BackColor = $ui.C.White; $p.AccessibleName = 'Text box'
  $Tb.BorderStyle = 'None'; $Tb.AutoSize = $false; $Tb.Font = $ui.F.Small; $Tb.ForeColor = $ui.C.Ink
  $Tb.BackColor = $ui.C.White; [void]$p.Controls.Add($Tb)
  $Tb.Add_GotFocus({ try { $this.Parent.Parent.Invalidate() } catch { $null = $_ } })
  $Tb.Add_LostFocus({ try { $this.Parent.Parent.Invalidate() } catch { $null = $_ } })
  $p.Add_Paint({
    try { $pn = New-Object System.Drawing.Pen($ui.C.Edge); $_.Graphics.DrawRectangle($pn, 0, 0, ($this.ClientSize.Width - 1), ($this.ClientSize.Height - 1)); $pn.Dispose() } catch { $null = $_ } })
  $p.Add_SizeChanged({ & $ui.BoxFit $this }); $p.Add_Click({ try { [void]$this.Controls[0].Focus() } catch { $null = $_ } }); $ui.Boxes += $p; $p }
$ui.Field = New-Object System.Windows.Forms.TextBox
# On a card with BoxNoEnter (the hand card) Enter in the box answers nothing: the main button is not the Enter button
# while the box has the focus (review of PR 211: Enter in the address box answered Done).
$ui.Field.Add_GotFocus({ if ($ui.BoxNoEnter) { $ui.Form.AcceptButton = $null } }); $ui.Field.Add_LostFocus({ if ($ui.BoxNoEnter) { $ui.Form.AcceptButton = $ui.AcceptOn } })
$ui.FieldBox = & $ui.MkBox $ui.Field $ui.Z.FieldM; $ui.FieldBox.Margin = (& $ui.Pad $ui.Z.G2 $ui.Z.M $ui.Z.M $ui.Z.M)   # 8 from the label; 4 + the button's 4 = 8 to the button
$ui.FieldB = & $ui.Btn 'compact'
$ui.FieldB.Add_Click({ if ($ui.FieldDo) { & $ui.FieldDo } })
foreach ($c in @($ui.FieldL, $ui.FieldBox, $ui.FieldB)) { [void]$ui.FieldRow.Controls.Add($c) }
$ui.ErrRow = & $ui.Flow $ui.Z.G2; & $ui.Ring $ui.ErrRow
$ui.ErrBox = New-Object System.Windows.Forms.TextBox
$ui.ErrBox.Multiline = $true; $ui.ErrBox.ScrollBars = 'Vertical'; $ui.ErrBox.Size = New-Object System.Drawing.Size($ui.Z.FieldL, 96)
$ui.ErrBox.Margin = (& $ui.Pad 4 4 4 4); $ui.ErrBox.BorderStyle = 'FixedSingle'
$ui.ErrBox.Font = $ui.F.Small; $ui.ErrBox.ForeColor = $ui.C.Ink; $ui.ErrBox.BackColor = $ui.C.White; $ui.ErrBox.AccessibleName = 'Error message'; & $ui.Cue $ui.ErrBox
[void]$ui.ErrRow.Controls.Add($ui.ErrBox)
$ui.LinkRow = & $ui.Flow 0; $ui.LinkRow.WrapContents = $true; $ui.LinkRow.Margin = (& $ui.Pad (-$ui.Z.M) 0 0 0); & $ui.Ring $ui.LinkRow
$ui.CopyPathB = & $ui.LinkBtn 'Copy file path'; $ui.ShowFileB = & $ui.LinkBtn 'Show file in folder'; $ui.PageB = & $ui.LinkBtn 'Open repository page'
$ui.PageB.AccessibleName = 'Open the repository page in your browser'; $ui.PageB.Visible = $false
foreach ($c in @($ui.CopyPathB, $ui.ShowFileB, $ui.PageB)) { [void]$ui.LinkRow.Controls.Add($c) }
$ui.Note = & $ui.Text $ui.F.Small $ui.C.Gray $ui.Z.G2 'Note'
$ui.Help = & $ui.Text $ui.F.Body $ui.C.Navy $ui.Z.G4 'Help'
$ui.Close = & $ui.Text $ui.F.Small $ui.C.Gray $ui.Z.G4 'Closing line'   # the hand card's closing line, directly above the buttons ($ui.VHand)
# the buttons' own 4 px margin is part of the 16 px gap
$ui.BtnRow = & $ui.Flow $ui.Z.G4; $ui.BtnRow.WrapContents = $true; $ui.BtnRow.Margin = (& $ui.Pad (-$ui.Z.M) ($ui.Z.G4 - $ui.Z.M) 0 0); & $ui.Ring $ui.BtnRow
[void]$ui.BtnRow.Controls.Add($ui.BackB)   # B6: Back (Esc) first, at the left end
$ui.B = @(); foreach ($k in 0..($ui.NB - 1)) {
  $b = & $ui.Btn 'action'; $b.Tag = $k
  $b.Add_Click({ $a = $ui.Acts[[int]$this.Tag]; if ($a -and (-not $ui.Busy -or $ui.Always[[int]$this.Tag]) -and (& $ui.Settled)) { & $a } })
  $ui.B += $b; [void]$ui.BtnRow.Controls.Add($b)
}
$ui.Foot = & $ui.Text $ui.F.Small $ui.C.Gray ($ui.Z.G6 - $ui.Z.M) 'Last line'
# the Administrator's test extras (test rounds only; they go away with the test branch): the results address, the e-mail draft
# and "the window displayed correctly". A deploy never shows them: it sends nothing.
$ui.TestRow = & $ui.Flow ($ui.Z.G6 - $ui.Z.M); $ui.TestRow.WrapContents = $true; & $ui.Ring $ui.TestRow
$ui.TestL = & $ui.Label $ui.F.SmallB $ui.C.Gray 10; $ui.TestL.Text = 'Test rounds only'; $ui.TestL.Visible = $true
$ui.ToBox = New-Object System.Windows.Forms.TextBox
$ui.ToBox.AccessibleName = 'Send results to (e-mail)'; $ui.ToBoxF = & $ui.MkBox $ui.ToBox $ui.Z.FieldS; $ui.ToBoxF.Margin = (& $ui.Pad $ui.Z.G2 $ui.Z.M $ui.Z.M $ui.Z.M)
$ui.DraftB = & $ui.LinkBtn 'Make e-mail draft'
$ui.OkBox = New-Object System.Windows.Forms.CheckBox
$ui.OkBox.AutoSize = $true; $ui.OkBox.Checked = $true; $ui.OkBox.Text = 'The window displayed correctly'; $ui.OkBox.ForeColor = $ui.C.Gray
$ui.OkBox.Margin = (& $ui.Pad 4 9 4 4); $ui.OkBox.AccessibleName = 'The window displayed correctly (nothing overlapped or cut off)'
foreach ($c in @($ui.TestL, $ui.ToBoxF, $ui.DraftB, $ui.OkBox)) { [void]$ui.TestRow.Controls.Add($c) }
# Puts controls into a table as one auto-sized row each, top to bottom. Takes the table and the list of controls; sets
# the row count; gives back nothing.
$ui.Fill = { param($T, $Parts)
  $row = 0
  foreach ($c in @($Parts)) { [void]$T.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize'))); $T.Controls.Add($c, 0, $row); $row++ }
  $T.RowCount = $row }
& $ui.Fill $ui.Body @($ui.SentRow, $ui.P[0], $ui.P[1], $ui.P[2], $ui.P[3], $ui.Opts, $ui.FieldRow, $ui.Guide, $ui.PathL, $ui.PathT, $ui.PctRow, $ui.RunBar, $ui.RunA, $ui.RunRow, $ui.RunB,
  $ui.ErrRow, $ui.Todo, $ui.LinkRow, $ui.Note, $ui.Help)
$i = 0; foreach ($x in @($ui.BtnRow.Controls)) { $x.TabIndex = $i; $i++ }   # Tab goes along the row from the left: Back (Esc) first, the primary last (B3, B6)
& $ui.Fill $ui.Tail @($ui.Close, $ui.BtnRow, $ui.Foot, $ui.TestRow)
& $ui.Fill $ui.Stack @($ui.Head, $ui.Scroll, $ui.Gap, $ui.Tail)
$ui.Card.Controls.Add($ui.Stack, 1, 1); $ui.Card.SetColumnSpan($ui.Stack, 2)   # two columns: room for the scroll bar beside the text

# ---- What a card shows around its text (plan engine-v48 steps 2 to 4; $ui.SetCard calls these)
# Esc (Cards v2; critique change 4, the Administrator, 2026-11-27): Back only on Choose, Maintenance and the not-installed card, and
# on the Run card Esc opens the Cancel question. Your turn and Done take no Esc; the Back of another card is a plain "Back".
$ui.EscViews = @('choose', 'maint', 'notinst')
$ui.Dress = {
  <#
  .SYNOPSIS
  Sets the parts of a card that are not its text: the light line, the stage now, the YOUR TURN chip, the color of the line
  in capitals and the parts of the Run and step-failed cards.
  .PARAMETER C
  The card (the hashtable of $ui.SetCard): Light ('you', 'bad' or 'pass'), KickColor (a token name), StepRow, Todo.
  .OUTPUTS
  Nothing.
  #>
  param($C)
  & $ui.SetLight ([string]$C.Light); & $ui.SetStage ([string]$C.View) ([string]$C.Light -eq 'pass')
  $ui.Chip.Visible = ([string]$C.Light -eq 'you'); $ui.Kick.ForeColor = $(if ($C.KickColor) { $ui.C[[string]$C.KickColor] } else { $ui.C.Gray })
  if ($ui.Scaled) {   # the line in capitals beside the chip
    $kw = [int]$ui.ContentW - $(if ($ui.Chip.Visible) { [int]$ui.Chip.PreferredSize.Width + (& $ui.Sc $ui.Z.G3) } else { 0 })
    & $ui.SetWrap $ui.Kick $kw
  }
  foreach ($x in @($ui.PctRow, $ui.RunBar, $ui.RunRow)) { $x.Visible = [bool]$C.StepRow }
  if (-not $C.StepRow) { $ui.RunA.Visible = $false; $ui.RunB.Visible = $false }
  $ui.Todo.Visible = [bool]$C.Todo; $ui.TodoT.Text = [string]$C.Todo
  $om = & $ui.Sc $(if (@($C.Options | Where-Object { $_ -and $_.Inline }).Count) { $ui.Z.G4 } else { $ui.Z.G6 }); $m = $ui.Opts.Margin   # one-line rows (Maintenance): 16 above the list
  if ($m.Top -ne $om) { $ui.Opts.Margin = New-Object System.Windows.Forms.Padding($m.Left, $om, $m.Right, $m.Bottom) }
  $ui.P[0].Font = $(if ($C.Strong) { $ui.F.Turn } else { $ui.F.Body }) }   # the Done card's summary line is strong
# Says whether a button text fits the widest button (B1: 240 x 40) with the button's padding, as $ui.BtnSize measures it. A
# main button whose text with " (Enter)" does not fit keeps its text alone (Enter still selects it). Takes the text.
$ui.KeyFits = { param([string]$T)
  try {
    return ([int][System.Windows.Forms.TextRenderer]::MeasureText($T, $ui.F.SmallB).Width + (& $ui.Sc (2 * $ui.Z.G2)) -le (& $ui.Sc $ui.Z.WideW))
  } catch { return $true } }   # no measure: the key shows
$ui.SetButtons = {
  <#
  .SYNOPSIS
  Fills the action row of a card: the primary button last (B3, B4) with its key in its text ("Done (Enter)"), Back at the
  left end ("Back (Esc)" where Esc does Back), and Enter on the primary unless the card says NoAccept.
  .PARAMETER C
  The card: Buttons (Text, Kind, Act, Always; up to $ui.NB), Back, NoAccept.
  .OUTPUTS
  Nothing. Sets $ui.Acts, $ui.BOn, $ui.BMain, $ui.Always, $ui.Back, $ui.BackOn, $ui.First, $ui.Accept and the AcceptButton.
  #>
  param($C)
  $bs = @(@($C.Buttons | Where-Object { $_ -and [string]$_.Kind -ne 'primary' }) + @($C.Buttons | Where-Object { $_ -and [string]$_.Kind -eq 'primary' }))
  $ui.Acts = @(); $ui.First = $null; $ui.Accept = $null; $ui.BOn = @($false) * $ui.NB; $ui.BMain = @($false) * $ui.NB; $ui.Always = @($false) * $ui.NB
  $ui.Back = $C.Back; $ui.BackOn = ([bool]$C.Back -and -not $ui.RecOn); $ui.BackB.Visible = $ui.BackOn   # B6: Back at the left end of the action row
  $ui.BackB.Text = $(if ($ui.EscViews -contains [string]$C.View) { 'Back (Esc)' } else { 'Back' }); $ui.BackB.AccessibleName = $ui.BackB.Text   # "(Esc)" only where Esc works
  $ui.BoxNoEnter = [bool]$C.BoxNoEnter   # Enter in a box of this card answers nothing (the hand card's address box)
  for ($k = 0; $k -lt $ui.NB; $k++) {
    $b = $ui.B[$k]
    if ($k -ge $bs.Count) { $b.Visible = $false; $ui.Acts += $null; continue }
    $main = ([string]$bs[$k].Kind -eq 'primary'); $key = $(if ($main -and -not $C.NoAccept -and (& $ui.KeyFits ([string]$bs[$k].Text + ' (Enter)'))) { ' (Enter)' } else { '' })
    $b.Text = [string]$bs[$k].Text + $key; & $ui.Style $b ([string]$bs[$k].Kind)
    $b.Visible = $true; $ui.Acts += $bs[$k].Act; $ui.BOn[$k] = $true; $ui.BMain[$k] = $main; $ui.Always[$k] = [bool]$bs[$k].Always
    if ($b.Enabled -and -not $ui.First) { $ui.First = $b }; if ($b.Enabled -and -not $ui.Accept -and $main) { $ui.Accept = $b } }
  & $ui.Apart
  $ui.BtnRow.Visible = [bool]($bs.Count -or $ui.BackOn)
  $ui.Form.AcceptButton = $(if ($C.NoAccept) { $null } else { $ui.Accept }); $ui.AcceptOn = $ui.Form.AcceptButton }   # Enter = the primary button ("(Enter)" in its text)

# RADE window part 04, the hand-step text and the Record's first parts: builds the rich text of the numbered
# lines of a hand step and fits its box. Builds on 03-card.ps1 (the Guide box).
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# ---- The Record (F2): all checks by group with their result, the steps with a box each (they can be changed only
# before the run), and one text box with the files (New, Replace, Recycle), what the installs made, and the log.
$ui.Rec = New-Object System.Windows.Forms.TableLayoutPanel
$ui.Rec.Dock = 'Fill'; $ui.Rec.ColumnCount = 3; $ui.Rec.RowCount = 2
$ui.Rec.Padding = (& $ui.Pad ($ui.Z.Inset + $ui.Z.M) 0 ($ui.Z.Inset + $ui.Z.M) $ui.Z.G2); $ui.Rec.BackColor = $ui.C.White; $ui.Rec.Visible = $false
foreach ($w in @(36, 30, 34)) { [void]$ui.Rec.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', $w))) }
[void]$ui.Rec.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize'))); [void]$ui.Rec.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))
$ui.RecHead = New-Object System.Windows.Forms.FlowLayoutPanel
$ui.RecHead.AutoSize = $true; $ui.RecHead.WrapContents = $false; $ui.RecHead.BackColor = $ui.C.White; $ui.RecHead.Margin = (& $ui.Pad 0 0 0 4); & $ui.Ring $ui.RecHead
$ui.RecClose = & $ui.Btn 'compact'; $ui.RecClose.Text = 'Back (Esc)'; $ui.RecClose.AccessibleName = 'Close Details (Esc)'
$ui.RecTitle = & $ui.Label $ui.F.Body $ui.C.Navy 9; $ui.RecTitle.Margin = (& $ui.Pad 10 9 0 0); $ui.RecTitle.Text = 'Details'; $ui.RecTitle.Visible = $true
# R33 (the Administrator, 19 Nov 26): the check list and the step list are drawn, so they cannot be selected; Copy all puts the whole
# Record (the checks with each detail, the steps, the files and the log) on the clipboard as plain text ($ui.RecAll).
$ui.RecCopy = & $ui.Btn 'compact'; $ui.RecCopy.Text = 'Copy all'; $ui.RecCopy.AccessibleName = 'Copy all of Details as text'
[void]$ui.RecHead.Controls.Add($ui.RecClose); [void]$ui.RecHead.Controls.Add($ui.RecCopy); [void]$ui.RecHead.Controls.Add($ui.RecTitle)
$ui.RecChecks = New-Object System.Windows.Forms.Panel
$ui.RecChecks.Dock = 'Top'; $ui.RecChecks.BackColor = $ui.C.White; $ui.RecChecks.AccessibleRole = 'StaticText'; $ui.RecChecks.AccessibleName = 'Checks'
try { [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic, Instance').SetValue($ui.RecChecks, $true, $null) } catch { $null = $_ }
$ui.RecSteps = New-Object System.Windows.Forms.FlowLayoutPanel
$ui.RecSteps.Dock = 'Fill'; $ui.RecSteps.FlowDirection = 'TopDown'; $ui.RecSteps.WrapContents = $false
$ui.RecSteps.AutoScroll = $true; $ui.RecSteps.BackColor = $ui.C.White; $ui.RecSteps.Margin = (& $ui.Pad 0 0 16 0); $ui.RecSteps.AccessibleName = 'Steps'
$ui.RecText = New-Object System.Windows.Forms.TextBox
$ui.RecText.Dock = 'Fill'; $ui.RecText.Multiline = $true; $ui.RecText.ReadOnly = $true; $ui.RecText.ScrollBars = 'Vertical'; $ui.RecText.WordWrap = $true
$ui.RecText.Font = $ui.F.Mono; $ui.RecText.BackColor = $ui.C.White; $ui.RecText.ForeColor = $ui.C.Ink
$ui.RecText.BorderStyle = 'FixedSingle'; $ui.RecText.Margin = (& $ui.Pad 4 4 4 4); $ui.RecText.AccessibleName = 'Files, made list and log'
$ui.Rec.Controls.Add($ui.RecHead, 0, 0); $ui.Rec.SetColumnSpan($ui.RecHead, 3)
# The painted list sits in a panel that scrolls only when the list is taller than the window (many reused checks at 150 %).
$ui.RecScroll = New-Object System.Windows.Forms.Panel
$ui.RecScroll.Dock = 'Fill'; $ui.RecScroll.AutoScroll = $true; $ui.RecScroll.BackColor = $ui.C.White; $ui.RecScroll.Margin = (& $ui.Pad 4 0 24 0)
$ui.RecScroll.Controls.Add($ui.RecChecks)
$ui.Rec.Controls.Add($ui.RecScroll, 0, 1); $ui.Rec.Controls.Add($ui.RecSteps, 1, 1); $ui.Rec.Controls.Add($ui.RecText, 2, 1)
# The Fill parts go in first: they dock last, inside the light, the logo line, the bottom line and the edge bar.
foreach ($c in @($ui.Card, $ui.Rec, $ui.Bottom, $ui.Edge, $ui.Light, $ui.Band)) { $ui.Form.Controls.Add($c) }   # the band on top, the light line under it
$ui.Form.ResumeLayout($false); $ui.Form.PerformLayout()

# The lines of a hand step (the Administrator, 2026-11-17; R28 N4): a guide line that starts with "<digits>. " is numbered:
# its number right-aligned in the left column, its text wrapped in the right column; any other line follows the list,
# small and gray. All of it is ONE rich text box ($ui.Guide), so a person can select across lines. The plain parts stay in
# $ui.GuideNums, $ui.GuideTexts and $ui.GuideRest (the tests read them). RTF: figure spaces right-align the numbers, a tab
# and a hanging indent start the text column; sizes in twips from the pixels the box draws at.
$ui.SetSteps = { param($Guide)
  $ui.GuideNums = @(); $ui.GuideTexts = @(); $ui.GuideRest = @()
  foreach ($g in @($Guide)) { $g = [string]$g
    if ($g -match '^(\d+)\.\s+(\S.*)$') { $ui.GuideNums += ($Matches[1] + '.'); $ui.GuideTexts += $Matches[2] } elseif ($g.Trim()) { $ui.GuideRest += $g.Trim() } }
  $on = [bool](@($ui.GuideNums).Count -or @($ui.GuideRest).Count); $ui.Guide.Visible = $on
  if (-not $on) { try { $ui.Guide.Clear() } catch { $null = $_ }; return }
  & $ui.GuideBuild; & $ui.FitSteps }
# Escapes text for rich text (RTF): backslash and braces, and characters above 126 as \u codes. Takes the text; gives
# back the escaped text.
$ui.RtfEsc = { param([string]$T) $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $T.ToCharArray()) {
    $n = [int]$ch
    if ($ch -eq [char]92 -or $ch -eq '{' -or $ch -eq '}') { [void]$sb.Append([char]92).Append($ch) }
    elseif ($n -gt 126) { [void]$sb.Append('\u' + $(if ($n -gt 32767) { $n - 65536 } else { $n }) + '?') }
    elseif ($n -lt 32) { [void]$sb.Append(' ') }
    else { [void]$sb.Append($ch) }
  }
  return $sb.ToString() }
# Builds the rich text of the hand-step box from $ui.GuideNums, $ui.GuideTexts and $ui.GuideRest (numbers right-aligned
# in a column, then the small gray lines) and sets it into the box. Takes nothing; sets $ui.Guide.Rtf, $ui.GuideInkAt
# and the box's screen-reader text.
$ui.GuideBuild = {
  <#
  .SYNOPSIS
  Builds the RTF content for the hand-step instructions box.
  .DESCRIPTION
  Measures numbered step prefixes, generates right-aligned RTF paragraphs for numbered and unnumbered lines,
  assigns $ui.Guide.Rtf, and updates $ui.GuideInkAt and AccessibleDescription.
  .OUTPUTS
  None.
  #>
  $g = $null; try { $g = $ui.Guide.CreateGraphics() } catch { $null = $_ }
  $dpi = 96.0; try { if ($g -and [double]$g.DpiX -gt 0) { $dpi = [double]$g.DpiX } } catch { $null = $_ }
  # Turns screen pixels into twips (1/1440 inch) at the box's dpi. Takes the pixels; gives back a whole number.
  $tw = { param([double]$Px) [int][math]::Round($Px * 1440.0 / $dpi) }
  $nw = 0
  foreach ($n in @($ui.GuideNums)) {
    $w = 0
    try {
      $sz = New-Object System.Drawing.Size(100000, 0)
      $w = [int][System.Windows.Forms.TextRenderer]::MeasureText($g, $n, $ui.F.Body, $sz, [System.Windows.Forms.TextFormatFlags]'NoPadding, SingleLine').Width
    } catch { $w = [int][System.Windows.Forms.TextRenderer]::MeasureText($n, $ui.F.Body).Width }
    $nw = [math]::Max($nw, $w)
  }
  try { if ($g) { $g.Dispose() } } catch { $null = $_ }
  $cT = & $tw ($nw + (& $ui.Sc 8)); $g1 = & $tw (& $ui.Sc $ui.Z.G1); $g3 = & $tw (& $ui.Sc $ui.Z.G3)
  # Writes a color as the RTF color text (red, green, blue). Takes the color; gives back the text.
  $col = { param($C) '\red' + $C.R + '\green' + $C.G + '\blue' + $C.B + ';' }
  $fb = [int][math]::Round([double]$ui.F.Body.SizeInPoints * 2); $fs = [int][math]::Round([double]$ui.F.Small.SizeInPoints * 2)
  $paras = @(); $plain = 0; $wide = ''; $ui.GuideInkAt = 0
  # A shorter number gets figure spaces (as wide as a digit) in front: the numbers end on one line, and every line starts at
  # the left indent, so the first letter's place never depends on a tab (R28 job: a right tab was laid out late).
  $ml = 0; foreach ($n in @($ui.GuideNums)) { $ml = [math]::Max($ml, ([string]$n).Length) }
  for ($i = 0; $i -lt @($ui.GuideNums).Count; $i++) {
    $n = [string]$ui.GuideNums[$i]; $t = [string]$ui.GuideTexts[$i]; $pad = ([string][char]0x2007) * ($ml - $n.Length)
    if ($n.Length -eq $ml -and -not $wide) { $wide = $n; $ui.GuideInkAt = $plain }   # a widest number: its first letter is on the card edge
    $paras += ('\pard\li' + $cT + '\fi-' + $cT + '\tx' + $cT + '\sb' + $(if ($i) { $g1 } else { 0 }) + '\cf1\fs' + $fb + ' ' + (& $ui.RtfEsc ($pad + $n)) + '\tab ' + (& $ui.RtfEsc $t))
    $plain += 2 + $pad.Length + $n.Length + $t.Length }   # padding, number, tab, text, and the line break
  for ($i = 0; $i -lt @($ui.GuideRest).Count; $i++) {
    $sb = $(if ($i -or @($ui.GuideNums).Count) { $(if ($i) { 0 } else { $g3 }) } else { 0 })
    $paras += ('\pard\li0\fi0\sb' + $sb + '\cf2\fs' + $fs + ' ' + (& $ui.RtfEsc ([string]$ui.GuideRest[$i])))
  }
  if (-not @($ui.GuideNums).Count) { $ui.GuideInkAt = 0 }
  $fontName = & $ui.RtfEsc ([string]$ui.F.Body.Name)
  $rtf = '{\rtf1\ansi\ansicpg1252\deff0\uc1{\fonttbl{\f0\fnil ' + $fontName + ';}}{\colortbl ;' + (& $col $ui.C.Navy) + (& $col $ui.C.Gray) + '}\f0 ' + ($paras -join "\par`r`n") + '}'
  # its final width first: a text laid out at the default 100 px kept a wrong place for its first letter (R28 job)
  if ([int]$ui.ContentW -gt 0 -and $ui.Guide.Width -ne [int]$ui.ContentW) { $ui.Guide.Width = [int]$ui.ContentW }
  $ui.GuideH = 0; $ui.Guide.Rtf = $rtf
  $accLines = @(for ($i = 0; $i -lt @($ui.GuideNums).Count; $i++) { [string]$ui.GuideNums[$i] + ' ' + [string]$ui.GuideTexts[$i] }) + @($ui.GuideRest)
  $ui.Guide.AccessibleDescription = ($accLines -join ' ') }
# How tall the text is: the rich text box says it (ContentsResized), or the place of its last letter plus one line.
$ui.GuideNeed = { $h = [int]$ui.GuideH
  try {
    $n = [int]$ui.Guide.TextLength
    if ($n -gt 0) {
      $pt = $ui.Guide.GetPositionFromCharIndex($n - 1); $lf = $(if (@($ui.GuideRest).Count) { $ui.F.Small } else { $ui.F.Body })
      $h = [math]::Max($h, [int]$pt.Y + [int][System.Windows.Forms.TextRenderer]::MeasureText('Ag', $lf).Height)
    }
  } catch { $null = $_ }
  return $h }
# Sets the hand-step box to its width and the height its text needs. Takes nothing; changes the box size and does
# nothing while it is already fitting.
$ui.GuideFit = { if ($ui.InGuideFit) { return }; $ui.InGuideFit = $true
  try {
    if ($ui.Guide.Visible) {
      $w = [int]$ui.ContentW; $h = [math]::Max(1, (& $ui.GuideNeed) + (& $ui.Sc 2))
      if ($ui.Guide.Width -ne $w) { $ui.GuideH = 0; $ui.Guide.Width = $w; $h = [math]::Max(1, (& $ui.GuideNeed) + (& $ui.Sc 2)) }
      if ($ui.Guide.Height -ne $h) { $ui.Guide.Height = $h }
    }
  } catch { $null = $_ } finally { $ui.InGuideFit = $false } }
# Where the ink of the guide's first number starts in the box: the place of the letter (as the box lays it out) plus the
# letter's own left side (drawn once into a bitmap). A rich text box cannot be drawn into a bitmap, so $ui.Ink cannot measure it.
$ui.Bearing = { param([string]$Ch, $F)
  $k = 'bearing|' + $F.Name + '|' + $F.SizeInPoints + '|' + $Ch; if ($ui.Inks.ContainsKey($k)) { return [int]$ui.Inks[$k] }; $v = 0
  try { $bm = New-Object System.Drawing.Bitmap(160, 160); try { $gb = [System.Drawing.Graphics]::FromImage($bm); $gb.Clear([System.Drawing.Color]::White)
      $fmt = [System.Windows.Forms.TextFormatFlags]'NoPadding'
      [System.Windows.Forms.TextRenderer]::DrawText($gb, $Ch, $F, (New-Object System.Drawing.Point(0, 0)), [System.Drawing.Color]::Black, $fmt)
      $gb.Dispose(); $hit = -1
      for ($x = 0; $x -lt 80 -and $hit -lt 0; $x++) { for ($y = 0; $y -lt 160; $y++) { $px = $bm.GetPixel($x, $y); if ($px.R + $px.G + $px.B -lt 600) { $hit = $x; break } } }
      if ($hit -ge 0) { $v = $hit; $ui.Inks[$k] = $v } } finally { $bm.Dispose() } } catch { $null = $_ }
  return $v }
# Gives the x place where the ink of the first number starts in the hand-step box (the letter's place plus its side
# bearing); 0 when it cannot be read. Takes nothing.
$ui.GuideInk = { try { $i = [int]$ui.GuideInkAt; $t = [string]$ui.Guide.Text; if ($i -ge $t.Length) { $i = 0 }; if (-not $t) { return 0 }
    $f = $(if (@($ui.GuideNums).Count) { $ui.F.Body } else { $ui.F.Small }); return ([int]$ui.Guide.GetPositionFromCharIndex($i).X + (& $ui.Bearing ([string]$t[$i]) $f)) } catch { return 0 } }
# Fits the hand-step box after its text or the window width changed. Takes nothing; calls $ui.GuideFit.
$ui.FitSteps = { & $ui.GuideFit }
# Lays the card out again for the window's size: text widths, the choices, the step boxes and the buttons.
$ui.Fit = {
  <#
  .SYNOPSIS
  Reflows card column widths, wraps labels, sizes inputs and buttons, and re-runs layout squeeze checks.
  .DESCRIPTION
  Computes content column width from card client width and layout caps, updates MaximumSize/MinimumSize on rows,
  re-measures option rows and running step lists, and invokes $ui.Squeeze.
  .OUTPUTS
  None.
  #>
  if (-not $ui.Scaled) { return }   # R1 review: a size set while Windows Forms scales the form would be scaled again
  $W = [int]$ui.Card.ClientSize.Width; $col = [math]::Min([int]($W * $ui.Layout.Share / 100), [int](& $ui.Sc $ui.Layout.MaxW)); $side = [math]::Max(0, [int](($W - $col) / 2))
  try { if (@($ui.CardCols).Count -eq 3 -and ([int]$ui.CardCols[0].Width -ne $side -or [int]$ui.CardCols[1].Width -ne $col)) {
      $ui.CardCols[0].SizeType = 'Absolute'; $ui.CardCols[0].Width = $side; $ui.CardCols[1].SizeType = 'Absolute'; $ui.CardCols[1].Width = $col
      $ui.CardCols[2].SizeType = 'Percent'; $ui.CardCols[2].Width = 100 } } catch { $null = $_ }   # stand-in types or a form being closed: the card keeps its last columns
  $cw = [math]::Max((& $ui.Sc 240), $col - (& $ui.Sc 4)); $ui.ContentW = $cw
  foreach ($l in @($ui.P[0], $ui.P[1], $ui.P[2], $ui.P[3], $ui.PathT, $ui.Note, $ui.Help, $ui.Foot, $ui.Close)) { & $ui.SetWrap $l $cw }
  & $ui.SetWrap $ui.Kick ($cw - $(if ($ui.Chip.Visible) { [int]$ui.Chip.PreferredSize.Width + (& $ui.Sc $ui.Z.G3) } else { 0 }))   # the line in capitals beside the YOUR TURN chip
  & $ui.SetWrap $ui.Sent ($cw - (& $ui.Sc 44))
  $mm = & $ui.Sc $ui.Z.M
  foreach ($r in @($ui.BtnRow, $ui.LinkRow, $ui.TestRow, $ui.FieldRow)) { $r.MaximumSize = New-Object System.Drawing.Size(($cw + 2 * $mm), 0) }
  # B3: the action row is as wide as the column, so the primary can stand at its right end (an auto-sized row wraps at its own width)
  $ui.BtnRow.MinimumSize = New-Object System.Drawing.Size(($cw + 2 * $mm), 0)
  $ui.ErrBox.Width = [math]::Min((& $ui.Sc $ui.Z.FieldL), ($cw - 2 * $mm))
  & $ui.BandFit   # the band: full size or half size for this width (02-fixed-parts.ps1)
  try {
    $lh = [math]::Max([int][System.Windows.Forms.TextRenderer]::MeasureText('Ag', $ui.Kick.Font).Height + (& $ui.Sc 2), [int]$ui.Chip.PreferredSize.Height)
    if ($ui.Head.MinimumSize.Height -ne $lh) { $ui.Head.MinimumSize = New-Object System.Drawing.Size(0, $lh) }
  } catch { $null = $_ }   # L1: the header row keeps its height on a card with no line or no chip
  foreach ($l in @($ui.RightL, $ui.StepTime, $ui.StepFrac, $ui.PctL)) { & $ui.FixW $l }   # labels of changing values: one size from their widest value
  & $ui.FitRow; & $ui.Apart; & $ui.FitSent; & $ui.FitSteps; & $ui.FitEdges; & $ui.FitBar; & $ui.AlignRows
  foreach ($o in @($ui.Opts.Controls)) { $o.Width = $cw; try { $o.Height = (& $ui.OptPlan $o.Tag $cw).H } catch { $null = $_ } }
  if ($ui.View -eq 'run' -and $ui.Running) { & $ui.PlaceRuns }   # the step lists take the room this size has
  & $ui.Squeeze }

# RADE window part 08, a hand step: the cards for a step the user does by hand (It failed, questions,
# open the address) and $script:guideUi, which the engine waits in until the user answers.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# ---- A step you do by hand, or a check you answer by looking (R13, R14, R18): the card holds the numbered lines, the
# address (it can be changed; it is remembered in Config), the file path on the clipboard, and the answers. The engine
# waits in $script:guideUi until an answer is set: OK = Done or Yes, No, Abort = It failed (with the error text),
# Cancel = Skip, Not now, or the window closed. Enter = Done (plan engine-v48 step 4; before: a click only).
$ui.VHand = {
  <#
  .SYNOPSIS
  Displays the hand-step instruction card for the active manual step or look-and-answer check.
  .DESCRIPTION
  Formats clipboard guidance, action buttons respecting Hide flags, optional URL field, and sets card focus.
  .OUTPUTS
  None.
  #>
  $st = $ui.G.Step; $file = [string]$ui.G.File; $hide = @($st.Hide)
  $clip = $(if (-not $file) { '' } elseif (Copy-TextToClipboard $file) { 'The path of ' + $st.File + ' is on the clipboard.' }
    else { 'Select "Copy file path" to put the path of ' + $st.File + ' on the clipboard.' })
  $two = $(if ($st.NoText) { @{ Text = [string]$st.NoText; Act = { $ui.Answer = 'No' } } } else { @{ Text = 'It failed'; Act = { & $ui.VHandFail } } })
  # R28 N1: the address row only when the step has an address (or a saved one it can take); N6: the file's full path on the card.
  $addr = [bool]($ui.GUrl -or $st.UrlConfig); $dw = $(if ($st.DoneText) { [string]$st.DoneText } else { 'Done' })
  # E1 (the Administrator, 2026-11-19): the step's "hide" takes buttons off the card; one button always stays (the build checks it).
  $one = @{ Text = $dw; Kind = 'primary'; Act = { $ui.Answer = 'OK' } }
  $three = @{ Text = $(if ($st.SkipText) { [string]$st.SkipText } else { 'Skip' }); Act = { $ui.Answer = 'Cancel' } }
  $bs = @($(if ($hide -notcontains 'done') { $one }), $(if ($hide -notcontains 'skip') { $three }), $(if ($hide -notcontains 'failed') { $two }))   # Cards v2: Done, then Skip and It failed
  $close = $(if ($hide -contains 'done') { '' } elseif ($addr) { 'When you finish in the browser, come back to this window and select "' + $dw + '".' }
    else { 'When you finish, select "' + $dw + '".' })
  $handKick = $(if ($ui.Running -and $ui.StepI) { 'Step ' + $ui.StepI + ' of ' + $ui.StepN } else { '' })
  $handField = $(if ($addr) { @{ Label = 'Address'; Text = $ui.GUrl; Name = 'Address to open'; Button = 'Open in browser'; Act = { & $ui.OpenUrl } } } else { $null })
  # Cards v2 (critique change 3): Enter = Done ("Done (Enter)"): the focus is on Done (a focused button takes Enter itself)
  & $ui.SetCard @{ View = 'hand'; Light = 'you'; Kicker = $handKick; Sentence = (Get-StepTitle $st)
    P = @([string]$st.Note); Lines = @($st.Guide); Close = $close
    Field = $handField; Path = $file; Links = [bool]$file; Note = $clip
    Buttons = $bs; BoxNoEnter = $true; Focus = $(if ($addr) { 'main' } else { 'text' }) } }
# Shows the card where the user pastes the error of a hand step that failed; its button sets the answer to Abort. Takes
# nothing.
$ui.VHandFail = {
  $failBtn = @{ Text = 'Report the failure'; Kind = 'primary'; Act = { $script:guideError = [string]$ui.ErrBox.Text; $ui.Answer = 'Abort' } }
  & $ui.SetCard @{ View = 'handfail'; Light = 'you'; Kicker = 'It failed'; Sentence = 'What did the error say?'
    P = @('Paste the error message here. Do not include names or a site address.'); Err = $true
    Buttons = @($failBtn); Back = { & $ui.VHand }; NoAccept = $true; Focus = 'err' } }
# A question of a hand step (manifest "answers"), after Done: the prompt is the sentence; yes/no and pick answer with
# one button per word, a text with one line (10,000 characters at most; empty is allowed; R28: kept whole) and "Continue". No Back.
$ui.ReplyActs = @({ $ui.Reply = [string]$ui.B[0].Text }, { $ui.Reply = [string]$ui.B[1].Text }, { $ui.Reply = [string]$ui.B[2].Text }, { $ui.Reply = [string]$ui.B[3].Text })
$ui.VAnswer = {
  <#
  .SYNOPSIS
  Shows one question of a hand step (text, yes or no, or a pick). The first sentence of the prompt is the headline.
  .DESCRIPTION
  Yes / no and a pick answer with one plain button per choice. When a choice does not fit the widest button (E5, R42
  plan; $ui.AnswerFits), each choice is a full-width choice row instead, so no answer text is cut. A text question has
  the box "Your answer" and "Continue". No Back.
  .PARAMETER Q
  The question (Kind, Prompt, Choices).
  .PARAMETER I
  Its number.
  .PARAMETER N
  The count of questions.
  .OUTPUTS
  None; the answer is set in $ui.Reply.
  #>
  param($Q, [int]$I, [int]$N)
  $ui.Reply = $null
  $ansKick = $(if ($ui.Running -and $ui.StepI) { 'Step ' + $ui.StepI + ' of ' + $ui.StepN + $dot } else { '' }) + 'Question ' + $I + ' of ' + $N
  $c = @{ View = 'answer'; Light = 'you'; Kicker = $ansKick; Sentence = [string]$Q.Prompt }
  # The prompt's first sentence (up to the first "?", "." or ":" followed by a space or the end) is the headline; the rest
  # is a body line under it (the Administrator, 2026-11-15, rework B). A first sentence too long for one line shrinks ($ui.FitSent).
  if ([string]$Q.Prompt -match '^(.+?[?.:])(?:\s+(\S.*))?$') { $c.Sentence = $Matches[1]; if ($Matches[2]) { $c.P = @($Matches[2].Trim()) } }
  if ($Q.Kind -eq 'text') { $c.Field = @{ Label = 'Your answer'; Text = ''; Name = [string]$Q.Prompt; Max = 10000; Above = $true }
    $c.Focus = 'field'; $c.Buttons = @(@{ Text = 'Continue'; Kind = 'primary'; Act = { $ui.Reply = [string]$ui.Field.Text } }) }
  else { $ws = @($(if ($Q.Kind -eq 'yesno') { 'Yes', 'No' } else { $Q.Choices })); $ui.AnswerWords = @($ws | ForEach-Object { [string]$_ })
    if (& $ui.AnswerFits $ws) { $c.Buttons = @(for ($k = 0; $k -lt $ws.Count; $k++) { @{ Text = [string]$ws[$k]; Act = $ui.ReplyActs[$k] } }) }
    else {   # E5 (R41: "needs 416 has 360"): a choice too long for the widest button; each choice is a full-width row, no text is cut
      $c.Options = @(for ($k = 0; $k -lt $ws.Count; $k++) { @{ Index = $k; Name = [string]$ws[$k]; Ver = '' } })
      # A click on choice row j answers with that choice's own text. Takes the row's index.
      $c.OnOption = { param($j) $ui.Reply = [string]$ui.AnswerWords[$j] }
      $c.P = @(@($c.P) + @('You cannot change the answer after the click. Click the row with your answer. You then see the next card.') | Where-Object { $_ }) } }
  & $ui.SetCard $c }
# Says whether every answer choice fits the widest action button (UI standard v1, B1: 240 x 40), measured in the button
# font with the button's padding, as $ui.BtnSize measures it. Takes the choices; gives back $true or $false.
$ui.AnswerFits = { param($Words)
  $max = & $ui.Sc $ui.Z.WideW; $pad = & $ui.Sc (2 * $ui.Z.G2)
  foreach ($w in @($Words)) {
    try {
      if ([int][System.Windows.Forms.TextRenderer]::MeasureText([string]$w, $ui.F.SmallB).Width + $pad -gt $max) { return $false }
    } catch { $null = $_ }   # no measure: buttons, as before
  }
  return $true }
# E2 (the Administrator, 2026-11-19): after an answer that the manifest marks as a failure ("failOn"), the card where the
# user pastes the error text. Its button keeps the text in $script:guideError and sets $ui.Reply. No Back. Takes nothing.
$ui.VAnswerFail = {
  $ui.Reply = $null
  $afKick = $(if ($ui.Running -and $ui.StepI) { 'Step ' + $ui.StepI + ' of ' + $ui.StepN + $dot } else { '' }) + 'It failed'
  $afP = 'Paste the error message here. Do not include names or a site address. If there is no message, leave the box empty.'
  & $ui.SetCard @{ View = 'answerfail'; Light = 'you'; Kicker = $afKick; Sentence = 'What did the error say?'
    P = @($afP); Err = $true
    Buttons = @(@{ Text = 'Continue'; Kind = 'primary'; Act = { $script:guideError = [string]$ui.ErrBox.Text; $ui.Reply = 'ok' } }); NoAccept = $true; Focus = 'err' } }
# Waits until the user answers the card that is shown ($ui.Reply is set) or the window closes. Takes nothing.
$ui.WaitReply = { while ($null -eq $ui.Reply -and -not $script:closing -and -not $ui.Form.IsDisposed) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25 } }
# Asks the questions of a hand step, one card each, in order; a question with "showIf" shows only after one of its
# answers to the earlier question (E3). Keeps the answers in $script:guideAnswers and the answers that mean a failure
# in $script:guideFail; after the first of those it asks for the error text. Takes the step; gives back nothing.
$ui.AskAnswers = { param($Step)
  $qs = @($Step.Answers | Where-Object { $_ })
  for ($i = 0; $i -lt $qs.Count -and -not $script:closing -and -not $ui.Form.IsDisposed; $i++) {
    $q = $qs[$i]; if ($q.ShowKey -and @($q.ShowIn) -cnotcontains [string]$script:guideAnswers[[string]$q.ShowKey]) { continue }
    $null = & $ui.VAnswer $q ($i + 1) $qs.Count; $null = & $ui.WaitReply
    if ($null -eq $ui.Reply) { return }
    $v = [string]$ui.Reply; $script:guideAnswers[[string]$q.Key] = $v
    if (@($q.FailOn) -ccontains $v) { $script:guideFail += ([string]$q.Key + ': ' + $v); if (@($script:guideFail).Count -eq 1) { $null = & $ui.VAnswerFail; $null = & $ui.WaitReply } }
  } }
# Opens the address in the box in the browser and remembers it (also in its file). Takes nothing; says so when the
# address does not start with https://, or is not on the host of the step's own address (the Administrator, 2026-11-17).
$ui.OpenUrl = {
  $u = $ui.Field.Text.Trim()
  if ($u -notmatch '^https://') { & $ui.Say1 'The address must start with https://'; return }
  $fixed = [string]$ui.G.Step.Url
  if (-not $fixed) { & $ui.Say1 'This step gives no address of its own, so RADE cannot open one from here.'; return }
  if (-not (Test-SameHost $u $fixed)) { & $ui.Say1 ('The address must be on ' + ([uri]$fixed).Host + ', like the address this step gives.'); return }
  $ui.GUrl = $u; try { if ($ui.G.UrlFile) { Set-Content -LiteralPath $ui.G.UrlFile -Value $u -Encoding UTF8 } } catch { $null = $_ }
  try {
    Start-Process -FilePath $u; & $ui.Say1 'Opened in your browser. Do the steps on this card, then come back to this window.'
  } catch { & $ui.Say1 ('The browser could not be opened: ' + $_.Exception.Message) } }
$ui.CopyPathB.Add_Click({
  $msg = $(if (Copy-TextToClipboard ([string]$ui.G.File)) { 'File path copied. Press Ctrl+V in the "File name" box' } else { 'The clipboard is busy. Select "Copy file path" again.' })
  & $ui.Say1 $msg })
$ui.PageB.Add_Click({ try { Start-Process -FilePath $homeUrl } catch { & $ui.Say1 'The browser could not be opened. Open the repository page from your bookmarks.' } })
$ui.ShowFileB.Add_Click({ if ($ui.G.File) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $ui.G.File + '"') } })
# Shows a hand step and waits until the user answers, then asks the step's questions; a step with "answersOnly" shows its
# questions at once (E2). Takes the step, the file path, the address and the address file; gives back OK, Abort or Cancel.
$script:guideUi = {
  <#
  .SYNOPSIS
  Displays a manual guide step in the UI and waits for completion, failure report, or cancellation.
  .DESCRIPTION
  Renders the hand card (unless AnswersOnly), collects follow-up question answers on OK, restores busy state,
  and returns OK, Abort, or Cancel.
  .PARAMETER Step
  The step object containing guide instructions, flags, and optional follow-up answers.
  .PARAMETER File
  Optional target file path associated with the step.
  .PARAMETER Url
  Initial URL to display or open for the step.
  .PARAMETER UrlFile
  Optional path where edited step URLs are persisted.
  .OUTPUTS
  String result ('OK', 'Abort', or 'Cancel').
  #>
  param($Step, [string]$File, [string]$Url, [string]$UrlFile)
  $ui.G = @{ Step = $Step; File = $File; UrlFile = $UrlFile }; $ui.GUrl = $Url; $script:guideError = ''; $ui.Answer = ''; $was = $ui.Busy; $ui.Busy = $false
  $script:guideAnswers = @{}; $script:guideFail = @()
  if ($Step.AnswersOnly) { $ui.Answer = 'OK'; $null = & $ui.ToFront }
  else { $null = & $ui.VHand; $null = & $ui.ToFront
    while (-not $ui.Answer -and -not $script:closing -and -not $ui.Form.IsDisposed) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 25 } }
  # After Done (not after "It failed" or Skip): the step's questions, one card each, in order. Their time is the step's time.
  if ($ui.Answer -eq 'OK') { $null = & $ui.AskAnswers $Step }
  $ui.Busy = $was; $res = [string]$ui.Answer; if (-not $res) { $res = 'Cancel' }
  if ($Step.AnswersOnly -and ($script:closing -or $ui.Form.IsDisposed)) { $res = 'Cancel' }   # the window closed before the last answer
  $ui.Guides = @($ui.Guides | Where-Object { $_ -ne [string]$Step.Name })
  if ($ui.Running -and -not $script:closing) { $null = & $ui.ShowRun }
  return $res }
# L4 (the Administrator, 2026-11-19): the last card of a test round, "Anything else about this round or the app?". The
# text is optional and takes up to 10,000 characters, like every text answer (R34, R7); a pasted block becomes one line ($ui.PasteLine);
# the engine puts it into the report under the line "Other feedback:" (Get-RoundFeedback). Takes
# nothing; waits for Continue; gives back the text ('' when the window closed).
$script:feedbackUi = {
  <#
  .SYNOPSIS
  Displays the end-of-round optional feedback prompt in test rounds and returns the entered text.
  .DESCRIPTION
  Holds the final step display briefly, shows the feedback card, waits for user response, restores busy state,
  and resumes the Run card view.
  .OUTPUTS
  String feedback entered by the user, or empty string when closed.
  #>
  $null = & $ui.HoldStep   # L8: the last step stays on the Run card for its minimum time first
  $was = $ui.Busy; $ui.Busy = $false; $ui.Reply = $null; $ui.Asked = $true
  $fbField = @{ Label = 'Your answer'; Text = ''; Name = 'Anything else about this round or the app?'; Max = 10000; Above = $true }
  $null = & $ui.SetCard @{ View = 'feedback'; Light = 'you'; Kicker = 'Last question'; Sentence = 'Anything else about this round or the app?'
    P = @('This is optional. Do not type names or addresses.'); Field = $fbField; Focus = 'field'
    Buttons = @(@{ Text = 'Continue'; Kind = 'primary'; Act = { $ui.Reply = [string]$ui.Field.Text } }) }
  $null = & $ui.ToFront; $null = & $ui.WaitReply
  $ui.Busy = $was; $text = [string]$ui.Reply
  if ($ui.Running -and -not $script:closing) { $null = & $ui.ShowRun }
  return $text }
# ---- Feedback on every card (UI standard v1, B13; the Administrator, 2026-11-20). In a test round the bottom line has the
# link "Feedback" ($ui.FeedB) on every card. It takes a picture of the window as it is (Control.DrawToBitmap of the form),
# then shows a card with a comment box; Save writes the comment (masked as a text answer is) and the picture as
# feedback-NN.txt and feedback-NN.png into Rounds\<round>\Feedback, then shows the card it came from again. Feedback is a
# subfolder of the round's results folder: the e-mail draft attaches only the files at the top of the results folder, and
# the picture shows the real profile path (DoD365 boundary, AGENTS.md "Project rules"), so it stays on this computer.
# Gives back $true when the bundle's chosen (or only) application is a test one: the link shows then. Takes nothing.
$ui.NoteOn = {
  try {
    if ($ui.Picked) { return [bool](-not (Test-Deploy)) }
    return [bool](@($apps | Where-Object { [string]$_.Mode -ne 'deploy' }).Count)
  } catch { return $false } }   # no answer: no link
$ui.NoNoteViews = @('note')
$ui.VNote = {
  <#
  .SYNOPSIS
  Shows the feedback card for the card on screen, with a picture of the window taken first.
  .DESCRIPTION
  Does nothing while RADE is busy or a run is on (the Run card keeps updating), in the Record and on the feedback card
  itself. The picture is kept in $ui.NoteShot until Save or Back; no picture (a host that cannot draw the form) is allowed.
  .OUTPUTS
  Nothing.
  #>
  if ($ui.Busy -or $ui.Running -or $ui.RecOn -or -not $ui.CardNow -or [string]$ui.View -in $ui.NoNoteViews) { return }
  try { if ($ui.NoteShot) { $ui.NoteShot.Dispose() } } catch { $null = $_ }   # an old picture (the card was left by F1, F2 or Close)
  $ui.NoteFor = $ui.CardNow; $ui.NoteShot = $null; $ui.NoteKeep = @{ Field = [string]$ui.Field.Text; Err = [string]$ui.ErrBox.Text }   # typed text comes back
  try { $w = [int]$ui.Form.Width; $h = [int]$ui.Form.Height; $bm = New-Object System.Drawing.Bitmap($w, $h)
    $ui.Form.DrawToBitmap($bm, (New-Object System.Drawing.Rectangle(0, 0, $w, $h))); $ui.NoteShot = $bm } catch { $null = $_ }   # no picture: the comment alone
  $noteP = 'RADE saves your comment and a picture of the window in the Feedback folder of this round. They stay on this computer and are not attached to the results e-mail.'
  $saveBtn = @{ Text = 'Save'; Kind = 'primary'; Act = { & $ui.Say1 (& $ui.SaveNote ([string]$ui.ErrBox.Text)); & $ui.NoteBack $false } }
  & $ui.SetCard @{ View = 'note'; Kicker = 'Feedback'; Sentence = 'What do you want to tell us about this card?'
    P = @($noteP, 'Do not type names or addresses.'); Err = $true
    Buttons = @($saveBtn); Back = { & $ui.NoteBack $true }; NoAccept = $true; Focus = 'err' } }
$ui.SaveNote = {
  <#
  .SYNOPSIS
  Writes one feedback comment and the picture of $ui.NoteShot into Rounds\<round>\Feedback (UI standard v1, B13).
  .DESCRIPTION
  The files are feedback-NN.txt (the card, the time, the window size and scale, then the comment, masked as a text answer
  is) and feedback-NN.png; NN is the first number not yet used. A picture that cannot be saved leaves the comment saved.
  .PARAMETER Text
  The comment as typed.
  .OUTPUTS
  The line the card shows: what was saved, or why nothing could be saved (masked).
  #>
  param([string]$Text)
  try { $dir = Join-Path (Join-Path (Join-Path (Get-BasePath) 'Rounds') $round) 'Feedback'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop }
    $n = 1; while (Test-Path -LiteralPath (Join-Path $dir ('feedback-{0:D2}.txt' -f $n))) { $n++ }; $stem = 'feedback-{0:D2}' -f $n
    $win = [string]$ui.Form.ClientSize.Width + ' x ' + $ui.Form.ClientSize.Height + ' at ' + [int][math]::Round($ui.Dpi / 96.0 * 100) + ' %' + $(if ($ui.High) { ', contrast theme' } else { '' })
    $lines = @(('Card: ' + [string]$ui.NoteFor.View), ('Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')), ('Window: ' + $win), '', (ConvertTo-UserText $Text))
    [System.IO.File]::WriteAllText((Join-Path $dir ($stem + '.txt')), (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    $pic = ''; $png = ('System.Drawing.Imaging.ImageFormat' -as [type])
    if ($ui.NoteShot) { try { $ui.NoteShot.Save((Join-Path $dir ($stem + '.png')), $png::Png); $pic = ' and its picture' } catch { $null = $_ } }   # no picture file: the comment is saved
    return ('Feedback saved: ' + $stem + $pic + ' in the Feedback folder of round ' + $round + '.')
  } catch { return ('The feedback could not be saved: ' + (ConvertTo-Masked ([string]$_.Exception.Message))) } }
# Shows the card the feedback came from again and lets the picture go. Takes $true when Back was selected (the note line
# is cleared then).
$ui.NoteBack = { param([bool]$Cancel)
  $say = [string]$ui.Note.Text; try { if ($ui.NoteShot) { $ui.NoteShot.Dispose() } } catch { $null = $_ }; $ui.NoteShot = $null   # a picture that is gone: nothing to free
  if ($ui.NoteFor) { & $ui.SetCard $ui.NoteFor; if ($ui.NoteKeep) { $ui.Field.Text = $ui.NoteKeep.Field; $ui.ErrBox.Text = $ui.NoteKeep.Err }; if (-not $Cancel) { & $ui.Say1 $say } } }

# RADE window part 09, the Record (F2): lists the checks, the steps and the log, and closes it again.
# Builds on the Record parts in 04-record-parts.ps1.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# ---- The Record
# Returns the text color of a state in the Record (green PASSED, red FAILED or NEEDS REVIEW, ...). Takes the state.
$ui.StateInk = { param([string]$St)   # the word is always shown: never color alone
  $(if ($St -eq 'PASSED') { $ui.C.GreenInk } elseif ($St -in 'FAILED', 'NEEDS REVIEW') { $ui.C.Red }
    elseif ($St -in 'WARNING', 'RUNNING') { $ui.C.Navy } else { $ui.C.Gray }) }
$ui.RecRows = {
  <#
  .SYNOPSIS
  Builds the grouped check rows to display in the Record (Details) check list.
  .DESCRIPTION
  Collects check IDs for the chosen app or base checks, inserts uppercase group headers, and attaches
  detail and remediation lines.
  .OUTPUTS
  Array of row hashtables with Head or Name/State/More properties.
  #>
  $ids = $(if ($ui.Picked) { @($script:appChecks) } else { @($ui.BaseIds) }); $rows = @(); $g0 = ''
  foreach ($id in $ids) {
    $d = Get-CheckDef $id; $r = $(if ($ui.Picked) { $script:checkResults[$id] } else { $ui.BaseRes[$id] }); if (-not $r) { $r = @{ State = 'NOT RUN'; Detail = ''; Fix = '' } }
    if ([string]$d.Group -ne $g0) { $g0 = [string]$d.Group; $rows += @{ Head = $g0.ToUpperInvariant() } }
    $nm = [string]$d.Short; if (-not $nm) { $nm = [string]$d.Name }
    # not passed: what was found, then what to do; reused (Get-SavedCheck): "Last check: 17 Nov 26", then what it found; passed (R33): what it found
    $more = $(if ($r.State -ne 'PASSED' -or $r.Saved) { @(@($r.Detail, $r.Fix) | Where-Object { $_ }) } else { @(@($r.Detail) | Where-Object { $_ }) })
    $rows += @{ Name = $nm; State = [string]$r.State; More = $more }
  }
  return $rows }
$ui.RecPlan = {
  <#
  .SYNOPSIS
  Computes vertical layout geometry for the Record check list at a given width.
  .DESCRIPTION
  Measures status column width, wraps check names and detail lines up to two lines each,
  and returns row coordinates plus total height.
  .PARAMETER w
  Available width in pixels for the check list panel.
  .OUTPUTS
  Hashtable with Rows, Tall, Sw, Lw, In, H0, and Hc.
  #>
  param([int]$w)
  $h0 = [System.Windows.Forms.TextRenderer]::MeasureText('Ag', $ui.F.Small).Height; $hc = [System.Windows.Forms.TextRenderer]::MeasureText('Ag', $ui.F.SmallB).Height; $v = & $ui.Sc 3
  $sw = 0; foreach ($t in 'NOT RUN', 'WARNING', 'RUNNING', 'PASSED', 'FAILED', 'fallback') { $sw = [math]::Max($sw, [System.Windows.Forms.TextRenderer]::MeasureText($t, $ui.F.SmallB).Width) }
  $sw += & $ui.Sc 4; $lw = [math]::Max((& $ui.Sc 60), ($w - $sw - (& $ui.Sc 8))); $in = & $ui.Sc 12; $y = 0; $rows = @()
  foreach ($r in @($ui.RecData)) {
    if ($r.Head) { $y += & $ui.Sc 8; $rows += @{ R = $r; Y = $y; H = ($h0 + $v) }; $y += $h0 + $v; continue }
    $word = [string]$r.State; $qual = ''; if ($word -match '^(.+?) \((.+)\)$') { $word = $Matches[1]; $qual = $Matches[2] }
    $nh = (& $ui.Rows ([string]$r.Name) $ui.F.Small $lw $h0 2) * $h0 + $v; if ($qual) { $nh = [math]::Max($nh, (2 * $hc + $v)) }
    $more = @(); $my = $y + $nh
    foreach ($m in @($r.More)) { $mh = (& $ui.Rows ([string]$m) $ui.F.Small ($lw - $in) $h0 2) * $h0 + $v; $more += @{ T = [string]$m; Y = $my; H = $mh }; $my += $mh }
    $rows += @{ R = $r; Y = $y; H = $nh; Word = $word; Qual = $qual; More = $more }; $y = $my
  }
  return @{ Rows = $rows; Tall = $y; Sw = $sw; Lw = $lw; In = $in; H0 = $h0; Hc = $hc } }
$ui.RecChecks.Add_Paint({
  try {
    $g = $_.Graphics; $g.Clear($ui.C.White); $w = $this.ClientSize.Width; $pl = & $ui.RecPlan $w; $sw = $pl.Sw; $lw = $pl.Lw
    $wrap = 'Left, Top, NoPrefix, WordBreak, EndEllipsis, TextBoxControl'
    foreach ($q in @($pl.Rows)) {
      $r = $q.R
      if ($r.Head) { & $ui.Word $g ([string]$r.Head) $ui.F.SmallB $ui.C.Gray 0 $q.Y $w $q.H 'Left, VerticalCenter, NoPrefix, SingleLine'; continue }
      & $ui.Word $g ([string]$r.Name) $ui.F.Small $ui.C.Navy 0 ($q.Y + (& $ui.Sc 1)) $lw ($q.H - (& $ui.Sc 1)) $wrap
      & $ui.Word $g ([string]$q.Word) $ui.F.SmallB (& $ui.StateInk ([string]$q.Word)) ($w - $sw) ($q.Y + (& $ui.Sc 2)) $sw $pl.Hc 'Right, Top, NoPrefix, SingleLine'
      if ($q.Qual) { & $ui.Word $g ([string]$q.Qual) $ui.F.Small $ui.C.Gray ($w - $sw) ($q.Y + (& $ui.Sc 2) + $pl.Hc) $sw $pl.Hc 'Right, Top, NoPrefix, SingleLine' }
      foreach ($m in @($q.More)) { & $ui.Word $g $m.T $ui.F.Small $ui.C.Gray $pl.In ($m.Y + (& $ui.Sc 1)) ($lw - $pl.In) ($m.H - (& $ui.Sc 1)) $wrap }   # what was found, then what to do
    }
  } catch { $null = $_ } })
# Reads the check results again while the Record is open (R33: a check that ended after F2 still showed NOT RUN). Takes
# nothing; does nothing when the Record is closed. Called after each check result of the window's check runs.
$ui.RecRefresh = { if (-not $ui.RecOn) { return }
  try { $ui.RecData = @(& $ui.RecRows); & $ui.RecTall; & $ui.RecName; $ui.RecChecks.Invalidate() } catch { $null = $_ } }   # a form being closed: nothing to redraw
# Sets the screen-reader text of the check list from $ui.RecData. Takes nothing.
$ui.RecName = {
  $items = @($ui.RecData) | ForEach-Object {
    if ($_.Head) { $_.Head + ':' } else { $_.Name + ' ' + $_.State + $(if (@($_.More).Count) { ', ' + (@($_.More) -join ', ') } else { '' }) }
  }
  $ui.RecChecks.AccessibleName = 'Checks. ' + ($items -join '. ') }
# The whole Record as plain text, for Copy all (R33): the title, each check with its result and its detail lines, each step
# box with its state, then the text box (files, made list, log). Takes nothing; gives back the text with Windows line ends.
$ui.RecAll = {
  $t = @([string]$ui.RecTitle.Text, '', 'CHECKS')
  foreach ($r in @($ui.RecData)) { if ($r.Head) { $t += ('  ' + $r.Head) } else { $t += ('    ' + $r.State + ': ' + $r.Name); foreach ($m in @($r.More)) { $t += ('      ' + [string]$m) } } }
  $t += @('', 'STEPS')
  foreach ($c in @($ui.RecSteps.Controls)) {
    if ($c -is [System.Windows.Forms.CheckBox]) { $fu = $ui.Full[$c]; $t += ('  [' + $(if ($c.Checked) { 'x' } else { ' ' }) + '] ' + $(if ($null -ne $fu) { [string]$fu } else { [string]$c.Text })) }
    elseif ([string]$c.Text -and [string]$c.Text -ne 'STEPS') { $t += ('      ' + [string]$c.Text) } }
  $t += ''; $t += @(([string]$ui.RecText.Text) -split "`r?`n")
  return ((@($t) -join "`r`n").TrimEnd() + "`r`n") }
# Copy all: puts $ui.RecAll on the clipboard and says so on the button until the Record opens again. Takes nothing.
$ui.RecCopyAll = { try { [System.Windows.Forms.Clipboard]::SetText((& $ui.RecAll)); $ui.RecCopy.Text = 'Copied' } catch { $ui.RecCopy.Text = 'Not copied' } }
# Sets the height of the check list to the height of its rows. Takes nothing; does nothing before the window has its
# scale.
$ui.RecTall = {
  if (-not $ui.Scaled) { return }
  try {
    $t = (& $ui.RecPlan $ui.RecChecks.ClientSize.Width).Tall + (& $ui.Sc 4)
    if ($ui.RecChecks.Height -ne $t) { $ui.RecChecks.Height = $t }
  } catch { $null = $_ } }
$ui.RecChecks.Add_Resize({ if ($ui.RecOn -and [int]$ui.RecW -ne [int]$this.ClientSize.Width) { $ui.RecW = [int]$this.ClientSize.Width; & $ui.RecTall }; $this.Invalidate() })
# The step list: a label or a long step name wraps at the column's width, also after the window changes its size.
$ui.RecFit = {
  <#
  .SYNOPSIS
  Wraps step checkboxes and detail labels in the Record Steps panel to the column width.
  .DESCRIPTION
  Computes available column width and updates shortened checkbox text and label MaximumSize when scaled.
  .OUTPUTS
  None.
  #>
  if (-not $ui.Scaled) { return }
  try {
    $mw = [math]::Max((& $ui.Sc 120), ($ui.RecSteps.ClientSize.Width - (& $ui.Sc 28)))
    foreach ($l in @($ui.RecSteps.Controls)) {
      if ($l -is [System.Windows.Forms.CheckBox]) {
        $fu = $ui.Full[$l]; if ($null -ne $fu) { & $ui.Shorten $l ([string]$fu) $mw }
        $l.Size = New-Object System.Drawing.Size($mw, $l.PreferredSize.Height)
      } else { $l.MaximumSize = New-Object System.Drawing.Size($mw, 0) }
    }
  } catch { $null = $_ } }   # a step box is one line, as wide as the column, and ends with "..." when its text is longer
$ui.RecSteps.Add_SizeChanged({ & $ui.RecFit })
& $ui.Ring $ui.RecSteps; & $ui.Ring $ui.Rec; & $ui.Cue $ui.RecText   # focus is always visible: the step boxes and the text box too
# Opens the Record (F2): every check, the step boxes, the files, the made list and the log, sized to its rows.
$ui.VRecord = {
  <#
  .SYNOPSIS
  Opens the Details (Record) view showing checks, editable step checkboxes, planned files, and the log.
  .DESCRIPTION
  Populates check rows, rebuilds step checkboxes (editable when opened from Ready), formats the plan and log text, and shows the Record panel.
  .OUTPUTS
  None.
  #>
  & $ui.Check
  if ($ui.View -eq 'ready' -and -not $ui.Running) { $ui.Edit = $true }   # B7 (UI standard v1): the Record is a link only; opened from Ready, its boxes can change
  $ui.RecOn = $true; $ui.RecData = @(& $ui.RecRows); $ui.RecW = 0; & $ui.RecTall; & $ui.RecName; $ui.RecCopy.Text = 'Copy all'
  $old = @($ui.RecSteps.Controls); $ui.RecSteps.Controls.Clear(); foreach ($o in $old) { $o.Dispose() }; $ui.Full = @{}
  # Adds a styled label row into the Record Steps panel.
  $mk = { param([string]$Text, $Font, $Color)
    $l = New-Object System.Windows.Forms.Label; $l.AutoSize = $true; $l.UseMnemonic = $false
    $l.MaximumSize = New-Object System.Drawing.Size(([math]::Max((& $ui.Sc 120), $ui.RecSteps.ClientSize.Width - (& $ui.Sc 24))), 0)
    $l.Text = $Text; $l.Font = $Font; $l.ForeColor = $Color; $l.Margin = (& $ui.Pad (& $ui.Sc 5) 0 0 (& $ui.Sc 6)); [void]$ui.RecSteps.Controls.Add($l) }
  & $mk 'STEPS' $ui.F.SmallB $ui.C.Gray
  if (-not $ui.Picked) { & $mk 'Choose an application first.' $ui.F.Small $ui.C.Gray }
  else {
    if (-not $ui.Edit) { & $mk $(if ($ui.Running) { 'The run has started: the boxes are locked.' } else { 'To change the boxes, go to "Ready" and select "Details (F2)".' }) $ui.F.Small $ui.C.Gray }
    $list = @(); if ($cleanup.Count) { $list += -1 }; $list += @($script:appSteps); $n = 0
    foreach ($k in $list) {
      $cb = New-Object System.Windows.Forms.CheckBox; $cb.AutoSize = $false; $cb.UseMnemonic = $false
      $cb.Margin = (& $ui.Pad (& $ui.Sc 5) (& $ui.Sc 4) (& $ui.Sc 4) (& $ui.Sc 4)); & $ui.Cue $cb; $cb.Enabled = [bool]$ui.Edit
      $cb.Tag = [int]$k; $cb.Font = $ui.F.SmallB; $cb.ForeColor = $ui.C.Navy
      if ($k -lt 0) { $cb.Text = 'Clean-up'; $cb.Checked = [bool]$ui.Clean; $more = 'Moves finished files to the Recycle Bin' }
      else {
        $n++; $s1 = $steps[$k]; $cb.Checked = [bool]$ui.Sel[[int]$k]
        $tag = $(if ($s1.AskParam) { '  (asks for a folder)' } elseif ($s1.Kind -eq 'guide') { '  (needs you)' } else { '' })
        $cb.Text = [string]$n + '  ' + (Get-StepTitle $s1) + $tag
        $doneMsg = 'Already done for version ' + $script:app.Version + '. Tick the box to run it again'
        $stateNote = $(if ((Test-Deploy) -and -not [bool]$s1.Optional -and -not (Get-StepDefault $k)) { $doneMsg } else { [string]$s1.Note })
        $more = $(if ($ui.StepState[[int]$k]) { [string]$ui.StepState[[int]$k] } else { $stateNote })
      }
      $cb.AccessibleName = $cb.Text + $(if ($more) { '. ' + $more } else { '' }); $ui.Full[$cb] = [string]$cb.Text
      $cb.Add_CheckedChanged({ if ([int]$this.Tag -lt 0) { $ui.Clean = [bool]$this.Checked } else { $ui.Sel[[int]$this.Tag] = [bool]$this.Checked } })
      [void]$ui.RecSteps.Controls.Add($cb); if ($more) { & $mk $more $ui.F.Small (& $ui.StateInk $more) }
    }
  }
  $t = @()
  if ($ui.Picked) { if (-not $ui.Plan) { $ui.Plan = Get-RoundPlan }; $t += $ui.Plan.Lines
    if (Test-Deploy) { $ml = @(Get-MadeLine); if ($ml.Count) { $t += ''; $t += $ml } else { $t += @('', 'The installs of this application have made nothing yet.') } } }
  if ($ui.Log.Count -or $ui.Running) { $t += @('', 'LOG'); $t += @($ui.Log) }
  $ui.RecText.Text = ($t -join "`r`n") + "`r`n"
  $ui.RecTitle.Text = 'Details' + $(if ($ui.Picked) { $dot + $script:app.Name } else { '' }); & $ui.RecFit
  $ui.Card.Visible = $false; $ui.Rec.Visible = $true; & $ui.RecTall; $ui.RecChecks.Invalidate()
  $ui.RecB.Visible = $false; $ui.TourB.Visible = $false; $ui.BackB.Visible = $false; $ui.FeedB.Visible = $false
  try { [void]$ui.RecClose.Focus() } catch { $null = $_ } }
# Closes the Record and shows the card again; redraws the ready card when a step box was changed. Takes nothing.
$ui.CloseRecord = {
  & $ui.Check
  $ui.RecOn = $false; $ui.Rec.Visible = $false; $ui.Card.Visible = $true; $ui.RecB.Visible = $true
  $ui.TourB.Visible = ($ui.HelpViews -contains [string]$ui.View); $ui.BackOn = [bool]$ui.Back; $ui.BackB.Visible = $ui.BackOn
  $ui.BtnRow.Visible = [bool](@($ui.BOn | Where-Object { $_ }).Count -or $ui.BackOn); & $ui.Apart
  $ui.FeedB.Visible = [bool]((& $ui.NoteOn) -and [string]$ui.View -notin $ui.NoNoteViews)
  if ($ui.Edit) { $ui.Edit = $false; if ($ui.View -eq 'ready') { & $ui.VReady } }   # the plan line follows the boxes
  try { [void]$ui.RecB.Focus() } catch { $null = $_ } }
$ui.RecB.Add_Click({ & $ui.VRecord })
$ui.FeedB.Add_Click({ if (& $ui.Settled) { & $ui.VNote } })   # B13: the feedback card for the card on screen
$ui.RecClose.Add_Click({ & $ui.CloseRecord })
$ui.RecCopy.Add_Click({ & $ui.RecCopyAll })
$ui.BackB.Add_Click({ if ((& $ui.Settled) -and $ui.Back -and -not $ui.RecOn -and -not $ui.Busy -and -not $ui.Running) { & $ui.Back } })
