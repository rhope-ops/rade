# RADE engine part 11, text mode: runs the whole round in the console (checks, plan, the Enter prompt,
# the round and the summary) when no window is open. Uses the parts before it.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

<#
.SYNOPSIS
Shows this process's console window again (engine-v44, review of the hidden ISE child).
.DESCRIPTION
The ISE child (Invoke-IseWindow, part 05) and the app's shortcut start with a hidden console window, so
no blank console shows while the RADE window is open. When the window cannot open there, text mode runs in that console.
.OUTPUTS
None.
#>
function Show-RadeConsole {
  # Inline C# compilation is forbidden by DEC-NIPR; text mode writes to the active host stream.
  $null = 0
}

try {
  if ($env:RADE_HOST -in 'child', 'shortcut') { Show-RadeConsole }   # a hidden console (ISE child, shortcut): it shows for text mode
  $script:textMode = $true
  # Writes a line to the run log and the console. Takes the line; gives back nothing.
  $say = { param($t) Add-RunLog $t; Write-Host $t }
  Write-Host ('RADE - ' + $round + ' - build ' + $buildId)
  Write-Host $script:scriptCheck.Line   # the bundle hash, to compare with the RADE page (docs/specs/bundle-hash.md)
  Write-Host (Get-LastRoundText (Read-RoundHistory (Get-BasePath)))
  $newer = Get-NewerRound
  if ($newer) { Write-Host ('A newer round, ' + $newer + ', is in the repository. Type N and press Enter to stop, then run ' + $newer + '.') }
  if ($apps.Count -gt 1) {
    for ($i = 0; $i -lt $apps.Count; $i++) { Write-Host ('  ' + ($i + 1) + '. ' + $apps[$i].Name) }
    $pick = ([string](Read-Host ('Type the number of the application to deploy (1 to ' + $apps.Count + ') and press Enter'))).Trim()
    $pi = 0; if ([int]::TryParse($pick, [ref]$pi) -and $pi -ge 1 -and $pi -le $apps.Count) { Select-App ($pi - 1) }
  }
  Write-Host ('Application: ' + $script:app.Name)
  # All checks run here too: the sign-in check opens its own sign-in window; the Power Automate check asks in the console.
  $site0 = Get-SiteUrl (Get-BasePath)
  if (-not (Test-SiteUrl $site0) -and @($script:appChecks | Where-Object { $_ -in 'net-site', 'site-rights' }).Count) {
    $v = ([string](Read-Host 'Type the site address (it starts with https://usaf.dps.mil/sites/), then press Enter')).Trim()
    if (Test-SiteUrl $v) { $site0 = $v; try { Save-SiteUrl (Get-BasePath) $v } catch { $null = $_ } }   # saved as the window does: the record and the steps read it
  }
  $script:secret = Get-Secret (Get-ProfileLeaf) (Get-ProfileLeaf)
  $cache = Read-CheckCache
  foreach ($id in $script:appChecks) {
    $d = Get-CheckDef $id
    $r = Get-CheckToRun $d $cache (Get-BasePath) $site0 $false
    if (-not $r) { $r = Invoke-Check $d (Get-BasePath) $site0 $null }
    $script:checkResults[$id] = $r
    Write-Host ('  ' + $r.State + ': ' + $d.Name + '. ' + $r.Detail + $(if ($r.Fix -and ($r.State -ne 'PASSED' -or $r.Saved)) { ' | ' + $r.Fix } else { '' }))
  }
  Save-CheckCache $script:checkResults (Get-BasePath) $site0
  if ($checkGate -and (Get-CheckBlock $script:checkResults)) {
    # PFM 14 Nov 26: no deploy unless every check passes. Nothing has been written.
    Write-Host ''
    Write-Host 'You cannot deploy yet: a check is FAILED or NOT RUN (see above). Only the saved checks (RADE\Config\rade-checks.json) were written.'
    Write-Host 'Fix each one, then paste the round again.'
    return
  }
  # Pause and resume (the Administrator, 2026-11-20; docs/engine.md "Pause and resume"): R (or Enter) resumes, S starts over.
  $rs = Read-RoundState (Get-BasePath)
  if ($rs.State -eq 'bad') { $null = Clear-RoundState (Get-BasePath); Write-Host ('The saved progress of this round could not be read (' + $rs.Why + '), so the round starts over.') }
  elseif ($rs.State -eq 'other') { $null = Clear-RoundState (Get-BasePath); Write-Host 'Saved progress of another build of this round was not used. The round starts over.' }
  elseif ($rs.State -eq 'ok') {
    $ra = ([string](Read-Host ('Type R and press Enter to resume at step ' + $rs.Next + ' of ' + $rs.Total + ', or type S and press Enter to start over'))).Trim()
    if ($ra -match '^[Ss]') { $why = Clear-RoundState (Get-BasePath); Write-Host $(if ($why) { 'The saved progress could not be moved to the Recycle Bin (' + $why + ').' } else { 'Start over: the saved progress is in the Recycle Bin.' }) }
    else { $script:resume = $rs.Doc; Write-Host ('Resume at step ' + $rs.Next + ' of ' + $rs.Total + '.') }
  }
  foreach ($l in (Get-RoundPlan).Lines) { Write-Host $l }
  $to = $(if (Test-Deploy) { '' } else { Get-MailTo (Get-BasePath) })
  # The plan above shows first; Enter starts the run (PFM 13 Nov), N stops before anything is written.
  $go = ([string](Read-Host 'Press Enter to start the round, or type N and press Enter to stop with no changes')).Trim()
  if ($go -match '^[Nn]') { Write-Host 'Stopped. Only the saved checks (RADE\Config\rade-checks.json) were written.'; return }
  $sel = @(); for ($k = 0; $k -lt $steps.Count; $k++) { $sel += ($script:appSteps -contains $k -and (Get-StepDefault $k) -and -not $steps[$k].AskParam) }   # text mode: steps that need a folder are skipped
  # Text mode: prints the overall line when a step starts (step i of count and the percent). Takes the Invoke-Round values.
  $onStatusText = { param($i, $count, $name, $estimate) $null = $name; $null = $estimate; $g = Get-Progress; Write-Host ('  Overall: step ' + $i + ' of ' + $count + ', ' + [int]($g.All * 100) + ' % done, about ' + (Format-Duration $g.Left) + ' left (a guess)') }
  $checkLines = Get-CheckSummary $script:checkResults
  $sum = Invoke-Round $true $sel $to $say { } { } $onStatusText { 'Window: text mode (no window opened)' } @() $checkLines
  if (Test-Deploy) { return }   # a deploy sends nothing: no folder pop-up, no clipboard
  if ($script:resultsDir -and $env:OS -eq 'Windows_NT' -and -not $script:draftMade) { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $script:resultsDir + '"') }
  if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) { try { Set-Clipboard -Value ($sum -join "`r`n"); Write-Host 'Summary copied to the clipboard.' } catch { Write-Host 'The clipboard is not available.' } }
} catch {
  Write-Host ''
  $m = 'STOPPED: ' + (ConvertTo-Masked ([string]$_))
  Write-Host $m
  $w = Get-WhatToDo $m; if ($w) { Write-Host $w }
  if ($m -match '^STOPPED: INTERRUPTED: ') { Write-Host 'In text mode: insert your CAC, run RADE again and type R to resume at that step.' }
}
