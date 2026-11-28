# RADE window part 01, setup: asks Windows for the real screen dpi, creates the $ui table that holds every
# window value, and creates the form. The window parts run inside "if ($gui) { try {" of 10-window.ps1 and use no other part before this one.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.
# Network: none.
# Writes: none.
# Credentials: none.

# The "One thing" window (the Administrator, 2026-11-14; docs/window-design.md): the window shows one statement or one
# question at a time; everything else (all checks, the step boxes, the files, the made list, the log) is in the Record
# (F2). Each answer moves on: there is no Next / Back row and no Exit button (Esc goes back, and exits on Choose; the window's X exits).
# Every window value lives in $ui: handlers and the engine's callbacks run inside engine functions, where a plain
# variable name could meet a local of the same name. A block stored in $ui reads only $ui and the bundle's globals.
# R28 item 1 (the Administrator, 2026-11-17): text scales with the controls. Two ways were possible: (a) ask Windows for the real
# dpi (SetProcessDPIAware, GetDpiForWindow: a native call from user32) and size everything from it, or (b) AutoScaleMode Font.
# (b) scales by the form font, which Windows draws at 96 dpi on the R25 device (dpiX 96, autoScale 144, font 18 px): it gives
# no scaling at all there. RADE takes (a) and keeps one scale source: the controls follow the form's auto-scale (as before),
# and every font is made bigger by the same factor when the screen draws text smaller ($ui.FontScale in engine/rade_ui.ps1).
# The native call is asked for before any form exists; it changes nothing when the process already has an awareness
# (the call fails), and when a native call cannot be compiled (Constrained Language Mode) the window runs as before.
# Inline C# compilation is forbidden by DEC-NIPR; use standard WinForms AutoScaleMode.Dpi.
$script:native = $false
$script:dpiThread = 'n/a'
$script:taskbarId = 'n/a'
[System.Windows.Forms.Application]::EnableVisualStyles()
$ui = @{
  View = ''; Running = $false; Busy = $false; RecOn = $false; Edit = $false; Answer = ''
  Acts = @(); Back = $null; OnOpt = $null; FieldDo = $null
  Log = (New-Object System.Collections.Generic.List[string]); Summary = @(); Sel = @{}
  Clean = $true; StepState = @{}; Plan = $null; Picked = $false; BaseIds = @()
  BaseRes = @{}; Blocked = @{}; Newer = @{}; Bars = @{}; G = $null; GUrl = ''; CurId = ''
  StepI = 0; StepN = 0; StepNow = ''; BusyShown = $false
  Always = @($false, $false, $false, $false, $false, $false); NB = 6
  StartAfter = $false; Cancel = $false; Dpi = 96.0; ScreenDpi = 96.0; FontK = 1.0
  FontDpi = 96.0; Scaled = $false; Full = @{}
  Clock = [System.Diagnostics.Stopwatch]::StartNew(); CardAt = -1000000.0; GuardMs = 400
  Calm = $false; ContentW = 780
}
# Themes (the Administrator, 2026-11-27, plan engine-v48 D6): the RADE window reads the Windows app mode once when it opens:
# AppsUseLightTheme 0 = dark (Kanon in Fulcrum colors); 1 or no value = light (Kanon in USAF colors). A contrast theme
# wins over both. engine/rade_ui.ps1 takes $ui.Dark as it is set here (an app window that copies that file stays light).
# Takes nothing; gives back $true for dark. No registry (not Windows): light.
$ui.DarkOn = {
  $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
  try {
    $v = Get-ItemPropertyValue -LiteralPath $p -Name 'AppsUseLightTheme' -ErrorAction Stop
    return ([int]$v -eq 0)
  } catch { return $false }   # no value: light
}
$ui.Dark = [bool](& $ui.DarkOn)
$ui.OpenedAt = (Get-Date).AddSeconds(-1)   # E4: the SCALE lines of the RADE windows shown from this time on go into the round's results
# engine-v47 (the Administrator, 2026-11-26): the line under the word RADE is RADE's full name, "Redacted Application Deployment
# Engine" (replaces the short tagline of L1). The RADE row shows only for an app with no productName and logo.
$ui.Tagline = 'Redacted Application Deployment Engine'
# Layout values from engine/window.json, put in by the build (text column share, cap, min window, min frame, step ms).
$ui.Layout = @{
  Share = [double]'@@TEXT_SHARE@@'; MaxW = [int]'@@TEXT_MAX@@'
  MinW = [int]'@@MIN_W@@'; MinH = [int]'@@MIN_H@@'
  FrameMin = [int]'@@FRAME_MIN@@'; StepMs = [int]'@@MIN_STEP_MS@@'
}
$ui.Hist = Read-RoundHistory (Get-BasePath)
$script:secret = Get-Secret (Get-ProfileLeaf) (Get-ProfileLeaf)   # saved checks are masked before they are written
try { $ui.Calm = -not [System.Windows.Forms.SystemInformation]::UIEffectsEnabled } catch { $null = $_ }
$ui.Form = New-Object System.Windows.Forms.Form
# The title text (docs/window-design.md "Title bar"). engine-v47 (the Administrator, 2026-11-26: "Kanon icon and name"): for an app with
# application.productName, "<word> - <version>" for a chosen install ("Kanon - 0.1.0"), else "<word> - <round>" ("Kanon - R46";
# from the shortcut, the version of the paste's install); the engine number is in Details (F2). Without a productName,
# "RADE - engine-vNN - <round>" as before (90-161.Z R44 E2; from the shortcut: no round). Takes the chosen app or $null.
$ui.TitleText = { param($App)
  if (-not [string]$appProduct) { return ('RADE - engine-v' + $engineRelease + $(if (Test-RunnerStart) { '' } else { ' - ' + $round })) }
  if (-not $App -and (Test-RunnerStart)) { $App = @($apps | Where-Object { [string]$_.Version })[0] }   # the shortcut opens the paste of an install
  $v = $(if ($App -and [string]$App.Version) { [string]$App.Version } elseif (-not (Test-RunnerStart)) { [string]$round } else { '' })
  return ([string]$appProduct + $(if ($v) { ' - ' + $v } else { '' })) }
$ui.Form.Text = & $ui.TitleText $null
$ui.Form.SuspendLayout()
$ui.Form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96); $ui.Form.AutoScaleMode = 'Dpi'   # sizes below are at 100 % scaling
# RADE shared UI file (engine/rade_ui.ps1): the theme tokens (colors, fonts, sizes), the builders for buttons, links and
# card text, the drawing and measuring helpers (part 2: engine/rade_ui_text.ps1, right after this file), and the layout self-check. rade_build.py puts this text into every bundle
# at its marker line (docs/engine.md "How an app gets the engine"); it runs inside the window's try block, after
# $ui.Form exists, and fills $ui. An app window can reuse it: same $ui, same names. ASCII only (a bundle is ASCII).
# Needs from the window: $ui (a hashtable), $ui.Form, the globals $apps, $dot, $round and the engine function
# ConvertTo-Masked and Test-Deploy (only the self-check uses them).

# ---- Scale and colors
# One scale source (R24: the screen dpi said 96 while Windows Forms scaled every control 1.5 x): $ui.Dpi is the dpi the
# form scales to (its auto-scale dimensions; the form's sizes are given at 96). Every size RADE sets or draws after the
# form has scaled goes through $ui.Sc. The screen dpi is only reported (the SCALE line).
try { $gx = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $ui.ScreenDpi = [double]$gx.DpiX; $gx.Dispose() } catch { $null = $_ }
# Reads the form's current auto-scale DPI into $ui.Dpi.
$ui.FormDpi = { try { $d = [double]$ui.Form.CurrentAutoScaleDimensions.Width; if ($d -gt 0) { $ui.Dpi = $d } } catch { $null = $_ } }
# Scales a 100 % pixel size to current DPI pixels.
$ui.Sc = { param([double]$Px) [int][math]::Round($Px * $ui.Dpi / 96.0) }   # a size at 100 % in screen pixels, for parts made or drawn after the form has scaled
# ---- UI tokens (UI standard v1, the Administrator, 2026-11-20; docs/ui-standard.md): written from engine/ui-tokens.json
# by python3 engine/rade_tokens.py --write. Do not edit these lines: a build stops when they differ from that file.
$ui.Standard = 'v1'
# Colors: name = @(red, green, blue, the SystemColors role it takes while a Windows contrast theme is on); uses: the file.
$ui.Tok = [ordered]@{}
$ui.Tok.White = @(255, 255, 255, 'Window'); $ui.Tok.Ink = @(27, 36, 48, 'WindowText'); $ui.Tok.Navy = @(11, 37, 69, 'WindowText')
$ui.Tok.Gray = @(90, 101, 115, 'GrayText'); $ui.Tok.Blue = @(0, 83, 159, 'Highlight'); $ui.Tok.OnBlue = @(255, 255, 255, 'HighlightText')
$ui.Tok.Link = @(0, 83, 159, 'HotTrack'); $ui.Tok.Focus = @(11, 37, 69, 'HotTrack'); $ui.Tok.Face = @(255, 255, 255, 'ButtonFace')
$ui.Tok.FaceInk = @(11, 37, 69, 'ControlText'); $ui.Tok.Edge = @(122, 135, 148, 'ControlText'); $ui.Tok.Hair = @(227, 232, 238, 'GrayText')
$ui.Tok.Track = @(127, 147, 168, 'GrayText'); $ui.Tok.Off = @(244, 246, 248, 'ButtonFace'); $ui.Tok.OffInk = @(95, 104, 116, 'GrayText')
$ui.Tok.Yellow = @(255, 205, 0, 'Highlight'); $ui.Tok.Red = @(139, 26, 26, 'WindowText'); $ui.Tok.Green = @(46, 133, 64, 'Highlight')
$ui.Tok.GreenInk = @(31, 107, 49, 'WindowText'); $ui.Tok.Band = @(8, 27, 51, 'Window'); $ui.Tok.BandInk = @(255, 255, 255, 'WindowText')
$ui.Tok.BandMuted = @(185, 199, 216, 'GrayText'); $ui.Tok.Info = @(0, 83, 159, 'Highlight'); $ui.Tok.Tint = @(242, 246, 251, 'Window')
$ui.Tok.OnYellow = @(11, 37, 69, 'HighlightText'); $ui.Tok.OffRed = @(139, 26, 26, 'GrayText')
# The dark set (plan engine-v48 D6): name = @(red, green, blue); the system role is the light one.
$ui.TokDark = [ordered]@{}
$ui.TokDark.White = @(21, 23, 29); $ui.TokDark.Ink = @(243, 238, 228); $ui.TokDark.Navy = @(243, 238, 228); $ui.TokDark.Gray = @(169, 172, 181)
$ui.TokDark.Blue = @(235, 101, 59); $ui.TokDark.OnBlue = @(21, 23, 29); $ui.TokDark.Link = @(141, 184, 240); $ui.TokDark.Focus = @(255, 140, 102)
$ui.TokDark.Face = @(34, 38, 49); $ui.TokDark.FaceInk = @(243, 238, 228); $ui.TokDark.Edge = @(122, 127, 140); $ui.TokDark.Hair = @(48, 52, 61)
$ui.TokDark.Track = @(58, 63, 74); $ui.TokDark.Off = @(38, 42, 51); $ui.TokDark.OffInk = @(149, 153, 163); $ui.TokDark.Yellow = @(212, 175, 55)
$ui.TokDark.Red = @(244, 155, 145); $ui.TokDark.Green = @(95, 208, 142); $ui.TokDark.GreenInk = @(95, 208, 142); $ui.TokDark.Band = @(14, 16, 21)
$ui.TokDark.BandInk = @(243, 238, 228); $ui.TokDark.BandMuted = @(169, 172, 181); $ui.TokDark.Info = @(141, 184, 240); $ui.TokDark.Tint = @(27, 36, 51)
$ui.TokDark.OnYellow = @(21, 23, 29); $ui.TokDark.OffRed = @(201, 143, 137)
# Sizes, gaps and field widths, in pixels at 100 % (every size set after the form has scaled goes through $ui.Sc).
$ui.Z = @{
  ActionW = 160; WideW = 240; ActionH = 40; CompactW = 96; CompactH = 30; LinkH = 28; BarTop = 11; M = 4; Inset = 24; BandH = 56; BandLogo = 36; Disc = 20; LineIdle = 4; LineLoud = 8; Narrow = 700
  G1 = 4; G2 = 8; G3 = 12; G4 = 16; G6 = 24
  FieldS = 240; FieldM = 420; FieldL = 600 }
# Faces: name = @(family, the font file's name in the bundle ('' = none), the family used when the font cannot be loaded).
$ui.Faces = @{ title = @('Segoe UI Semibold', '', 'Segoe UI Semibold'); text = @('Segoe UI', '', 'Segoe UI')
  strong = @('Segoe UI Semibold', '', 'Segoe UI Semibold'); mono = @('Consolas', '', 'Consolas') }
# Text styles: name = @(face, size in points at 100 %, font style ('' = regular)); uses: the file.
$ui.Styles = [ordered]@{}
$ui.Styles.Sent = @('title', 22, ''); $ui.Styles.Word = @('title', 15, 'Bold'); $ui.Styles.Body = @('text', 12, ''); $ui.Styles.Small = @('text', 10, '')
$ui.Styles.SmallB = @('strong', 10, ''); $ui.Styles.Link = @('strong', 10, 'Underline'); $ui.Styles.Turn = @('strong', 12, 'Bold'); $ui.Styles.Mono = @('mono', 9, '')
# ---- End of the UI tokens
# ---- Colors and Windows contrast themes (UI standard v1, the Administrator, 2026-11-20; docs/ui-standard.md B10, B11)
# One meaning each (the "use" of each token above): navy = card text, Air Force blue = the action and progress, yellow =
# your turn, dark red = FAILED, NEEDS REVIEW and the one destructive action, green = passed. Every text pair is at least
# 4.5:1 and every non-text pair 3:1 (scripts/ui_tokens.py computes them from engine/ui-tokens.json). While a Windows
# contrast theme is on (SystemInformation.HighContrast), each token is the system color of its role, so the window has
# the theme's colors; $ui.Recolor follows a theme that changes while the window is open.
$ui.HighOn = { try { return [bool][System.Windows.Forms.SystemInformation]::HighContrast } catch { return $false } }   # no answer (an old host): the own colors
# The color of one token: its own color, or while $ui.High is on the system color of its role. Takes the token name; gives
# back a Color (WindowText for a name that is not a token, so no text is ever lost).
$ui.Color = {
  <#
  .SYNOPSIS
  Resolves a UI color token name to a System.Drawing.Color for the active theme.
  .DESCRIPTION
  Returns the system color matching the token role when HighContrast is active, or the dark/light RGB color.
  .PARAMETER Role
  Token name from $ui.Tok (e.g. Navy, Blue, Red, White).
  .OUTPUTS
  System.Drawing.Color for the token, or Black if unknown.
  #>
  param([string]$Role)
  $t = $ui.Tok[$Role]
  if ($ui.High) {
    $r = $(if ($t) { [string]$t[3] } else { 'WindowText' })
    try {
      $sc = [System.Drawing.SystemColors]::$r
      if ($null -eq $sc) { $sc = [System.Drawing.SystemColors]::WindowText }
      return $sc
    } catch { return [System.Drawing.Color]::Black }   # no system colors: black
  }
  if (-not $t) { return [System.Drawing.Color]::Black }
  if ($ui.Dark -and $ui.TokDark[$Role]) { $t = $ui.TokDark[$Role] }   # the dark set (plan engine-v48 D6)
  return [System.Drawing.Color]::FromArgb([int]$t[0], [int]$t[1], [int]$t[2]) }
# Puts the colors for a theme into $ui.C in place (every builder and paint handler reads them there). Takes $true for the
# system colors of a contrast theme, $false for the own colors.
$ui.UseColors = { param([bool]$High) $ui.High = $High; foreach ($k in @($ui.Tok.Keys)) { $ui.C[$k] = & $ui.Color $k } }
# The dark set is opt-in (review of PR 211): a window that wants it sets $ui.Dark before this file runs (the RADE window:
# engine/ps/window/01-setup.ps1, from the Windows app mode). An app window that copies this file has no $ui.Dark: light.
$ui.Dark = [bool]$ui.Dark; $ui.C = @{}; & $ui.UseColors (& $ui.HighOn)
# ---- Fonts, sizes and buttons
# Cosmetics never stop the window (R06: Font('Segoe UI', 10, 'Bold') failed with "Multiple ambiguous overloads"): a typed
# style and size, and the window font when a font cannot be made.
$ui.Bold = [Enum]::Parse(('System.Drawing.FontStyle' -as [type]), 'Bold')
# $Pt is the size at 100 % scaling; $ui.FontK (R28: text scales with the controls) makes it as much bigger as the controls are.
$ui.Font = { param([string]$Fam, [double]$Pt, $Style)
  try {
    $pk = [single]($Pt * $ui.FontK)
    if ($null -ne $Style) { return (New-Object System.Drawing.Font($Fam, $pk, $Style)) }
    return (New-Object System.Drawing.Font($Fam, $pk))
  } catch { return $ui.Form.Font }
}
# FontScale: how much bigger than the screen's own text scaling the fonts must be, so that text follows the controls. A probe
# font of 100 pt Segoe UI is 177 px tall when the screen draws text at 96 dpi; its real height gives the dpi the text is drawn
# at. On the R25 device (autoScale 144, text at 96) the answer is 1.5; where Windows scales both, it is 1. The factor is
# kept to steps of 0.25 (the Windows scales); anything odd gives 1.
$ui.FontScale = { $ui.FontK = 1.0; $ui.FontDpi = 96.0
  try { $pf = New-Object System.Drawing.Font('Segoe UI', [single]100); $r = [double]$pf.Height / 177.3; try { $pf.Dispose() } catch { $null = $_ }
    if ($r -gt 0.6 -and $r -lt 4) {
      $k = [math]::Round(($ui.Dpi / 96.0) / $r * 4) / 4
      if ($k -ge 0.5 -and $k -le 4) { $ui.FontK = [double]$k }
      $ui.FontDpi = 96.0 * [math]::Max(1.0, [math]::Round($r * 4) / 4)
    } } catch { $null = $_ } }
# Native Windows fonts (Segoe UI / Segoe UI Semibold / Consolas): no embedded TTFs and no Add-Type P/Invoke (DEC-NIPR).
$ui.FontFam = @{}; $ui.FontNote = 'native (Segoe UI / Consolas)'
# Builds the Font object for a named style token from $ui.Styles.
$ui.StyleFont = { param([string]$Name)
  $s = $ui.Styles[$Name]; $face = $ui.Faces[[string]$s[0]]; $pt = [double]$s[1]
  $st = $(if ([string]$s[2]) { [Enum]::Parse(('System.Drawing.FontStyle' -as [type]), [string]$s[2]) } else { $null })
  return (& $ui.Font ([string]$face[2]) $pt $st) }
& $ui.FormDpi; & $ui.FontScale; $ui.Form.Font = (& $ui.StyleFont 'Small')
# Text styles (the Administrator, 2026-11-17; faces and sizes from the UI tokens, UI standard v1): Sent = headline; Body =
# paragraphs, step lines, help line; Small = second lines, notes, box text; SmallB = the line in capitals, labels, every
# button, key numbers, the Record's heads and result words; Link = SmallB underlined (a link is marked by more than
# color); Word = the word in the band and the Run card's percent; Mono = the Record's text box only; Turn = the strong summary line of the Done card.
$ui.F = @{}; foreach ($k in @($ui.Styles.Keys)) { $ui.F[$k] = & $ui.StyleFont $k }; $ui.F.Small = $ui.Form.Font
# Sizes: the UI tokens above (gaps 4, 8, 12, 16, 24; a 4 px margin around a button or link for its focus ring).
$ui.Pad = { param([int]$L, [int]$T, [int]$R, [int]$B) New-Object System.Windows.Forms.Padding($L, $T, $R, $B) }
# Creates an auto-sized, hidden Label with the given font, color, and top margin.
$ui.Label = { param($Font, $Color, [int]$Top)
  $l = New-Object System.Windows.Forms.Label; $l.AutoSize = $true; $l.Font = $Font; $l.ForeColor = $Color
  $l.BackColor = $ui.C.White; $l.UseMnemonic = $false; $l.Margin = (& $ui.Pad 0 $Top 0 0); $l.Visible = $false; $l }
# ---- Card text that can be selected (R28, the Administrator, 2026-11-17)
# The headline, the lines, the help, the notes and the questions of a card are read-only, borderless text boxes: the same look as
# a label, but the text can be highlighted and copied (Ctrl+C, or right-click: Copy, Select All). No tab stop, no caret shown.
# A text box does not size itself to its text, so $ui.Reflow gives it the size the text needs (measured as the edit control wraps:
# WordBreak, TextBoxControl) whenever its text, its font or its wrap width changes. The wrap width is $ui.Wrap[box] (set with
# $ui.SetWrap): a text box's own MaximumSize would cut the few extra pixels the edit control keeps at its edges.
$ui.Wrap = @{}
# A text box with a fixed number of lines ($ui.Hold[box] = n): $ui.Reflow makes it n lines tall whatever its text, also with no
# text, so the parts under it never move when the text changes (the Run card's now-doing line: the Administrator, 2026-11-19,
# "the cancel button jumps up and down"). Its text is cut to n lines with $ui.FitLines.
$ui.Hold = @{}
# A text box with a least number of lines ($ui.MinLines[box] = n): at least n lines tall, also with no text (the line in
# capitals: the "Your turn" line under it never moves up on a card with no line).
$ui.MinLines = @{}
# A text box that shows changing values ($ui.Range[box] = every text it can show on this card, set by $ui.SetCard): it is as
# wide and as tall as the largest of them, so a new value never moves or resizes a part of the card (the Administrator,
# 2026-11-19: "values cause fluttering and distortion as things fly around").
$ui.Range = @{}
# Gets the wrap width of a card text box or label.
$ui.GetWrap = { param($C) if ($C -is [System.Windows.Forms.TextBox]) { return [int]$ui.Wrap[$C] }; return [int]$C.MaximumSize.Width }
# Sets the wrap width of a card text box or label and reflows text boxes.
$ui.SetWrap = { param($C, [int]$W)
  if ($C -is [System.Windows.Forms.TextBox]) { $ui.Wrap[$C] = $W; & $ui.Reflow $C }
  else { $C.MaximumSize = New-Object System.Drawing.Size($W, 0) } }
# Resizes a card text box to fit its text, fixed hold lines, range, or minimum lines.
$ui.Reflow = {
  <#
  .SYNOPSIS
  Resizes a card text box to fit its text, fixed line count, value range, or minimum line count.
  .DESCRIPTION
  Computes size using $ui.Hold, $ui.Range, $ui.MinLines, and $ui.Wrap without altering unrelated controls.
  .PARAMETER T
  The TextBox control to measure and resize.
  .OUTPUTS
  None.
  #>
  param($T)
  try { $txt = [string]$T.Text; $n = [int]$ui.Hold[$T]
    if ($n -gt 0) {   # a fixed number of lines: as wide as its wrap width, n lines tall
      $w = [int]$ui.Wrap[$T]; $one = & $ui.Meas 'Ag' $T.Font 100000
      $nw = $(if ($w -gt 0) { $w + (& $ui.Sc 4) } else { $one.Width })
      $ns = New-Object System.Drawing.Size($nw, ($n * $one.Height + (& $ui.Sc 2)))
      if ($T.Width -ne $ns.Width -or $T.Height -ne $ns.Height) { $T.Size = $ns }; return }
    $all = @(@($ui.Range[$T]) + @($txt) | Where-Object { $_ }); $m = [int]$ui.MinLines[$T]; if (-not $all.Count -and $m -le 0) { return }   # its text and its range
    $w = [int]$ui.Wrap[$T]; $bw = 0; $bh = 0
    foreach ($x in $all) { $s = & $ui.TextSize ([string]$x) $T.Font $w; $bw = [math]::Max($bw, $s.Width); $bh = [math]::Max($bh, $s.Height) }
    if ($m -gt 0) { $bw = [math]::Max($bw, (& $ui.Sc 4)); $bh = [math]::Max($bh, ($m * (& $ui.Meas 'Ag' $T.Font 100000).Height + (& $ui.Sc 2))) }
    $ns = New-Object System.Drawing.Size($bw, $bh); if ($T.Width -ne $ns.Width -or $T.Height -ne $ns.Height) { $T.Size = $ns } } catch { $null = $_ } }
# The size a card text box needs for one text: as the edit control wraps it at the wrap width (0: no wrap), with the few
# pixels the control keeps at its edges. Takes the text, the font and the wrap width; gives back the size.
$ui.TextSize = { param([string]$Txt, $Font, [int]$W)
  $sl = & $ui.Sc 4; $one = & $ui.Meas $Txt $Font 100000; $sz = $one
  if ($W -gt 0 -and $one.Width -gt $W) { $sz = & $ui.Meas $Txt $Font $W; $bw = $W + $sl } else { $bw = $one.Width + 2 * $sl }
  return (New-Object System.Drawing.Size($bw, ($sz.Height + (& $ui.Sc 2)))) }
$ui.Menu = New-Object System.Windows.Forms.ContextMenuStrip; $ui.Menu.AccessibleName = 'Text menu'; $ui.MenuCopy = $ui.Menu.Items.Add('Copy'); $ui.MenuAll = $ui.Menu.Items.Add('Select All')
# Pastes the clipboard text into a one-line text box as one line, in place of its selection. When the text is longer
# than the room, it is cut and the gray line under the box says how many characters did not fit (R7, the Administrator,
# 2026-11-19; docs/window-design.md "Cards"). Takes the box; gives back $true when it pasted (the key is then handled),
# $false when the clipboard has no text or the box is multi-line.
$ui.PasteLine = {
  <#
  .SYNOPSIS
  Pastes clipboard text as a single line into a writable single-line TextBox, truncating overflow.
  .DESCRIPTION
  Flattens newlines and tabs via $ui.OneLine, inserts into SelectedText within MaxLength, and displays a note if characters were truncated.
  .PARAMETER Tb
  Target TextBox control.
  .OUTPUTS
  Boolean indicating whether clipboard text was pasted.
  #>
  param($Tb)
  try { if ($Tb.Multiline -or $Tb.ReadOnly -or -not [System.Windows.Forms.Clipboard]::ContainsText()) { return $false }
    $room = [int]$Tb.MaxLength - ([string]$Tb.Text).Length + [int]$Tb.SelectionLength
    $whole = & $ui.OneLine ([System.Windows.Forms.Clipboard]::GetText()) ([int]::MaxValue)
    $Tb.SelectedText = & $ui.OneLine $whole $room
    $lost = $whole.Length - [math]::Max(0, $room)
    $lostStr = $lost.ToString('N0', [System.Globalization.CultureInfo]::InvariantCulture)
    $unit = $(if ($lost -eq 1) { ' character did' } else { ' characters did' })
    $msg = $(if ($lost -gt 0) { 'The paste was too long: ' + $lostStr + $unit + ' not fit.' } else { '' })
    if ($msg) { & $ui.Say1 $msg; $ui.PasteNote = $msg }
    elseif ($ui.PasteNote -and [string]$ui.Note.Text -ceq [string]$ui.PasteNote) { & $ui.Say1 ''; $ui.PasteNote = '' }   # clear only a note this paste wrote
    return $true } catch { return $false } }
$ui.MenuCopy.Add_Click({ $null = & $ui.CopyText $ui.Menu.SourceControl })
$ui.MenuAll.Add_Click({ try { $ui.Menu.SourceControl.SelectAll() } catch { $null = $_ } })
$ui.Menu.Add_Opening({ try { $ui.MenuCopy.Enabled = [bool]($ui.Menu.SourceControl.SelectionLength -gt 0) } catch { $null = $_ } })
# Placeholder handler for suppressing caret feedback on read-only card text boxes.
$ui.NoCaret = { param($C) $null = $C }
# Creates a read-only, selectable, borderless multiline TextBox for card text.
$ui.Text = { param($Font, $Color, [int]$Top, [string]$Name)
  $t = New-Object System.Windows.Forms.TextBox; $t.Multiline = $true; $t.ReadOnly = $true; $t.WordWrap = $true
  $t.ScrollBars = 'None'; $t.BorderStyle = 'None'; $t.TabStop = $false; $t.AutoSize = $false
  $t.Font = $Font; $t.ForeColor = $Color; $t.BackColor = $ui.C.White; $t.Margin = (& $ui.Pad 0 $Top 0 0); $t.Visible = $false; $t.ContextMenuStrip = $ui.Menu; $t.AccessibleName = $Name
  $ui.Wrap[$t] = 0; $t.Add_TextChanged({ & $ui.Reflow $this }); $t.Add_FontChanged({ & $ui.Reflow $this })
  $t.Add_GotFocus({ & $ui.NoCaret $this }); $t.Add_MouseUp({ & $ui.NoCaret $this }); $t.Add_KeyUp({ & $ui.NoCaret $this }); $t }
# Returns $true when the active control is an editable TextBox.
$ui.InField = { $a = $ui.Form.ActiveControl; return [bool](($a -is [System.Windows.Forms.TextBox]) -and $a.TabStop) }   # a box the user types in (card text is not one)
# Creates an auto-sized, hidden FlowLayoutPanel with white background and top margin.
$ui.Flow = { param([int]$Top)
  $f = New-Object System.Windows.Forms.FlowLayoutPanel; $f.AutoSize = $true; $f.WrapContents = $false
  $f.BackColor = $ui.C.White; $f.Margin = (& $ui.Pad 0 $Top 0 0); $f.Visible = $false; $f }
# Focus is always visible: a 2 px navy ring around the control that has it, drawn by its parent ($ui.Ring), also after a
# mouse click. Each focusable control tells its parent to repaint ($ui.Cue) and keeps a 4 px margin for the ring.
$ui.Cue = { param($C) $C.Add_GotFocus({ try { $this.Parent.Invalidate() } catch { $null = $_ } }); $C.Add_LostFocus({ try { $this.Parent.Invalidate() } catch { $null = $_ } }) }
# Paints a 2 px focus ring around any focused visible child control inside container $P.
$ui.Ring = {
  <#
  .SYNOPSIS
  Attaches a Paint handler to container $P that draws a 2 px focus ring around the focused child control.
  .DESCRIPTION
  Iterates visible child controls on Paint and outlines focused controls or active input box containers.
  .PARAMETER P
  The parent container Control.
  .OUTPUTS
  None.
  #>
  param($P)
  $P.Add_Paint({
    try {
      foreach ($c in $this.Controls) {
        if (($c.Focused -or ($ui.Boxes -contains $c -and $c.ContainsFocus)) -and $c.Visible) {
          $pn = New-Object System.Drawing.Pen($ui.C.Focus, [single](& $ui.Sc 2)); $b = $c.Bounds; $o = & $ui.Sc 2
          $_.Graphics.DrawRectangle($pn, ($b.Left - $o), ($b.Top - $o), ($b.Width + 2 * $o - 1), ($b.Height + 2 * $o - 1))
          $pn.Dispose()
        }
      }
    } catch { $null = $_ }
  }) }
$ui.Style = {
  <#
  .SYNOPSIS
  Applies visual colors, border, font, and enabled state to a button for the specified kind.
  .DESCRIPTION
  Sets $ui.Kinds[$B], enables or disables the button, configures flat appearance colors (including hover and pressed
  states) for primary, danger, dangerline, off, dangeroff, or default secondary buttons.
  .PARAMETER B
  The Button control to style.
  .PARAMETER Kind
  Button style kind ('primary', 'danger', 'dangerline', 'off', 'dangeroff', or '').
  .OUTPUTS
  None.
  #>
  param($B, [string]$Kind)
  # primary = Air Force blue (dark: ember); danger = dark red (dark: an outline); dangerline = error outline;
  # off = not available (gray, text 6.3:1); dangeroff = destructive action unavailable; else white with gray edge.
  $ui.Kinds[$B] = $Kind; $B.Enabled = ($Kind -notin 'off', 'dangeroff'); $B.FlatStyle = 'Flat'; $B.FlatAppearance.BorderSize = 1; $B.Font = $ui.F.SmallB; $over = $null; $down = $null
  if ($Kind -eq 'off') { $B.BackColor = $ui.C.Off; $B.ForeColor = $ui.C.OffInk; $B.FlatAppearance.BorderColor = $ui.C.Track }
  elseif ($Kind -eq 'dangeroff') { $B.BackColor = $ui.C.Off; $B.ForeColor = $ui.C.OffRed; $B.FlatAppearance.BorderColor = $ui.C.OffRed }
  elseif ($Kind -eq 'primary') { $B.BackColor = $ui.C.Blue; $B.ForeColor = $ui.C.OnBlue; $B.FlatAppearance.BorderColor = $ui.C.Blue }
  elseif ($Kind -eq 'danger' -and -not $ui.Dark) { $B.BackColor = $ui.C.Red; $B.ForeColor = $ui.C.White; $B.FlatAppearance.BorderColor = $ui.C.Red }
  elseif ($Kind -in 'danger', 'dangerline') {
    # the error color as text and edge (Cards v2: "Stop the install"; dark: every danger button)
    $B.BackColor = $ui.C.Face; $B.ForeColor = $ui.C.Red; $B.FlatAppearance.BorderColor = $ui.C.Red
  }
  else { $B.BackColor = $ui.C.Face; $B.ForeColor = $ui.C.FaceInk; $B.FlatAppearance.BorderColor = $ui.C.Edge; $over = $ui.C.Hair; $down = $ui.C.Off }
  if (-not $over) { $over = $B.BackColor; $down = $B.BackColor }
  try { $B.FlatAppearance.MouseOverBackColor = $over; $B.FlatAppearance.MouseDownBackColor = $down } catch { $null = $_ } }
# Every button draws its own face, border and text in every state (normal, under the pointer, pressed, focused, default,
# not available), over what Windows drew: no theme border, no black default-button border, no dotted focus rectangle
# (R24: a black or gray outline on a work computer). The focus is the navy ring its parent draws ($ui.Ring).
$ui.Hot = $null; $ui.Down = $null
# A card's buttons and choices take no click in the first $ui.GuardMs (400) ms after the card changed (R2 review: the second
# click of a double-click on Done answered the first question unseen). Enter and Space click the same buttons: same guard.
# Monotonic time (a Stopwatch, not the wall clock: M1 review); a negative elapsed time never blocks a click.
$ui.Settled = { $e = $ui.Clock.Elapsed.TotalMilliseconds - [double]$ui.CardAt; ($e -ge $ui.GuardMs -or $e -lt 0) }
# Owner-draws a button's background, border, and label text across normal, hover, pressed, and busy states.
$ui.Face = {
  <#
  .SYNOPSIS
  Owner-draws a button or link label's background, border, and centered or left-aligned text.
  .DESCRIPTION
  Accounts for $ui.Busy (respecting Always flags), enabled, down, and hover states, then renders text via $ui.Word.
  .PARAMETER B
  The Button control being painted.
  .PARAMETER G
  Graphics surface for the Paint event.
  .OUTPUTS
  None.
  #>
  param($B, $G)
  try {
    if (-not $B.Text) { return }
    $w = $B.ClientSize.Width; $h = $B.ClientSize.Height; $fa = $B.FlatAppearance
    # While RADE is busy a button does nothing, so it looks unavailable (R28), except buttons marked Always (Cancel).
    $busy = [bool]($ui.Busy -and -not (($B.Tag -is [int]) -and $ui.Always[[int]$B.Tag]))
    $bg = $(
      if ($busy -and [int]$fa.BorderSize -gt 0) { $ui.C.Off }
      elseif (-not $B.Enabled) { $B.BackColor }
      elseif ([object]::ReferenceEquals($ui.Down, $B)) { $fa.MouseDownBackColor }
      elseif ([object]::ReferenceEquals($ui.Hot, $B)) { $fa.MouseOverBackColor }
      else { $B.BackColor }
    )
    $G.Clear($bg)
    if ([int]$fa.BorderSize -gt 0) {
      $pn = New-Object System.Drawing.Pen($(if ($busy) { $ui.C.Track } else { $fa.BorderColor }))
      $G.DrawRectangle($pn, 0, 0, ($w - 1), ($h - 1)); $pn.Dispose()
    }
    # A link (no edge) draws its text at the left, a button in the middle (R28: a link in a wide box started 38 px right of the card edge).
    $flags = $(if ([int]$fa.BorderSize -gt 0) { 'HorizontalCenter, VerticalCenter, NoPrefix, SingleLine' } else { 'Left, VerticalCenter, NoPrefix, SingleLine' })
    & $ui.Word $G ([string]$B.Text) $B.Font $(if ($busy) { $ui.C.OffInk } else { $B.ForeColor }) 0 0 $w $h $flags
  } catch { $null = $_ } }
# Attaches custom paint, hover, press, and visibility handlers to button $B.
$ui.Own = { param($B) $B.UseVisualStyleBackColor = $false; $B.Add_Paint({ & $ui.Face $this $_.Graphics })
  $B.Add_MouseEnter({ $ui.Hot = $this; $this.Invalidate() }); $B.Add_MouseLeave({ if ([object]::ReferenceEquals($ui.Hot, $this)) { $ui.Hot = $null }; $this.Invalidate() })
  $B.Add_MouseDown({ if ([string]$_.Button -eq 'Left') { $ui.Down = $this; $this.Invalidate() } }); $B.Add_MouseUp({ $ui.Down = $null; $this.Invalidate() })
  $B.Add_VisibleChanged({ if ([object]::ReferenceEquals($ui.Hot, $this)) { $ui.Hot = $null }; if ([object]::ReferenceEquals($ui.Down, $this)) { $ui.Down = $null } }) }
# Buttons have fixed sizes (UI standard v1, B1; the Administrator, 2026-11-20): no AutoSize, so a button never grows or
# shrinks with its text. $Kind: 'action' (a card's buttons: 160 x 40, or 240 x 40 when its label needs more room) or
# 'compact' (96 x 30: beside a box, "Back (Esc)", the Record's buttons; 160 x 30 when its label needs more room). A label
# that needs more than the widest size is cut, and the self-check reports it (rule B1). Sizes: $ui.Z.
$ui.BtnKind = @{}; $ui.Wide = @{}
# The size of a button of a kind for its text: at 100 % before the window has its scale (Windows Forms scales it), else scaled.
$ui.BtnSize = { param($B)
  $k = [string]$ui.BtnKind[$B]; $s = $(if ($ui.Scaled) { $ui.Sc } else { { param([double]$Px) [int]$Px } })
  $h = $(if ($k -eq 'compact') { $ui.Z.CompactH } else { $ui.Z.ActionH }); $ws = $(if ($k -eq 'compact') { @($ui.Z.CompactW, $ui.Z.ActionW) } else { @($ui.Z.ActionW, $ui.Z.WideW) })
  $need = 0
  try {
    if ($B.Text) { $need = [int][System.Windows.Forms.TextRenderer]::MeasureText([string]$B.Text, $B.Font).Width + (& $ui.Sc (2 * $ui.Z.G2)) }
  } catch { $null = $_ }   # no measure: the first width
  $w = $(if ($need -le (& $ui.Sc $ws[0]) -and -not $ui.Wide[$B]) { $ws[0] } else { $ws[1] })   # $ui.Wide: the wide size for every text (a stack of buttons)
  return (New-Object System.Drawing.Size((& $s $w), (& $s $h))) }
# Gives a button the size of its kind for its text ($ui.BtnSize). Takes the button.
$ui.FitBtn = { param($B) try { $ns = & $ui.BtnSize $B; if ($B.Width -ne $ns.Width -or $B.Height -ne $ns.Height) { $B.Size = $ns } } catch { $null = $_ } }   # no size now: the next text sets it
$ui.AutoNames = @{}   # the name $ui.AutoName gave each button
# AccessibleName on every control (docs/window-design.md; fleet v2): a button whose name nobody set takes its text and
# follows it when the text changes; a name set by hand stays. Takes the button; gives back nothing.
$ui.AutoName = { param($B) if (-not [string]$B.AccessibleName -or [string]$ui.AutoNames[$B] -eq [string]$B.AccessibleName) {
    $B.AccessibleName = [string]$B.Text; $ui.AutoNames[$B] = [string]$B.Text } }
# Makes a button of a kind ('action' or 'compact'), styled, with its focus ring and own face. Takes the kind; gives back the button.
$ui.Btn = { param([string]$Kind) $b = New-Object System.Windows.Forms.Button; $b.AutoSize = $false; $ui.BtnKind[$b] = $(if ($Kind -eq 'compact') { 'compact' } else { 'action' })
  $b.Padding = (& $ui.Pad $ui.Z.G2 0 $ui.Z.G2 0); $b.Margin = (& $ui.Pad $ui.Z.M $ui.Z.M $ui.Z.M $ui.Z.M); $b.UseMnemonic = $false; & $ui.Style $b ''; & $ui.Cue $b; & $ui.Own $b
  & $ui.FitBtn $b; $b.Add_TextChanged({ & $ui.FitBtn $this; & $ui.AutoName $this }); $b }   # gives back the button
# Creates an underlined flat link button with accessible name tracking and focus ring.
$ui.LinkBtn = { param([string]$Text)
  $b = New-Object System.Windows.Forms.Button; $b.Text = $Text; $b.AutoSize = $true; $b.AutoSizeMode = 'GrowAndShrink'
  $b.MinimumSize = New-Object System.Drawing.Size(0, $ui.Z.LinkH); $b.Margin = (& $ui.Pad $ui.Z.M $ui.Z.M $ui.Z.M $ui.Z.M)
  $b.UseMnemonic = $false; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
  $b.BackColor = $ui.C.White; $b.ForeColor = $ui.C.Link; $b.Font = $ui.F.Link; $ui.Links += $b
  try { $b.FlatAppearance.MouseOverBackColor = $ui.C.White; $b.FlatAppearance.MouseDownBackColor = $ui.C.Hair } catch { $null = $_ }   # no hover colors: the link still works
  & $ui.Cue $b; & $ui.Own $b; & $ui.AutoName $b; $b.Add_TextChanged({ & $ui.AutoName $this }); $b }   # a link: Air Force blue, semibold and underlined (not color alone), 28 high
$ui.Kinds = @{}; $ui.Links = @()   # the kind each button was last styled with; every link ($ui.Recolor styles them again)
# Bars: RADE draws them (R17). A 30 ms timer eases the fill to its value; with Windows animations off it jumps. No bar
# moves back inside a run (all) or a step (step). The bar on the bottom edge is all steps; the short one is this step.
$ui.DrawBar = { param($P, $G)
  try {
    $b = $ui.Bars[[string]$P.Tag]; $G.Clear($(if ($b.On) { $ui.C.Track } else { $ui.C.White }))
    $fw = [int][math]::Round($P.ClientSize.Width * $b.Shown)
    if ($b.On -and $fw -gt 0) {
      $br = New-Object System.Drawing.SolidBrush($b.Fill)
      $G.FillRectangle($br, 0, 0, $fw, $P.ClientSize.Height); $br.Dispose()
    }
  } catch { $null = $_ } }
# Makes one thin progress bar (a panel the engine draws itself) and registers it in $ui.Bars. Takes the bar name and its
# screen-reader label; gives back the panel.
$ui.MkBar = { param([string]$Name, [string]$Label)
  $p = New-Object System.Windows.Forms.Panel; $p.Height = 4; $p.Tag = $Name; $p.AccessibleRole = 'ProgressBar'; $p.AccessibleName = $Label; $p.AccessibleDescription = '0 %'
  try { [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic, Instance').SetValue($p, $true, $null) } catch { $null = $_ }
  $ui.Bars[$Name] = @{ Panel = $p; Target = 0.0; Shown = 0.0; On = $false; Fill = $ui.C.Info }   # progress: the Info color (dark: blue, not the ember of the main button)
  $p.Add_Paint({ & $ui.DrawBar $this $_.Graphics }); $p }
# Sets what a bar shows. Takes the bar name, the fraction (0 to 1) and whether it is on; the fill eases to it, and a
# smaller value jumps back at once. Gives back nothing.
$ui.SetBar = { param([string]$Name, [double]$Value, [bool]$On)
  $b = $ui.Bars[$Name]; $v = [math]::Max(0.0, [math]::Min(1.0, $Value))
  if ($v -lt $b.Target - 0.001 -or $ui.Calm) { $b.Shown = $v }   # a new step starts at 0 with no slide back
  $b.Target = $v; $b.On = $On; $b.Panel.AccessibleDescription = [string][int]($v * 100) + ' %'; $b.Panel.Invalidate() }
# ---- A contrast theme that changes while the window is open (UI standard v1, B11; backlog item 24)
# The form's SystemColorsChanged event (Windows sends WM_SYSCOLORCHANGE when a contrast theme comes on or goes off) calls
# $ui.Recolor on the window's own thread: PowerShell code cannot run on the thread of SystemEvents, and the event goes with
# the form when it closes, so nothing is left to detach. $ui.Roles keeps, for each control and color property, the token
# it was painted with (found from the colors it had), so a switch back gives each part its own color again.
$ui.Roles = @{}; $ui.Recolor = {
  <#
  .SYNOPSIS
  Paints the window again in the colors of the current Windows theme (its own colors, or a contrast theme's system colors).
  .DESCRIPTION
  Does nothing when the theme did not change, unless Force is set. Each property gets the color of its token (see above).
  .PARAMETER Force
  $true to paint again also when the theme did not change.
  .OUTPUTS
  Nothing.
  #>
  param([bool]$Force)
  $hi = [bool](& $ui.HighOn); if ($hi -eq [bool]$ui.High -and -not $Force) { return }
  try { $rev = @{}; foreach ($k in @($ui.Tok.Keys)) { $a = $ui.C[$k].ToArgb(); if (-not $rev.ContainsKey($a)) { $rev[$a] = $k } }   # the colors before the change: color -> token
    $todo = New-Object System.Collections.Stack; $todo.Push($ui.Form); $all = @()
    while ($todo.Count) { $c = $todo.Pop(); $all += $c; foreach ($k in @($c.Controls)) { $todo.Push($k) } }
    foreach ($c in $all) { if (-not $ui.Roles.ContainsKey($c)) { $ui.Roles[$c] = @{} }; $r = $ui.Roles[$c]
      foreach ($pp in 'ForeColor', 'BackColor') { try { $a = $c.$pp.ToArgb(); $t0 = [string]$r[$pp]   # the token it had keeps its place while its color is still on the control
          if (-not ($t0 -and $ui.C[$t0].ToArgb() -eq $a)) { $t = $rev[$a]; if ($t) { $r[$pp] = $t } } } catch { $null = $_ } } }   # a color that is no token stays as it is
    & $ui.UseColors $hi
    foreach ($c in $all) { $r = $ui.Roles[$c]; foreach ($pp in @($r.Keys)) { try { $c.$pp = $ui.C[[string]$r[$pp]] } catch { $null = $_ } } }   # a property that cannot be set keeps its color
    foreach ($b in @($ui.Kinds.Keys)) {
      try {
        $en = $b.Enabled; & $ui.Style $b ([string]$ui.Kinds[$b])
        if ([string]$ui.Kinds[$b] -notin 'off', 'dangeroff') { $b.Enabled = $en }
      } catch { $null = $_ }   # a button that is gone: nothing to paint
    }
    foreach ($b in @($ui.Links)) {
      try {
        $b.BackColor = $ui.C.White; $b.ForeColor = $ui.C.Link
        $b.FlatAppearance.MouseOverBackColor = $ui.C.White; $b.FlatAppearance.MouseDownBackColor = $ui.C.Hair
      } catch { $null = $_ }   # same: a link that is gone
    }
    if ($ui.CardNow -and -not $ui.RecOn -and -not $ui.Busy -and -not $ui.Running) {
      $k = @([string]$ui.Field.Text, [string]$ui.ErrBox.Text, [string]$ui.Note.Text); $on = $ui.LayOn; $ui.LayOn = $false
      try { & $ui.SetCard $ui.CardNow } finally { $ui.LayOn = $on }
      $ui.Field.Text = $k[0]; $ui.ErrBox.Text = $k[1]; & $ui.Say1 $k[2]
    }; $ui.Form.Invalidate($true) } catch { $null = $_ } }   # the card's own colors, typed text kept; never stops the window
# Where ink starts, ink-tight text, long words, shortened text, drawing and measuring ($ui.Ink to $ui.Meas): engine/rade_ui_text.ps1.
# ---- The layout self-check (docs/window-design.md "Proof"): in a test round, and in the Windows job, RADE measures each
# card it showed: a text that needs more room than its control has, a control that a parent cuts, two parts that
# overlap. The result is one line under "Window: OK" in the results e-mail draft ("PASS layout" or the defects), so a
# cut text is found by a measure, not by a person's eye. A deploy does not run it. It reads sizes only.
$ui.LayOn = $false; $ui.LayBad = New-Object System.Collections.Generic.List[string]; $ui.LaySeen = @{}; $ui.LayCards = @{}; $ui.LayScroll = @{}
try {
  $hasRender = [System.Windows.Forms.Application].GetMethod('SetCompatibleTextRenderingDefault')
  $hasTest = ($env:RADE_LAYOUT -eq '1' -or @($apps | Where-Object { [string]$_.Mode -ne 'deploy' }).Count)
  $ui.LayOn = [bool]($hasRender -and $hasTest)
} catch { $null = $_ }   # the real Windows Forms only: the test stand-ins have no layout
# Returns the $ui key name (or control type name) for a WinForms control.
$ui.NameOf = { param($C)
  foreach ($k in @($ui.Keys)) { if ([object]::ReferenceEquals($ui[$k], $C)) { return [string]$k } }
  foreach ($k in 'B', 'P') { for ($i = 0; $ui[$k] -and $i -lt @($ui[$k]).Count; $i++) { if ([object]::ReferenceEquals($ui[$k][$i], $C)) { return ($k + $i) } } }
  return $C.GetType().Name }
# ---- The alignment rules
# The alignment rules (docs/window-design.md "Sizes"), on measured numbers so the tests can give them a layout:
# RowBad: the parts of an aligned row (@{ N; Top; H; Kind }) share one midpoint within 1 px, and a box and a button in
# it are as tall as each other. EdgeBad: the visible left edges of a card's parts (@{ N; X }) are within 1 px.
$ui.RowBad = {
  <#
  .SYNOPSIS
  Checks alignment midpoints and box-to-button height parity for parts in a layout row.
  .DESCRIPTION
  Groups wrapping parts by margin top and reports layout defects when midpoints or box/button heights differ beyond 1 px.
  .PARAMETER Card
  Card view name used as the defect message prefix.
  .PARAMETER Row
  Row name used in defect messages.
  .PARAMETER Parts
  Array of part metric hashtables (N, Top, H, Line, Kind).
  .OUTPUTS
  Array of layout defect strings.
  #>
  param([string]$Card, [string]$Row, $Parts)
  # A row that wraps (the test extras in a small window) has a midpoint on each line: Line = the top of a part's margin box.
  $out = @(); $byLine = [ordered]@{}; foreach ($q in @($Parts | Where-Object { $_ })) { $k = [string][int]$q.Line; if (-not $byLine.Contains($k)) { $byLine[$k] = @() }; $byLine[$k] += $q }
  if ($byLine.Count -gt 1) { foreach ($k in @($byLine.Keys)) { $out += & $ui.RowBad $Card $Row @($byLine[$k] | ForEach-Object { $c = $_.Clone(); $c.Line = 0; $c }) }; return $out }
  $tol = [math]::Max(1, (& $ui.Sc 1)); $ps = @($Parts | Where-Object { $_ }); if ($ps.Count -lt 2) { return $out }
  $m0 = $ps[0].Top + $ps[0].H / 2.0
  foreach ($q in $ps) { $m = $q.Top + $q.H / 2.0; if ([math]::Abs($m - $m0) -gt $tol) { $out += ('LAYOUT ' + $Card + ' ' + $Row + ' ' + $q.N + ' midpoint: ' + $m + ', the row midpoint is ' + $m0) } }
  $bx = @($ps | Where-Object { $_.Kind -eq 'box' }); $bt = @($ps | Where-Object { $_.Kind -eq 'button' })
  foreach ($a in $bx) {
    foreach ($b in $bt) {
      if ([math]::Abs($a.H - $b.H) -gt $tol) { $out += ('LAYOUT ' + $Card + ' ' + $Row + ' heights: box ' + $a.N + ' ' + $a.H + ', button ' + $b.N + ' ' + $b.H) }
    }
  }
  return $out }
# Checks that all visible left ink edges on a card align within 1 scaled px.
$ui.EdgeBad = { param([string]$Card, $Edges)
  $out = @(); $tol = [math]::Max(1, (& $ui.Sc 1)); $es = @($Edges | Where-Object { $_ }); if ($es.Count -lt 2) { return $out }
  foreach ($e in $es) {
    if ([math]::Abs($e.X - $es[0].X) -gt $tol) {
      $extra = $(if ($e.D) { ' [' + $e.D + ']' } else { '' })
      $out += ('LAYOUT ' + $Card + ' ' + $e.N + ' edge: starts at ' + $e.X + ', the card edge is ' + $es[0].X + ' (' + $es[0].N + ')' + $extra)
    }
  }
  return $out }
# AboveBad (L3, the Administrator, 2026-11-19): a label above its box. The label's bottom is not under the box's top, the
# box starts on the card's edge and it is as wide as the card's text (from the edge to the end of the text column), each
# within 1 px (scaled). Takes the card and @{ LabelBottom; BoxTop; BoxLeft; BoxW; Edge; TextW }; gives back the defect lines.
$ui.AboveBad = { param([string]$Card, $M)
  $out = @(); $tol = [math]::Max(1, (& $ui.Sc 1))
  if ([int]$M.BoxTop -lt [int]$M.LabelBottom) { $out += ('LAYOUT ' + $Card + ' FieldRow label: its bottom is at ' + $M.LabelBottom + ', the box starts at ' + $M.BoxTop) }
  if ([math]::Abs([int]$M.BoxLeft - [int]$M.Edge) -gt $tol) { $out += ('LAYOUT ' + $Card + ' FieldBox edge: starts at ' + $M.BoxLeft + ', the card edge is ' + $M.Edge) }
  if ([math]::Abs([int]$M.BoxW - [int]$M.TextW) -gt $tol) { $out += ('LAYOUT ' + $Card + ' FieldBox width: ' + $M.BoxW + ', the card text is ' + $M.TextW + ' wide') }
  return $out }
# FrameBad (L1, the Administrator, 2026-11-19): the card frame. The header row starts at the frame's fixed top (so it is at
# the same place on every card of one window size), and the frame is as tall as its minimum at least, each within 1 px
# (scaled). A card that had to move up to fit (Moved) is not measured. Takes the card and @{ Top; WantTop; H; MinH; Moved };
# gives back the defect lines.
$ui.FrameBad = { param([string]$Card, $M)
  $out = @(); $tol = [math]::Max(1, (& $ui.Sc 1)); if ($M.Moved) { return $out }
  if ([math]::Abs([int]$M.Top - [int]$M.WantTop) -gt $tol) { $out += ('LAYOUT ' + $Card + ' frame: the header row is at ' + $M.Top + ', the fixed top is ' + $M.WantTop) }
  if ([int]$M.H + $tol -lt [int]$M.MinH) { $out += ('LAYOUT ' + $Card + ' frame: ' + $M.H + ' high, the minimum is ' + $M.MinH) }
  return $out }
# TickBad (R29b N3): the step's time or count (@{ N; Top; H }) has its vertical center within 1 px of the bar's (@{ Top; H }),
# at any scale (the tolerance is not scaled).
$ui.TickBad = { param([string]$Card, $Bar, $Tick)
  $mb = $Bar.Top + $Bar.H / 2.0; $mt = $Tick.Top + $Tick.H / 2.0
  if ([math]::Abs($mt - $mb) -le 1) { return @() }
  return @('LAYOUT ' + $Card + ' StepRow ' + $Tick.N + ' midpoint: ' + $mt + ', the bar midpoint is ' + $mb) }
# ---- The self-check walk
# Returns $true when control $C is a read-only selectable card text box.
$ui.IsCardText = { param($C) return [bool](($C -is [System.Windows.Forms.TextBox]) -and $C.ReadOnly -and -not $C.TabStop -and $ui.Wrap.ContainsKey($C)) }
# What a card text box needs, as its edit control wraps the text now (the line count it reports), else as measured.
$ui.TextNeed = { param($C)
  $w = [int](& $ui.GetWrap $C); $s = & $ui.Meas ([string]$C.Text) $C.Font $(if ($w -gt 0) { $w } else { 100000 }); $h = [int]$s.Height + (& $ui.Sc 2)
  try {
    $n = [int]$C.GetLineFromCharIndex([math]::Max(0, $C.Text.Length - 1)) + 1
    $lh = [int][System.Windows.Forms.TextRenderer]::MeasureText('Ag', $C.Font).Height
    if ($n -gt 0 -and $lh -gt 0) { $h = [math]::Max($h, $n * $lh) }
  } catch { $null = $_ }
  return (New-Object System.Drawing.Size($s.Width, $h)) }
# ---- UI standard v1 rules of the self-check (the Administrator, 2026-11-20; docs/ui-standard.md, each rule's check)
# The WCAG relative luminance of a color (0 to 1). Takes the color; gives back a number.
$ui.Lum = { param($C)
  $v = foreach ($x in @($C.R, $C.G, $C.B)) {
    $f = [double]$x / 255.0
    if ($f -le 0.04045) { $f / 12.92 } else { [math]::Pow(($f + 0.055) / 1.055, 2.4) }
  }
  0.2126 * $v[0] + 0.7152 * $v[1] + 0.0722 * $v[2] }
# The WCAG contrast ratio of two colors (1 to 21). Takes the two colors; gives back a number.
$ui.Ratio = { param($A, $B) $x = & $ui.Lum $A; $y = & $ui.Lum $B; ([math]::Max($x, $y) + 0.05) / ([math]::Min($x, $y) + 0.05) }
# B1 (fixed sizes) for one button with an edge: no AutoSize, a size of the set, and a label that fits. Takes the card,
# the button's name and the button; gives back the defect lines.
$ui.BtnBad = { param([string]$Card, [string]$Name, $B)
  $out = @(); $ws = @($ui.Z.CompactW, $ui.Z.ActionW, $ui.Z.WideW | ForEach-Object { & $ui.Sc $_ }); $hs = @($ui.Z.CompactH, $ui.Z.ActionH | ForEach-Object { & $ui.Sc $_ })
  if ($B.AutoSize) { $out += ('LAYOUT ' + $Card + ' ' + $Name + ' button: AutoSize is on (B1: fixed sizes)') }
  if ($ws -notcontains [int]$B.Width -or $hs -notcontains [int]$B.Height) { $out += ('LAYOUT ' + $Card + ' ' + $Name + ' button: ' + $B.Width + 'x' + $B.Height + ' is not a size of the set (B1)') }
  $need = [int][System.Windows.Forms.TextRenderer]::MeasureText([string]$B.Text, $B.Font).Width + (& $ui.Sc 4)
  if ($B.Text -and $need -gt [int]$B.Width) { $out += ('LAYOUT ' + $Card + ' ' + $Name + ' button text cut: needs ' + $need + ' has ' + $B.Width + ' (B1)') }
  return $out }
# B3, B4, B5 for the card's action row: at most one primary button, and it is the last one; at most 3 others ("Back (Esc)"
# is the Back pattern, not counted). Takes the card and the kinds of the shown buttons in row order; gives back the lines.
$ui.RowRuleBad = { param([string]$Card, $Kinds)
  $out = @(); $ks = @($Kinds); $main = @(for ($k = 0; $k -lt $ks.Count; $k++) { if ([string]$ks[$k] -eq 'primary') { $k } })
  if ($main.Count -gt 1) { $out += ('LAYOUT ' + $Card + ' buttons: ' + $main.Count + ' primary buttons, the rule is one (B4)') }
  if ($main.Count -eq 1 -and $main[0] -ne $ks.Count - 1) { $out += ('LAYOUT ' + $Card + ' buttons: the primary button is number ' + ($main[0] + 1) + ' of ' + $ks.Count + ', the rule is last (B3)') }
  if ($ks.Count - $main.Count -gt 3) { $out += ('LAYOUT ' + $Card + ' buttons: ' + ($ks.Count - $main.Count) + ' buttons beside the primary, the rule is 3 at most (B5)') }
  return $out }
# Inventory (RADE_INVENTORY = a file path; the Windows job): one JSON line for each control the self-check walks, with
# the card, the scale, the kind, the screen box, the colors and the accessible name (docs/ui-standard.md "Proof").
$ui.InvFile = [string]$env:RADE_INVENTORY
# Writes the inventory line of one control. Takes the card, the control and its screen box.
$ui.InvLine = { param([string]$Card, $C, $R)
  try { $o = [ordered]@{ card = $Card; scale = [int][math]::Round($ui.Dpi / 96.0 * 100); high = [bool]$ui.High; kind = $C.GetType().Name; name = (& $ui.NameOf $C)
      x = [int]$R.Left; y = [int]$R.Top; w = [int]$R.Width; h = [int]$R.Height; fore = '#{0:X6}' -f ($C.ForeColor.ToArgb() -band 0xFFFFFF); back = '#{0:X6}' -f ($C.BackColor.ToArgb() -band 0xFFFFFF)
      access = [string]$C.AccessibleName; button = [string]$ui.Kinds[$C] }
    Add-Content -LiteralPath $ui.InvFile -Value (ConvertTo-Json $o -Compress) -Encoding UTF8 -ErrorAction Stop } catch { $null = $_ } }   # the inventory is a test aid: never stop the check
# Checks a single visible control inside a container for layout, contrast, clipping, and text fit defects.
$ui.CheckControl = {
  <#
  .SYNOPSIS
  Checks a single visible control inside a card or Details view for layout and contrast defects.
  .DESCRIPTION
  Verifies accessible names, box scaling, button sizing, contrast ratio, clipping, wrapping labels,
  card text boxes, checkboxes, RichTextBox guide height, and label preferred size fit.
  .PARAMETER Card
  Card or Details view identifier for defect messages.
  .PARAMETER C
  Control instance being inspected.
  .PARAMETER R
  Screen rectangle of the control.
  .PARAMETER Clip
  Parent clipping rectangle in screen coordinates.
  .PARAMETER Scroll
  Whether the control lies inside a scrollable region.
  .OUTPUTS
  None.
  #>
  param([string]$Card, $C, $R, $Clip, [bool]$Scroll)
  $nm = & $ui.NameOf $C; if ($ui.InvFile) { & $ui.InvLine $Card $C $R }
  if ($C.CanSelect -and $C.TabStop -and -not [string]$C.AccessibleName) { $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ': no accessible name') }
  $minBoxH = & $ui.Sc $ui.Z.CompactH
  if ($ui.Boxes -contains $C -and [int]$C.Height + 1 -lt $minBoxH) {
    $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' box: ' + $C.Height + ' high, the rule is ' + $minBoxH + ' (B1; R36: a frame that did not scale cut its line at 150 %)') }
  if ($C -is [System.Windows.Forms.Button] -and [int]$C.FlatAppearance.BorderSize -gt 0 -and $ui.BtnKind.ContainsKey($C)) {
    foreach ($l in @(& $ui.BtnBad $Card $nm $C)) { $ui.LayBad.Add([string]$l) } }
  if ($C.Text -and $C.Enabled -and ($C -is [System.Windows.Forms.Label] -or $C -is [System.Windows.Forms.ButtonBase] -or (& $ui.IsCardText $C))) {
    $cr = & $ui.Ratio $C.ForeColor $C.BackColor
    if ($cr -lt 4.5) { $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' contrast: ' + [math]::Round($cr, 2) + ':1, the rule is 4.5:1 (B10)') } }
  if (-not $Scroll -and -not $Clip.Contains($R)) {
    $pos = ($R.Left - $Clip.Left).ToString() + ',' + ($R.Top - $Clip.Top).ToString()
    $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' cut: needs ' + $R.Width + 'x' + $R.Height + ' at ' + $pos + ' in ' + $Clip.Width + 'x' + $Clip.Height) }
  if ($C -is [System.Windows.Forms.Label] -and $C.AutoSize -and $C.MaximumSize.Width -gt 0 -and $C.Text) {
    $wb = & $ui.WordBad $Card $nm ([string]$C.Text) $C.Font $C.MaximumSize.Width; if ($wb) { $ui.LayBad.Add($wb) } }
  if (& $ui.IsCardText $C) {
    if ([int](& $ui.GetWrap $C) -gt 0 -and $C.Text) { $wb = & $ui.WordBad $Card $nm ([string]$C.Text) $C.Font ([int](& $ui.GetWrap $C)); if ($wb) { $ui.LayBad.Add($wb) } }
    $nd = & $ui.TextNeed $C; $lh1 = [int][System.Windows.Forms.TextRenderer]::MeasureText('Ag', $C.Font).Height
    if ($C.Text -and ($nd.Height -gt $C.ClientSize.Height + 1 -or $nd.Width -gt $C.ClientSize.Width + 1)) {
      $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' text: needs ' + $nd.Width + 'x' + $nd.Height + ' has ' + $C.ClientSize.Width + 'x' + $C.ClientSize.Height) }
    if ($C.Text -and -not $ui.Hold.ContainsKey($C) -and $C.ClientSize.Height -gt $nd.Height + $lh1) {
      $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' dead space: has ' + $C.ClientSize.Height + ' high, the text needs ' + $nd.Height) } }
  if ($C -is [System.Windows.Forms.CheckBox] -and $C.Text -and -not $C.AutoEllipsis) {
    $tw = [System.Windows.Forms.TextRenderer]::MeasureText([string]$C.Text, $C.Font).Width
    if ($tw -gt $C.ClientSize.Width + 1) { $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' text cut: needs ' + $tw + ' has ' + $C.ClientSize.Width) } }
  if ($C.Text -and ($C -is [System.Windows.Forms.Label] -or $C -is [System.Windows.Forms.ButtonBase] -or $C -is [System.Windows.Forms.TextBoxBase])) {
    $lh = [int](& $ui.LineH $C.Font); if ($C -is [System.Windows.Forms.TextBoxBase]) { $lh = [int][math]::Floor($lh * 0.8) }
    if ($C.ClientSize.Height + 1 -lt $lh) { $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' line cut: one line needs ' + $lh + ' high, has ' + $C.ClientSize.Height) } }
  if ($C -is [System.Windows.Forms.RichTextBox] -and $ui.GuideNeed -and [object]::ReferenceEquals($C, $ui.Guide)) {
    $gn = [int](& $ui.GuideNeed); if ($gn -gt $C.ClientSize.Height + 1) { $ui.LayBad.Add('LAYOUT ' + $Card + ' Guide text: needs ' + $gn + ' high, has ' + $C.ClientSize.Height) } }
  if (($C -is [System.Windows.Forms.Label] -or $C -is [System.Windows.Forms.ButtonBase]) -and $C.Text -and -not $C.AutoEllipsis -and -not $ui.BtnKind.ContainsKey($C)) {
    $want = $C.GetPreferredSize((New-Object System.Drawing.Size($C.Width, 0)))
    if ($want.Width -gt $C.Width + 1 -or $want.Height -gt $C.Height + 1) {
      $ui.LayBad.Add('LAYOUT ' + $Card + ' ' + $nm + ' text: needs ' + $want.Width + 'x' + $want.Height + ' has ' + $C.Width + 'x' + $C.Height) } } }
# Runs the layout self-check on the currently visible card and records any defects in $ui.LayBad.
$ui.Check = {
  <#
  .SYNOPSIS
  Runs the layout self-check on the currently visible card or Details view and appends defects to $ui.LayBad.
  .DESCRIPTION
  Walks visible controls once per card/title/size combination to verify layout, clipping, overlap, dead space,
  button row rules, and alignment rules.
  .OUTPUTS
  None.
  #>
  if (-not $ui.LayOn -or -not $ui.View) { return }
  if ($ui.Picked -and (Test-Deploy) -and $env:RADE_LAYOUT -ne '1') { return }
  $card = $(if ($ui.RecOn) { 'record' } else { [string]$ui.View })
  try {
    if (-not $ui.Form.Visible -or [string]$ui.Form.WindowState -eq 'Minimized') { return }
    $key = $card + '|' + $ui.View + '|' + $ui.Sent.Text + '|' + $ui.Kick.Text; $ui.LayCards[$key] = 1
    $key += '|' + $ui.Form.ClientSize.Width + 'x' + $ui.Form.ClientSize.Height; if ($ui.LaySeen.ContainsKey($key)) { return }; $ui.LaySeen[$key] = 1
    if ($ui.Scrolls -and -not $ui.RecOn) { $ui.LayScroll[$card] = 1 }
    $todo = New-Object System.Collections.Stack; $todo.Push(@($ui.Form, $ui.Form.RectangleToScreen($ui.Form.ClientRectangle), $false))
    while ($todo.Count) {
      $it = $todo.Pop(); $par = $it[0]; $clip = $it[1]; $scroll = $it[2]
      $kids = @($par.Controls | Where-Object { $_.Visible })
      for ($i = 0; $i -lt $kids.Count; $i++) {
        $c = $kids[$i]; $r = $c.RectangleToScreen($c.ClientRectangle); if ($r.Width -le 0 -or $r.Height -le 0) { continue }
        & $ui.CheckControl $card $c $r $clip $scroll
        for ($j = $i + 1; $j -lt $kids.Count; $j++) {
          if ($c.Bounds.IntersectsWith($kids[$j].Bounds)) { $ui.LayBad.Add('LAYOUT ' + $card + ' ' + (& $ui.NameOf $c) + ' overlaps ' + (& $ui.NameOf $kids[$j])) }
        }
        $sc2 = [bool]$c.AutoScroll; if ([object]::ReferenceEquals($c, $ui.Scroll)) { $sc2 = [bool]$ui.Scrolls }
        if ($c.Controls.Count) { $todo.Push(@($c, [System.Drawing.Rectangle]::Intersect($clip, $r), ($scroll -or $sc2))) }
      }
    }
    if ($ui.Scroll -and $ui.Body -and -not $ui.RecOn -and -not $ui.Scrolls -and $ui.Scroll.Visible) {
      $dead = [int]$ui.Scroll.ClientSize.Height - [int]$ui.Body.Height
      if ($dead -gt (& $ui.Sc 2)) { $ui.LayBad.Add('LAYOUT ' + $card + ' Scroll dead space: ' + $dead + ' px under the text') }
    }
    if (-not $ui.RecOn) { foreach ($l in @(& $ui.RowRuleBad $card @($ui.B | Where-Object { $_.Visible } | ForEach-Object { [string]$ui.Kinds[$_] }))) { $ui.LayBad.Add([string]$l) } }
    foreach ($l in @(& $ui.Measure $card)) { $ui.LayBad.Add([string]$l) }
  } catch { $ui.LayBad.Add('LAYOUT ' + $card + ' the self-check stopped: ' + (ConvertTo-Masked ([string]$_.Exception.Message))) } }

# RADE shared UI file, part 2 (engine/rade_ui_text.ps1): where ink starts, long words and
# one-line texts, shortened text, and drawing and measuring ($ui.Ink to $ui.Meas). Moved out of engine/rade_ui.ps1 on
# 2026-11-23 to keep each file at 450 lines or fewer (fleet v2 DEC 6). rade_build.py puts it into every bundle right
# after engine/rade_ui.ps1, at the same marker line; an app window that copies engine/rade_ui.ps1 copies this file after
# it, as it is. Its code runs when the window calls it (no part of engine/rade_ui.ps1 calls it while it loads).
# ASCII only (a bundle is ASCII). Needs from engine/rade_ui.ps1: $ui.Sc, $ui.Pad, $ui.C, $ui.FontDpi, $ui.Scaled, $ui.Trash.
# Network: none.
# Writes: none (it measures and draws on the window only).
# Credentials: none.
# ---- Where ink starts
$ui.Inks = @{}
$ui.Ink = {
  <#
  .SYNOPSIS
  Gives how far in from a control's left edge its ink starts, in pixels (the alignment rules: docs/window-design.md "Sizes").
  .DESCRIPTION
  Measured on what Windows drew (DrawToBitmap) and kept for each control kind, font, text start and size; an estimate
  from the font size when it cannot be measured (the estimate is not kept). A button with an edge gives 0.
  .PARAMETER C
  The control.
  .OUTPUTS
  The number of pixels, as an int.
  #>
  param($C)
  if ($C -is [System.Windows.Forms.ButtonBase] -and [int]$C.FlatAppearance.BorderSize -gt 0) { return 0 }
  # R28 (the Kick fix): the control is brought to the size the layout will give it BEFORE the cache key is made. The key held
  # the width the control had before it was resized, so a text measured at one width was used for another.
  try { if ($C.AutoSize -and $C.Text) { $pz = $C.PreferredSize; if ($C.Width -ne $pz.Width -or $C.Height -ne $pz.Height) { $C.Size = $pz } } } catch { $null = $_ }
  $f = $C.Font; $k = $C.GetType().Name + '|' + $f.Name + '|' + $f.SizeInPoints + '|' + $f.Style + '|' + ([string]$C.Text).PadRight(2).Substring(0, 2) + '|' +
    $(if ($C -is [System.Windows.Forms.ButtonBase] -or $C -is [System.Windows.Forms.Panel]) { [string]$C.Width + 'x' + $C.Height } else { '' })
  if ($ui.Inks.ContainsKey($k)) { return [int]$ui.Inks[$k] }
  $v = [int][math]::Ceiling([double]$f.SizeInPoints * $ui.FontDpi / 72.0 / 6.0); $got = $false
  if (-not $C.Text -and -not ($C -is [System.Windows.Forms.Panel])) { return $v }   # nothing drawn: nothing to measure
  try { $w = [math]::Max(1, $C.Width); $h = [math]::Max(1, $C.Height); $bm = New-Object System.Drawing.Bitmap($w, $h)
    try { $C.DrawToBitmap($bm, (New-Object System.Drawing.Rectangle(0, 0, $w, $h))); $bg = $C.BackColor; $hit = -1
      for ($x = 0; $x -lt [math]::Min($w, (& $ui.Sc 40)) -and $hit -lt 0; $x++) { for ($y = 0; $y -lt $h; $y++) { $px = $bm.GetPixel($x, $y); if ([math]::Abs($px.R - $bg.R) +
        [math]::Abs($px.G - $bg.G) + [math]::Abs($px.B - $bg.B) -gt 90) { $hit = $x; break } } }
      if ($hit -ge 0) { $v = $hit; $got = $true } } finally { $bm.Dispose() } } catch { $null = $_ }
  if ($got) { $ui.Inks[$k] = $v }; return $v }   # only a measure is kept; the estimate is tried again next time
# Sets the left margin of a control to L pixels (0 at least), only when it differs. Takes the control and the margin.
$ui.SetLeft = { param($C, [int]$L) $L = [math]::Max(0, $L); $m = $C.Margin; if ($m.Left -ne $L) { $C.Margin = New-Object System.Windows.Forms.Padding($L, $m.Top, $m.Right, $m.Bottom) } }
# ---- Long words and one-line texts
# A word wider than the line (no space in it) is cut into pieces that fit, one per line: it wraps by character and is
# never clipped (R7 review). Only what the window shows changes; the report keeps the text.
# The width a label needs to show a text in one line: asked of a label that is never shown, with the same font and flags
# as the window's labels (R24 job: TextRenderer's default flags gave 3 to 9 px more than a label uses).
$ui.Probe = New-Object System.Windows.Forms.Label; $ui.Probe.AutoSize = $true; $ui.Probe.UseMnemonic = $false;
  $ui.Trash = @(@($ui.Trash) | Where-Object { $_ }) + @($ui.Probe)   # disposed when the window has closed
# The width a label needs to show a text in one line ($ui.Probe). Takes the text and the font; gives back pixels.
$ui.WordW = { param([string]$T, $F) try { $ui.Probe.Font = $F; $ui.Probe.Text = $T; return [int]$ui.Probe.PreferredSize.Width } catch { return [int][System.Windows.Forms.TextRenderer]::MeasureText($T,
  $F).Width } }
$ui.Most = @{}   # the widest values of each label of changing values ($ui.FixW)
# A label that shows changing values (a percent, a count, a time; $ui.Most[label] = the widest values it can show) keeps one
# size: as wide as the widest of them and one line tall, so nothing beside it moves when the value changes (the
# Administrator, 2026-11-19). A value wider than all of them still fits: the label grows for it. Does nothing before the
# window has its scale (Windows Forms would scale the size again). Takes the label; gives back nothing.
$ui.FixW = { param($L) if (-not $ui.Scaled) { return }
  try { $w = 0; foreach ($x in @(@($ui.Most[$L]) + @([string]$L.Text) | Where-Object { $_ })) { $w = [math]::Max($w, (& $ui.WordW ([string]$x) $L.Font)) }
    $ui.Probe.Font = $L.Font; $ui.Probe.Text = '0'; $h = [int]$ui.Probe.PreferredSize.Height; if ($L.AutoSize) { $L.AutoSize = $false }
    if ($L.Width -ne $w -or $L.Height -ne $h) { $L.Size = New-Object System.Drawing.Size($w, $h) } } catch { $null = $_ } }   # no measure: the next fit sets it
# The height of one line of text in a font, as Windows draws it (TextRenderer: on a 150 % screen it can be taller than
# what a text box gives itself; R35 "Field line cut: one line needs 32 high, has 27"). Takes the font; gives back pixels.
$ui.LineH = { param($Font) [int][System.Windows.Forms.TextRenderer]::MeasureText('Ag', $Font).Height }
$ui.BreakLong = {
  <#
  .SYNOPSIS
  Cuts each word of a text that is wider than the line into pieces that fit, one per line (the comment above).
  .PARAMETER T
  The text.
  .PARAMETER F
  The font it shows in.
  .PARAMETER W
  The line width, in pixels (0 or less: the text is not changed).
  .OUTPUTS
  The text with the long words cut, as a string; the line breaks of the text are kept.
  #>
  param([string]$T, $F, [int]$W)
  if ($W -le 0 -or -not $T) { return $T }
  $parts = foreach ($ln in ($T -split '(\r?\n)')) {   # line by line; the line breaks are kept
    if ($ln -match '^\r?\n$') { $ln; continue }
    $ws = foreach ($wd in ($ln -split ' ')) {
      if ((& $ui.WordW $wd $F) -le $W) { $wd; continue }
      # by text element (M4 review): a surrogate pair or a letter with its accents is never split
      $pc = @(); $cur = ''; $en = [System.Globalization.StringInfo]::GetTextElementEnumerator($wd)
      while ($en.MoveNext()) { $ch = [string]$en.GetTextElement(); if ($cur -and (& $ui.WordW ($cur + $ch) $F) -gt $W) { $pc += $cur; $cur = '' }; $cur += $ch }
      $pc += $cur; $pc -join "`n" }
    @($ws) -join ' ' }
  return (@($parts) -join '') }
# ---- Shortened text
# A one-line text cut to fit a width with "..." at the end, measured by the control itself (M5 review: no AutoEllipsis,
# which shows a tooltip). Binary search on the number of text elements.
$ui.Shorten = { param($C, [string]$Full, [int]$W)
  $C.Text = $Full; if ($C.PreferredSize.Width -le $W) { return }
  $si = New-Object System.Globalization.StringInfo($Full); $lo = 0; $hi = $si.LengthInTextElements
  while ($lo -lt $hi) { $mid = [int][math]::Ceiling(($lo + $hi) / 2.0); $C.Text = $si.SubstringByTextElements(0, $mid).TrimEnd() + '...';
    if ($C.PreferredSize.Width -le $W) { $lo = $mid } else { $hi = $mid - 1 } }
  $C.Text = $(if ($lo -gt 0) { $si.SubstringByTextElements(0, $lo).TrimEnd() } else { '' }) + '...' }
# Cuts a text to N lines with "..." (the help below).
$ui.FitLines = {
  <#
  .SYNOPSIS
  Cuts a text to at most N lines at a width, with "..." at its end when it is cut (the Administrator, 2026-11-19).
  .DESCRIPTION
  Measured as a card text box wraps ($ui.Meas). Binary search on the number of text elements, so a letter with its accents
  is never split. The text is not changed when it fits.
  .PARAMETER T
  The text.
  .PARAMETER F
  The font it shows in.
  .PARAMETER W
  The wrap width, in pixels.
  .PARAMETER N
  The most lines it may take.
  .OUTPUTS
  The text that fits, as a string.
  #>
  param([string]$T, $F, [int]$W, [int]$N)
  if (-not $T -or $W -le 0 -or $N -le 0) { return $T }
  $most = $N * (& $ui.Meas 'Ag' $F 100000).Height
  if ((& $ui.Meas $T $F $W).Height -le $most) { return $T }
  $si = New-Object System.Globalization.StringInfo($T); $lo = 0; $hi = $si.LengthInTextElements
  while ($lo -lt $hi) { $mid = [int][math]::Ceiling(($lo + $hi) / 2.0); $x = $si.SubstringByTextElements(0, $mid).TrimEnd() + '...';
    if ((& $ui.Meas $x $F $W).Height -le $most) { $lo = $mid } else { $hi = $mid - 1 } }
  return ($(if ($lo -gt 0) { $si.SubstringByTextElements(0, $lo).TrimEnd() } else { '' }) + '...') }
# The self-check's rule for it: a word of a text that wraps is never wider than the line the text may take (a label's
# MaximumSize, a card text box's $ui.GetWrap; else the word is cut). Not the label's own width: a wrapping label is as wide
# as its widest line by its own measure, about 1 % narrower than the probe's, so a cut piece that is the widest line would
# always seem too wide (R28 job: 591/588, 597/591, 592/588).
$ui.WordBad = { param([string]$Card, [string]$Name, [string]$Text, $F, [int]$W)
  foreach ($wd in ($Text -split '\s+')) { if ($wd) { $ww = & $ui.WordW $wd $F; if ($ww -gt $W + 1) { return ('LAYOUT ' + $Card + ' ' + $Name + ' text: the word "' +
    $(if ($wd -match '[\\/]') { '<a path>' } elseif ($wd.Length -gt 20) { $wd.Substring(0, 20) + '...' } else { $wd }) + '" needs ' + $ww + ', the line is ' + $W) } } }
  return $null }
# ---- Drawing and measuring
# Draws a text in a box with TextRenderer. Takes the Graphics, the text, the font, the color, the box and the flags.
$ui.Word = { param($G, [string]$Text, $Font, $Color, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Flags) [System.Windows.Forms.TextRenderer]::DrawText($G, $Text, $Font,
  (New-Object System.Drawing.Rectangle($X, $Y, [math]::Max(1, $W), $H)), $Color, [System.Windows.Forms.TextFormatFlags]$Flags) }
# The size of a text that wraps at a width (the real font; docs/window-design.md "Text lengths").
$ui.Meas = { param([string]$Text, $Font, [int]$W) [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font, (New-Object System.Drawing.Size([math]::Max(1, $W), 0)),
  [System.Windows.Forms.TextFormatFlags]'WordBreak, NoPrefix, TextBoxControl') }
# ---- Copy and paste of card text (moved from engine/rade_ui.ps1 for engine-v48, to keep it at 450 lines or fewer)
# Copy gives the text as written (R28 N4): a word that RADE broke to fit a line is whole again (the break is a lone line feed), and the
# lines of a hand step (a rich text box) lose the tabs of their number column: "1. Open the page." on its own line.
$ui.CopyText = { param($C)
  try { if (-not ($C -is [System.Windows.Forms.TextBoxBase]) -or $C.SelectionLength -le 0) { return $false }
    $s = [string]$C.SelectedText
    if ($C -is [System.Windows.Forms.RichTextBox]) { $s = ($s -replace '\r?\n', "`n" -replace ([string][char]0x2007), '' -replace '\t', ' ') -replace "`n", "`r`n" }
    elseif (& $ui.IsCardText $C) { $s = $s -replace '(?<!\r)\n', '' }
    if ($s) { [System.Windows.Forms.Clipboard]::SetText($s); return $true } } catch { $null = $_ }
  return $false }
# R34 (the Administrator: the answer box did not take a pasted block): a one-line box keeps only the first line of a paste, so a
# paste into it comes here. $ui.OneLine joins the lines of a text with one space and cuts it to the room that is left.
# Takes the text and the room (characters); gives back the text to put in.
$ui.OneLine = { param([string]$T, [int]$Room)
  $s = ($T -replace '\s*(\r\n|\r|\n)\s*', ' ' -replace '\t', ' ').Trim(); if ($Room -lt 0) { $Room = 0 }; if ($s.Length -gt $Room) { $s = $s.Substring(0, $Room) }; return $s }

# The title-bar and taskbar icon: the app logo for an app with productName and a logo (engine-v47), else RADE's logo
# (Fulcrum, the Administrator, 2026-11-20); drawn at 32 px from the bundle's PNG. In the dark mode the app's logoDark when it has
# one (plan engine-v48 D6): $ui.AppPng is the app logo of the theme, for the icon and the band (02-fixed-parts.ps1).
$ui.AppPng = $(if ($ui.Dark -and -not $ui.High -and [string]$appLogoDarkPng) { [string]$appLogoDarkPng } else { [string]$appLogoPng })
try {
  $ib = New-Object System.Drawing.Bitmap((New-Object System.IO.MemoryStream(, [System.Convert]::FromBase64String($(if ([string]$appProduct -and $ui.AppPng) { $ui.AppPng } else { $logoPng })))))
  $ui.Form.Icon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap($ib, 32, 32)).GetHicon())
} catch { $null = $_ }   # a logo System.Drawing cannot read keeps the default icon
$ui.Form.ClientSize = New-Object System.Drawing.Size(1020, 760)   # at 100 %; the minimum size is set when the window has its scale (Shown)
$ui.Form.StartPosition = 'CenterScreen'; $ui.Form.KeyPreview = $true; $ui.Form.BackColor = $ui.C.White
$ui.Form.ShowInTaskbar = $true; $ui.Form.MinimizeBox = $true   # its own taskbar button: a minimized window can be restored (R24)

