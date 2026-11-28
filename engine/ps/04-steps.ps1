# RADE engine part 04, steps: runs one step as a child process, runs a hand (guide) step, builds the step
# lines, the results folder and the round plan, and makes the Outlook draft. Called by 06-round.ps1.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# Builds the start information of a step's child powershell.exe (pwsh when there is none): the step file with -Id and
# -NoPause, the round's fixed arguments, the person's answer as -<AskParam>, and the step's input variables.
# Takes the RADE app folder, the step and the answer; returns the ProcessStartInfo (nothing is started here).
function Get-StepStartInfo([string]$Base, $Step, [string]$Answer, [scriptblock]$Say) {
  $exe = 'powershell.exe'
  if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { $exe = 'pwsh' }
  $dir = Join-Path $Base $Step.Dir
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = '-NoProfile -File "' + (Join-Path $dir $Step.File) + '" -Id "' + $script:dodid + '" -NoPause'
  if ($Step.Args) { $psi.Arguments += ' ' + $Step.Args }   # fixed arguments from the round (for example -Set T12)
  if ($Step.AskParam -and $Answer) {
    # A trailing \ before the closing quote would escape it (command-line rules): trim it, but a drive root keeps its \,
    # doubled so "D:\\" reads back as D:\ (review R08).
    $a = $Answer; if ($a.Length -gt 3) { $a = $a.TrimEnd('\') }
    if ($a.EndsWith('\')) { $a += '\' }
    $psi.Arguments += ' -' + $Step.AskParam + ' "' + $a + '"'
  }
  $psi.WorkingDirectory = $dir
  # No -ExecutionPolicy setting (fleet v2, DEC 3: Group Policy governs). A RADE started from an old shortcut hands its
  # setting down in this variable as "Bypass": take only that value out (any other value a person set stays), so a step
  # runs as the child check proved it can.
  if ($psi.EnvironmentVariables['PSExecutionPolicyPreference'] -ceq 'Bypass') { $psi.EnvironmentVariables.Remove('PSExecutionPolicyPreference') }
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  try { $envs = Get-StepEnv $Base $Step; foreach ($k in @($envs.Keys)) { $psi.EnvironmentVariables[[string]$k] = [string]$envs[$k] } } catch { & $Say ('    NOTE: the step inputs could not be set: ' + (ConvertTo-Masked $_.Exception.Message)) }
  return $psi
}

# Reads one output line of a running step (the step contract, docs/engine.md "Step contract"): masks it, then a
# PROGRESS line moves the step bar, a NOW line goes to the window's now-doing line, a MADE line goes to the undo list, a FALLBACK line names the fallback route, and any
# other line is logged and counted as PASS, SKIP or FAIL. Takes the line, the step, the result record $R (changed in
# place), the site address (for cleaned names) and the log callback; returns nothing.
function Add-StepLine([string]$Line, $Step, $R, [string]$Site, [scriptblock]$Say) {
  $line = ConvertTo-Masked $Line
  # "PROGRESS n/m" (or "n of m") from a step script moves the step bar and stays out of the log (PFM 14 Nov 26).
  if ($line -match '^\s*PROGRESS\s+(\d+)\s*(?:/|of)\s*(\d+)\s*$') {
    if ($script:prog -and [int]$Matches[2] -gt 0) { $script:prog.Frac = [math]::Min(1.0, [double]$Matches[1] / [double]$Matches[2]); $script:prog.FracText = $Matches[1] + ' of ' + $Matches[2] }
    return
  }
  # "NOW <text>" (L7): the step says in plain words what it does now. The window shows it under the step's bar; it stays
  # out of the log and is not a result.
  if ($line -cmatch '^\s*NOW\s+(\S.*)$') { if ($script:nowUi) { & $script:nowUi $Matches[1].Trim() }; return }
  # "MADE <kind>: <name>": something the step created (a list, a flow, a file); kept for the undo list (step contract).
  # A MADE line is never a result: it is logged with the cleaned name and not counted as PASS, FAIL or SKIP (review).
  if ($line -cmatch '^\s*MADE\s+([a-z][a-z-]{0,30}):\s+(\S.*)$') {
    $mk = $Matches[1]; $mn = ConvertTo-MadeName $Matches[2] $Site; $R.Made += @{ kind = $mk; name = $mn }
    & $Say ('    MADE ' + $mk + ': ' + $mn); return
  }
  # "FALLBACK: <route>": the step used its documented fallback route (for a user with fewer rights). Not a result line;
  # a step that passes this way reads PASSED (fallback) and counts as passed (docs/engine.md "Results").
  if ($line -cmatch '^\s*FALLBACK:\s+(\S.*)$') {
    $R.Fallback = ConvertTo-MadeName $Matches[1] $Site
    & $Say ('    FALLBACK: ' + $R.Fallback); return
  }
  # Lines that may name a unit or a file (for example seal details) never reach the report (data boundary).
  if ($Step.ScreenOnly -and $line -match $Step.ScreenOnly) { $line = ($line -replace '^(\S+).*$', '$1') + ' (detail hidden: it may hold a name; run the step script by hand to see it)' }
  if ($line -match '(^|\s)PASS(\s|$)') { $R.Pass++ }
  if ($line -cmatch '(^|\s)SKIP(\s|$)') { $R.Skip++ }   # upper case only: prose such as "skip this" is not a result
  if ($line -match '(^|\s)(FAIL|FORMAT-FAIL|RENDER-ERROR|MEASURE-ERROR|STOPPED:)(\s|$)') { $R.Fail++; if ($line -match $signInLost) { $R.SignIn = $true } }   # a failed sign-in: the CAC may be out (12-resume.ps1)
  if ($line.Trim()) { & $Say ('    ' + $line) }   # step output, indented under its step heading
  if ($script:nowUi) { $now = Get-NowText $line; if ($now) { & $script:nowUi $now } }
}
# L7 (the Administrator, 2026-11-19): turns a result line of a step script into a plain sentence for the window's
# now-doing line: the words after PASS, SKIP or FAIL (upper case), with what the result means in front. Takes the line
# (masked already); gives back the sentence, or '' when the line is not a result or has no words after the result.
function Get-NowText([string]$Line) {
  if ($Line -cnotmatch '(?:^|\s)(PASS|SKIP|FAIL)(?:\s+|:\s*)(\S.*)$') { return '' }
  $what = $Matches[2].Trim()
  return ($(if ($Matches[1] -eq 'PASS') { 'Checked: ' } elseif ($Matches[1] -eq 'SKIP') { 'Skipped: ' } else { 'Needs review: ' }) + $what)
}

<#
.SYNOPSIS
Runs one step script as a child PowerShell, and once more when Windows' script policy blocked it.
.DESCRIPTION
engine-v46 (90-161.Z R45 finding 1: one step was blocked once; the same file ran a few seconds later). When the first run
printed no line and Windows did not load the script (Test-PolicyBlock), RADE logs the policy of each scope, waits 5
seconds and runs the step once more, unless the window is closing. A step blocked 2 times is named in
$script:blockedSteps for the end card.
.PARAMETER Base
The RADE app folder.
.PARAMETER Step
The step.
.PARAMETER Say
The log callback.
.PARAMETER Tick
The tick callback (moves the window's bars).
.PARAMETER Answer
The person's answer, or ''.
.OUTPUTS
What Invoke-RoundStepOnce gives, with Blocked ($true after 2 blocks).
#>
function Invoke-RoundStep([string]$Base, $Step, [scriptblock]$Say, [scriptblock]$Tick, [string]$Answer) {
  $r = Invoke-RoundStepOnce $Base $Step $Say $Tick $Answer
  if (-not (Test-PolicyBlock $r) -or $script:closing) { return $r }   # the window is closing: no second run
  & $Say ('    BLOCKED: Windows did not let this step''s script run (script policy). ' + (Get-PolicyLine) + '. RADE runs it once more in 5 seconds.')
  $until = (Get-Date).AddSeconds(5); while ((Get-Date) -lt $until -and -not $script:closing) { & $Tick; Start-Sleep -Milliseconds 30 }   # the bars keep moving while RADE waits
  if ($script:closing) { return $r }   # Exit during the wait (review of PR 206): the step does not start again
  $r = Invoke-RoundStepOnce $Base $Step $Say $Tick $Answer
  if (Test-PolicyBlock $r) { $r.Blocked = $true; $script:blockedSteps += [string]$Step.Name; & $Say ('    BLOCKED again: ' + (Get-PolicyLine) + '.') }
  else { & $Say '    The second run of this step was not blocked.' }
  return $r
}
# Says whether a step result is a script policy block: the script printed no line at all (so it did no work: review of
# PR 206, a step that printed FAIL or MADE lines and then failed to load a module is not run again) and its error output
# says that Windows did not load it (running scripts is disabled, or not digitally signed). Takes the result; gives back
# $true or $false.
function Test-PolicyBlock($R) { return [bool]([int]$R.Lines -eq 0 -and [string]$R.Err -match 'running scripts is disabled|is not digitally signed|PSSecurityException') }
# Gives one line with the script policy of each scope that has one ("Get-ExecutionPolicy -List"; numbers and words only),
# for the log of a blocked step. Takes nothing.
function Get-PolicyLine {
  $all = @(); try { $all = @(Get-ExecutionPolicy -List | Where-Object { [string]$_.ExecutionPolicy -ne 'Undefined' } | ForEach-Object { [string]$_.Scope + '=' + [string]$_.ExecutionPolicy }) } catch { $null = $_ }   # no list: none set
  return ('Policy: ' + $(if ($all.Count) { $all -join ', ' } else { 'none set' }) + '; in effect: ' + [string](Get-ExecutionPolicy))
}
<#
.SYNOPSIS
Runs one step script as a child PowerShell, one time.
.DESCRIPTION
Follows the step's output line by line until it ends or passes its time limit ($stepMinutes, or the step's own
Minutes); the window's bars move every 30 ms ($Tick). Each error line is logged masked and kept in Err, so
Invoke-RoundStep can see a script policy block (engine-v46).
.PARAMETER Base
The RADE app folder.
.PARAMETER Step
The step.
.PARAMETER Say
The log callback.
.PARAMETER Tick
The tick callback (moves the window's bars).
.PARAMETER Answer
The person's answer, or ''.
.OUTPUTS
@{ Pass; Fail; Skip; Exit; Made; Fallback; SignIn; Err (the masked error output); Blocked ($false here); Lines (the
output lines read) }.
#>
function Invoke-RoundStepOnce([string]$Base, $Step, [scriptblock]$Say, [scriptblock]$Tick, [string]$Answer) {
  $psi = Get-StepStartInfo $Base $Step $Answer $Say
  $r = @{ Pass = 0; Fail = 0; Skip = 0; Exit = $null; Made = @(); Fallback = ''; SignIn = $false; Err = ''; Blocked = $false; Lines = 0 }
  $siteNow = [string](Get-SiteUrl $Base)
  $p = [System.Diagnostics.Process]::Start($psi)
  $script:child = $p
  $limit = $stepMinutes; if ($Step.Minutes) { $limit = [int]$Step.Minutes }   # a step that waits for a person sets its own limit
  $deadline = (Get-Date).AddMinutes($limit)
  $errTask = $p.StandardError.ReadToEndAsync()
  $lineTask = $p.StandardOutput.ReadLineAsync()
  while ($true) {
    while (-not $lineTask.Wait(30)) {   # 30 ms: the window's bars move smoothly (R17)
      & $Tick
      if ((Get-Date) -gt $deadline) { try { $p.Kill() } catch { $null = $_ }; $r.Fail++; & $Say ('    STOPPED: the step ran longer than ' + $limit + ' minutes and was ended.'); break }
    }
    if (-not $lineTask.IsCompleted) { break }
    $line = $lineTask.Result
    if ($null -eq $line) { break }
    $r.Lines++   # engine-v46: a step that printed any line did work (Test-PolicyBlock)
    Add-StepLine $line $Step $r $siteNow $Say
    $lineTask = $p.StandardOutput.ReadLineAsync()
  }
  $p.WaitForExit()
  $script:child = $null
  foreach ($e in @(([string]$errTask.Result) -split "`r?`n" | Where-Object { $_ })) { $r.Fail++; if ($e -match $signInLost) { $r.SignIn = $true }; $m = ConvertTo-Masked $e; $r.Err += $m + "`n"; & $Say ('    Error output: ' + $m) }
  $r.Exit = $p.ExitCode
  return $r
}
# Gives the state word for a step result: SKIPPED, INTERRUPTED, NEEDS REVIEW or PASSED. Takes the result table; gives back the word.
function Get-StepState($R) {
  if ($R.Skipped) { return 'SKIPPED' }
  if ($R.Fail -gt 0 -or $R.Exit -ne 0) { if ($R.SignIn) { return 'INTERRUPTED' }; return 'NEEDS REVIEW' }   # a failed sign-in (CAC out): resume re-runs it (the Administrator, 2026-11-20)
  if ($R.Pass -eq 0 -and $R.Skip -gt 0) { return 'SKIPPED' }   # the step found nothing to do (R18: was PASSED with 0 passed)
  return 'PASSED'
}
function Get-StepLine($Step, $R, [double]$Seconds) {
  # One line per step in the summary and the e-mail: name, result, check counts, time.
  $state = Get-StepState $R
  if ($R.Skipped) { return ($Step.Name + ': SKIPPED' + $(if ($R.Why) { ' (' + $R.Why + ')' } else { ' by you' })) }
  if ($Step.Kind -eq 'guide' -and $R.FailText) { return ($Step.Name + ': FAILED (reported by you) in ' + (Format-Duration $Seconds) + ': ' + $R.FailText) }
  if ($Step.Kind -eq 'guide') { return ($Step.Name + ': ' + $state + $(if ($Step.AnswersOnly) { ' (answered by you) in ' } else { ' (confirmed by you) in ' }) + (Format-Duration $Seconds)) }
  if ($state -eq 'PASSED' -and $R.Fallback) { $state = 'PASSED (fallback: ' + $R.Fallback + ')' }
  return ($Step.Name + ': ' + $state + ' (' + $R.Pass + ' passed, ' + $R.Fail + ' failed' + $(if ($R.Skip) { ', ' + $R.Skip + ' skipped' } else { '' }) + ', exit code ' + $R.Exit + ') in ' + (Format-Duration $Seconds))
}
# Puts the text on the clipboard, by Windows Forms or else Set-Clipboard. Takes the text; gives back $true if it worked,
# else $false.
function Copy-TextToClipboard([string]$Text) {
  try { [System.Windows.Forms.Clipboard]::SetText($Text); return $true } catch { $null = $_ }
  try { if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) { Set-Clipboard -Value $Text; return $true } } catch { $null = $_ }
  return $false
}
function ConvertTo-UserText([string]$Text) {
  # Text a person typed (the "It failed" text, a text answer): one line, the DODID masked, no e-mail or site address.
  $t = ((ConvertTo-Masked $Text) -replace '\s+', ' ').Trim()
  $t = $t -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '<EMAIL>'   # e-mail first: the site rule would leave the name before @
  return ($t -replace 'https?://\S+', '<SITE>' -replace '[A-Za-z0-9.-]+\.(sharepoint|sharepoint-mil|onmicrosoft)\.[A-Za-z.]+\S*', '<SITE>')   # no address reaches the e-mail
}
# Runs a hand step: shows it (in the window or as console text), waits for Done, It failed or Skip, and asks the step's
# questions (a step with "answersOnly" shows only its questions). Takes the base folder, the step and a Say block; gives
# back the result table.
function Invoke-GuideStep([string]$Base, $Step, [scriptblock]$Say) {
  $r = @{ Pass = 0; Fail = 0; Exit = 0; Skipped = $false; FailText = ''; Answers = @() }
  $script:guideAnswers = @{}; $script:guideFail = @(); $script:guideError = ''
  $dir = Join-Path $Base $Step.Dir
  $file = $(if ($Step.File) { Join-Path $dir $Step.File } else { '' })   # R18: a guide step may need no file
  $url = $Step.Url
  $urlFile = ''
  if ($Step.UrlConfig) {
    $urlFile = Get-ConfigFile $Base $Step.UrlConfig
    # A saved address is used only on the host of the step's own address (the Administrator, 2026-11-17).
    if (Test-Path -LiteralPath $urlFile -PathType Leaf) { try { $v = ([string](Get-Content -LiteralPath $urlFile -TotalCount 1)).Trim(); if (Test-SameHost $v $Step.Url) { $url = $v } elseif ($v -and $Step.Url) { & $Say ('    The saved address is not on ' + ([uri]$Step.Url).Host + '; the step uses its own address.') } elseif ($v) { & $Say '    The saved address is not used: this step gives no address of its own.' } } catch { $null = $_ } }
  }
  # An old marker from an earlier run would make site setup wait for a result that is not coming (review R13 #2).
  if ($Step.Marker) { $old = Join-Path $dir $Step.Marker; if (Test-Path -LiteralPath $old -PathType Leaf) { try { Remove-Item -LiteralPath $old -Force } catch { $null = $_ } } }
  if ($Step.File) { & $Say ('    File ready: ' + $Step.Dir + '\' + $Step.File) }
  if ($script:textMode -and $Step.AnswersOnly) { $r.Skipped = $true; $r.Why = 'its questions need the RADE window'; & $Say ('    Skipped: ' + $r.Why + '.'); return $r }
  if ($script:textMode) {
    foreach ($l in @($Step.Guide)) { & $Say ('    ' + $l) }
    if ($url) { & $Say ('    Address: ' + $url) }   # R28 N1: a step with no address shows none
    if ($file -and (Copy-TextToClipboard $file)) { & $Say '    The full file path is on the clipboard.' }
    if ($url -and $env:OS -eq 'Windows_NT') { try { Start-Process -FilePath $url } catch { $null = $_ } }
    $res = Read-GuideChoice $Step
    if ($res -eq 'Abort') { $script:guideError = [string](Read-Host 'Paste the error message (no names or site address), then press Enter') }
  } elseif ($script:guideUi) { $res = [string](@(& $script:guideUi $Step $file $url $urlFile))[-1] }   # the window shows the step as a card and waits for the answer
  else { $res = 'Cancel' }
  # E2 (the Administrator, 2026-11-19): an answer that the manifest marks as a failure ("failOn") makes the step FAILED.
  $bad = @($script:guideFail | Where-Object { $_ })
  if ($res -eq 'Abort' -or ($res -eq 'OK' -and $bad.Count)) {
    $t = ConvertTo-UserText ([string]$script:guideError)
    if ($t.Length -gt 600) { $t = $t.Substring(0, 600) + ' ...' }
    if (-not $t) { $t = 'no error text given' }
    if ($bad.Count) { $t = 'answer ' + ($bad -join '; ') + '. Error text: ' + $t }
    $r.Fail = 1; $r.FailText = $t
    & $Say ('    Failed (reported by you): ' + $t)
  } elseif ($res -eq 'OK') {
    if ($Step.Marker) { try { Set-Content -LiteralPath (Join-Path $dir $Step.Marker) -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding UTF8 } catch { $null = $_ } }
    $r.Pass = 1
    & $Say ('    ' + $(if ($Step.DoneLog) { $Step.DoneLog } elseif ($Step.AnswersOnly) { 'Answered by you.' } else { 'Confirmed by you: the flow is imported and its run has started.' }))
  } elseif ($res -eq 'None') { $r.Skipped = $true; $r.Why = 'no answer that this step offers was given'; & $Say ('    Skipped: ' + $r.Why + '.') }   # text mode: a hidden answer is never recorded as the person's
  else { $r.Skipped = $true; & $Say '    Skipped by you.' }
  # The step's questions (manifest "answers"), asked after Done: one line each for the summary, under the step's line.
  if ($res -eq 'OK') { foreach ($q in @($Step.Answers | Where-Object { $_ })) { $r.Answers += ('  Answer ' + [string]$q.Key + ': ' + (Get-GuideAnswerText $q)) } }
  return $r
}
<#
.SYNOPSIS
Text mode: asks how a hand step ended and reads the answer.
.DESCRIPTION
Only the answers the step shows are offered (manifest "hide", E1); an answer that is not offered is asked again, 3 times
at most; then the step is skipped with that reason, not as an answer of the person.
.PARAMETER Step
The step (its Hide list names the answers that are not offered: done, failed, skip).
.OUTPUTS
OK (Done), Abort (It failed), Cancel (Skip) or None (no answer that the step offers, 3 times).
#>
function Read-GuideChoice($Step) {
  $hide = @($Step.Hide)
  $ask = 'Press Enter when the flow run has started, type F and Enter if it failed, or S and Enter to skip this step'
  if ($hide.Count) {
    $ws = @(); if ($hide -notcontains 'done') { $ws += 'press Enter when you have done this step' }; if ($hide -notcontains 'failed') { $ws += 'type F and Enter if it failed' }; if ($hide -notcontains 'skip') { $ws += 'type S and Enter to skip this step' }
    $ask = ($ws -join ', or '); $ask = $ask.Substring(0, 1).ToUpperInvariant() + $ask.Substring(1)
  }
  for ($n = 0; $n -lt 3; $n++) {
    $a = [string](Read-Host $ask); $a = $(if ($a) { $a.Trim() } else { '' })   # no input (closed stdin) gives no value, not ''
    $res = $(if ($a -match '^[Ss]') { 'Cancel' } elseif ($a -match '^[Ff]') { 'Abort' } else { 'OK' })
    $name = $(if ($res -eq 'OK') { 'done' } elseif ($res -eq 'Abort') { 'failed' } else { 'skip' })
    if ($hide -notcontains $name) { return $res }
  }
  return 'None'
}
# Gives the report text of one question of a hand step: the answer, or why there is none. A text answer is masked and
# kept whole. Takes the question; reads $script:guideAnswers; gives back the text.
function Get-GuideAnswerText($Q) {
  $k = [string]$Q.Key
  if ($script:textMode) { return 'not asked (text mode)' }
  # E3: a question that depends on an earlier answer ("showIf") and did not show.
  if ($Q.ShowKey -and @($Q.ShowIn) -cnotcontains [string]$script:guideAnswers[[string]$Q.ShowKey]) { return 'not asked' }
  if (-not $script:guideAnswers.ContainsKey($k)) { return 'not answered (the window closed)' }
  if ($Q.Kind -eq 'text') { $v = ConvertTo-UserText ([string]$script:guideAnswers[$k]); if (-not $v) { $v = '(no text)' }; return $v }   # the full answer (R28: it was cut at 120 characters)
  return [string]$script:guideAnswers[$k]   # yes/no and pick: the fixed words of the buttons
}
# Adds one line to the run log, when a log exists. Takes the line; gives back nothing.
function Add-RunLog([string]$T) { if ($null -ne $script:runLog) { $script:runLog.Add($T) } }
# No scripts in results (the Administrator, 2026-11-20): says whether a file is a script: a script extension ($scriptExts, from
# the build's SCRIPT_EXTS), or (engine-v34) a saved copy of a bundle under any name: its first line that is not blank is
# "# @@BUNDLE-HASH ..." (the .txt copy a person can save from a link; Test-BundleCopy). The first time a name is refused, one line goes to
# the run log. Takes the file name and, when there is one, its full path; gives back $true for a script file.
function Test-ScriptResult([string]$Name, [string]$Path = '') {
  $ext = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
  if ((@($scriptExts) -notcontains $ext) -and -not (Test-BundleCopy $Path)) { return $false }
  if ($null -eq $script:scriptsSkipped) { $script:scriptsSkipped = @{} }
  if (-not $script:scriptsSkipped.ContainsKey($Name)) { $script:scriptsSkipped[$Name] = $true; Add-RunLog ('SKIPPED script file ' + $Name + ' (scripts never go in results)') }
  return $true
}
# Says whether a file starts with the bundle hash line, so it is a copy of a bundle (a whole script) whatever its name.
# Reads to the first line that is not blank (at most 20 lines; a paste can put blank lines or spaces above it, and the
# bundle still runs); a file it cannot read counts as no copy (the extension check still holds). Takes the full path
# ('' for none); gives back $true for a bundle copy.
function Test-BundleCopy([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $reader = $null
  $first = ''
  try {
    $reader = New-Object System.IO.StreamReader($Path)
    for ($i = 0; $i -lt 20 -and -not $first; $i++) { $line = $reader.ReadLine(); if ($null -eq $line) { break }; $first = $line.TrimStart([char]0xFEFF).Trim() }
  } catch { return $false } finally { if ($reader) { $reader.Dispose() } }
  return $first.StartsWith('# @@BUNDLE-HASH ')
}
# Fills the results folder Rounds\<round>: a copy of each collect file (never a script file), then the report (the
# summary and the full log). Takes the RADE app folder and the summary; gives back the folder, the file count and the
# expected files that are missing.
function Export-RoundResult([string]$Base, [string[]]$Summary) {
  # One folder of plain files to attach to one e-mail (zips do not cross the boundary, PFM 13 Nov).
  $out = Join-Path (Join-Path $Base 'Rounds') $round
  if (-not (Test-Path -LiteralPath $out -PathType Container)) { [void](New-Item -ItemType Directory -Path $out -Force) }
  $count = 1; $missing = @()
  foreach ($c in $collect) {
    if ($c.Step -and -not ($script:ranSteps -contains $c.Step)) { continue }   # a skipped step has nothing to send
    $src = Join-Path $Base $c.Dir
    if ($c.Name -match '[*?]') {
      # A pattern (R10: any saved page counts, whatever its name); top level only, so a browser's "_files" folders stay out.
      # Several patterns may be joined with ';' ("*.mhtml;*.pdf"): missing only when none of them finds a file.
      # Windows -Filter '*.htm' also matches '.html': keep each file once. Copies carry the task prefix (T09-..., T12-...) so
      # two tasks never overwrite each other, and older copies of that task are removed first (review R10).
      $hits = @(); if (Test-Path -LiteralPath $src -PathType Container) { foreach ($pat in ($c.Name -split ';')) { $hits += @(Get-ChildItem -LiteralPath $src -File -Filter $pat -ErrorAction SilentlyContinue) } }
      $hits = @($hits | Sort-Object FullName -Unique | Where-Object { -not (Test-ScriptResult $_.Name $_.FullName) })   # a script never goes in results
      Get-ChildItem -LiteralPath $out -File -Filter ($c.Dir + '-*') -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
      foreach ($h in $hits) { Copy-Item -LiteralPath $h.FullName -Destination (Join-Path $out ($c.Dir + '-' + $h.Name)) -Force; $count++ }
      if (-not $hits.Count) { $missing += ($c.Dir + '\' + $c.Name) }
      continue
    }
    $old = Join-Path $out $c.Name
    if (Test-Path -LiteralPath $old -PathType Leaf) { Remove-Item -LiteralPath $old -Force }   # an older copy of the same name must not be sent again
    $p = Join-Path $src $c.Name
    if (Test-ScriptResult $c.Name $p) { continue }   # the build refuses such a name; this is the second guard
    if (Test-Path -LiteralPath $p -PathType Leaf) { Copy-Item -LiteralPath $p -Destination (Join-Path $out $c.Name) -Force; $count++ } else { $missing += ($c.Dir + '\' + $c.Name) }
  }
  if ($missing.Count) { $script:roundBad = $true }
  $report = Join-Path $out ('@@PREFIX@@-' + $round + '-report-r1.txt')
  $body = @($Summary) + @('', '---------------- full log ----------------') + @($script:runLog)
  [System.IO.File]::WriteAllText($report, (($body -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding $true))
  return @{ Dir = $out; Count = $count; Missing = $missing }
}
function Get-RoundPlan {
  # What this round writes and recycles, before it runs (PFM 13 Nov: show the impact; show the real path).
  $base = Get-BasePath
  $found = Test-Path -LiteralPath (Get-OneDrivePath) -PathType Container
  $mv = Get-RadeMove
  $shown = $(if ($mv.Needed) { $mv.To } else { $base })
  $lines = @(('Working folder: ' + $shown + $(if ($found) { '' } else { '   (NOT found: OneDrive is not set up in this Windows profile)' })), '')
  if ($mv.Needed) { $lines += @(('Folder move (runs first): OneDrive\' + $appFolder + '  ->  OneDrive\RADE\' + $appFolder), '  One move inside your OneDrive; every file keeps its place. If it cannot run, this round uses the old folder.', '') }
  $lines += 'Files this round saves:'
  foreach ($f in $files) {
    $p = Join-Path (Join-Path $base $f.Dir) $f.Name
    $lines += ($(if (Test-Path -LiteralPath $p -PathType Leaf) { '  Replace   ' } else { '  New       ' }) + $f.Dir + '\' + $f.Name)
  }
  foreach ($f in $fetch) {
    $p = Join-Path (Join-Path $base $f.Dir) $f.Name
    $lines += ($(if (Test-Path -LiteralPath $p -PathType Leaf) { '  Replace   ' } else { '  New       ' }) + $f.Dir + '\' + $f.Name + '  (downloaded from ' + ([uri]$f.Url).Host + $(if ($f.Sha) { ', checked' } else { '' }) + ')')
  }
  $lines += ('  Results   Rounds\' + $round + '\  (one report file and copies of the result files)')
  if ($cleanup.Count) {
    $cp = @{ Lines = @(); Kept = 0 }
    if (Test-Path -LiteralPath $base -PathType Container) { $cp = Get-CleanupPlan $base }
    if ($cp.Lines.Count) { $lines += ''; $lines += 'Clean-up (runs first; moves files to the Recycle Bin; clear its check box to skip):'; $lines += $cp.Lines }
    else { $lines += ''; $lines += 'Clean-up: nothing to recycle.' }
  }
  $lines += ''
  $lines += ('Settings   RADE\Config (' + $(if (Test-Deploy) { 'the installed versions' } else { 'the e-mail address' }) + ' and the saved checks) and Config\@@PREFIX@@-site.txt (the site address).')
  if ((Test-Deploy) -and $script:app.Marker) {
    $lines += ''
    $lines += ('On the site   after the steps, one row in the list "' + $script:app.Marker.List + '" (row "' + $script:app.Marker.Key + '": the installed version and the date, no name).')
    if (Test-FirstInstall) { $lines += ('First install from this account. Install ' + $script:app.Name + ' once for each wing, on one site: RADE stops a second install on this site, but it cannot see an install on another site.') }
  }
  $lines += ''
  $lines += 'Missing folders are created and files of the same name are replaced. Nothing else is changed, moved or deleted.'
  return @{ Shown = $shown; Found = $found; Lines = $lines }
}
function Save-RoundDraft([string]$Dir, [string[]]$Summary, [string]$To, [string]$WindowLine) {
  # One Outlook draft with subject, body and every results file (R05, PFM 13 Nov); To from the window box (R06).
  # Never sent: this code has no Send call (tests/run.sh checks). Classic Outlook only (new Outlook has no COM): else fall back.
  if ($env:OS -ne 'Windows_NT') { return 'not Windows' }
  try {
    if (-not (Test-Path -LiteralPath 'Registry::HKEY_CLASSES_ROOT\Outlook.Application')) { return 'Classic Outlook is not registered' }
    $ol = New-Object -ComObject Outlook.Application
    $m = $ol.CreateItem(0)
    $m.Subject = $Summary[0]
    if ($To) { $m.To = $To }
    $m.Body = ((@($Summary | Select-Object -Skip 1) + @('', $WindowLine)) -join "`r`n")
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -File)) { if ($f.Name -ne $stateName -and -not (Test-ScriptResult $f.Name $f.FullName)) { [void]$m.Attachments.Add($f.FullName) } }   # never a script, never the resume state
    $m.Display()   # first: if it fails, nothing is left in Drafts
    $m.Save()
    return ''
  } catch { return (ConvertTo-Masked $_.Exception.Message) }
}
# Says whether the chosen app runs in deploy mode (an install) and not as a test round. Takes nothing; gives back $true
# or $false.
function Test-Deploy { return ([string]$script:app.Mode -eq 'deploy') }
