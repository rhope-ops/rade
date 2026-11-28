# RADE engine part 07, the checks: the NIPR guard, the site address, the web and sign-in checks, the install
# record on the site, and Invoke-Check, which runs one check. Its results are saved by 08-saved-checks.ps1.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.
# Network: the app's go file (GitHub), the site on the DAF SharePoint host, the app's fixed Power Automate host, and
#   SharePoint sign-in through PnP; only these fixed addresses (AGENTS.md "No reconnaissance").
# Writes: one OneDrive test file and one temporary script (each deleted at once), the site address in Config, and the
#   install record (one row of one list on the site, after a deploy step).
# Credentials: the interactive CAC sign-in of PnP (-UseWebLogin); the proxy gets the Windows sign-in; no web request
#   of RADE sends the Windows sign-in to the address it asks (Get-WebRequest; the Administrator, 2026-11-17).

# ---- Checks (PFM 14 Nov 26: RADE checks, from its window, that this computer can install the chosen app and
# that the Administrator has the rights to see it done end to end). Read-only except: one test file in the OneDrive folder and one
# temporary script in the Windows temp folder, each deleted at once, the site address in Config when the Administrator enters it,
# and the install record row on the site (the marker script of part 16, after a deploy step).
# Kind: auto = runs on its own when the Check screen opens; signin = needs a CAC sign-in (button); guide = the Administrator looks
# in another program and answers (button). Advisory: a problem is a WARNING, never a FAILED.
$script:spEnabled = ('@@SP_ENABLED@@' -ne 'false')
$checkDefs = @(
  @{ Id = 'nipr'; Group = 'Local'; Name = 'This computer is on NIPR (area52 domain)'; Kind = 'auto' },
  @{ Id = 'ps'; Group = 'Local'; Name = 'PowerShell is version 5.1 or newer'; Kind = 'auto' },
  @{ Id = 'lang'; Group = 'Local'; Name = 'PowerShell is not restricted'; Kind = 'auto' },
  @{ Id = 'onedrive'; Group = 'Local'; Name = 'Your OneDrive folder is set up'; Kind = 'auto' },
  @{ Id = 'disk'; Group = 'Local'; Name = 'There is enough free disk space'; Kind = 'auto' },
  @{ Id = 'write'; Group = 'Local'; Name = 'Files can be saved in OneDrive'; Kind = 'auto' },
  @{ Id = 'child'; Group = 'Local'; Name = 'RADE can run its scripts'; Kind = 'auto' },
  @{ Id = 'outlook'; Group = 'Local'; Name = 'Outlook can make the results e-mail'; Kind = 'auto'; Advisory = $true },
  @{ Id = 'word'; Group = 'Local'; Name = 'Word is installed'; Kind = 'auto' },
  @{ Id = 'net-bookmark'; Group = 'Network'; Name = 'The repository can be reached'; Kind = 'auto'; Advisory = $true },
  @{ Id = 'net-flow'; Group = 'Network'; Name = 'Power Automate can be reached'; Kind = 'auto' },
  @{ Id = 'flow-guide'; Group = 'Access'; Name = 'You can import flows in Power Automate (you look)'; Short = 'You can import flows (you look)'; Kind = 'guide' }
)
if ($script:spEnabled) {
  $checkDefs += @(
    @{ Id = 'pnp'; Group = 'Local'; Name = 'The SharePoint tool (PnP.PowerShell 1.12.0) is installed'; Short = 'The SharePoint tool (PnP 1.12.0) is installed'; Kind = 'auto' },
    @{ Id = 'net-site'; Group = 'Network'; Name = 'Your SharePoint site can be reached'; Kind = 'auto' },
    @{ Id = 'site-rights'; Group = 'Access'; Name = 'You can change the site (sign in with your CAC)'; Short = 'You can change the site (CAC sign-in)'; Kind = 'signin' }
  )
}
# Short: the name in the window's narrow check column (the Administrator, 2026-11-14); the log and the e-mail keep Name.
$dot = ' ' + [char]0x00B7 + ' '   # a middle dot between facts, made at run time so the bundle stays ASCII
# ---- Environment guard (the Administrator, 15 Nov 26): RADE runs on NIPR computers only. It reads this computer's own
# full name (host name and its domain: two local values; nothing is sent and no host is contacted) and goes on only when
# that name contains the NIPR domain label below. It cannot prove NIPR; it stops an honest mistake. The name is never shown or saved.
$niprLabel = '@@NIPR_LABEL@@'
# Reads this computer's own host name and domain name (two local values; no host is contacted). Takes nothing; gives
# back "host.domain", or an empty text on an error.
function Get-OwnFqdn { try { $g = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties(); return [string]$g.HostName + '.' + [string]$g.DomainName } catch { return '' } }
# Says whether this computer's full name has the NIPR domain label. Takes nothing; gives back $true or $false.
function Test-NiprDevice { return ([string](Get-OwnFqdn)).Trim().ToLowerInvariant().Contains($niprLabel) }
# Finds the definition of a check by its id. Takes the id; gives back the definition, or $null.
function Get-CheckDef([string]$Id) { foreach ($d in $checkDefs) { if ($d.Id -eq $Id) { return $d } }; return $null }
function Get-SiteUrl([string]$Base) {
  # Config\@@PREFIX@@-site.txt: the same file T16 site setup keeps (one place for the site address; never in the repo).
  $p = Get-ConfigFile $Base '@@PREFIX@@-site.txt'
  if (Test-Path -LiteralPath $p -PathType Leaf) { try { return ([string](Get-Content -LiteralPath $p -TotalCount 1)).Trim() } catch { return '' } }
  return ''
}
$sitePrefix = '@@SITE_PREFIX@@'   # the DAF SharePoint address every site starts with; the box starts with it
# Guardrail (the Administrator, 14 Nov 26): only a site on the DAF SharePoint host is accepted, so RADE never signs in to
# or writes to another host.
function Test-SiteUrl([string]$Url) { return ($Url -match ('^' + [regex]::Escape($sitePrefix) + '[^/\\\s"]+/?$')) }
# Writes the site address to Config\<prefix>-site.txt, creating the folder if needed. Takes the base folder and the
# address; gives back nothing.
function Save-SiteUrl([string]$Base, [string]$Url) {
  $p = Get-ConfigFile $Base '@@PREFIX@@-site.txt'
  $dir = Split-Path -Parent $p
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
  [System.IO.File]::WriteAllText($p, ($Url.Trim() + "`r`n"), (New-Object System.Text.UTF8Encoding $true))
}
function Get-FlowPortal([string]$Base) {
  # The address the guide steps open (editable there, remembered in Config); the first app step that names one wins.
  # A Config address is used only when its host is the host of the app's own fixed address (the Administrator,
  # 2026-11-17: no address from a file a user can change reaches another host).
  foreach ($k in $script:appSteps) {
    $s = $steps[$k]
    if ($s.Url) {
      if ($s.UrlConfig) {
        $p = Get-ConfigFile $Base $s.UrlConfig
        if (Test-Path -LiteralPath $p -PathType Leaf) {
          try {
            $v = ([string](Get-Content -LiteralPath $p -TotalCount 1)).Trim()
            if ((Test-SameHost $v $s.Url)) { return @{ Url = $v; Config = $p } }
            elseif ($v) { return @{ Url = $s.Url; Config = $p; Refused = $true } }
          } catch { $null = $_ }
        }
      }
      return @{ Url = $s.Url; Config = $(if ($s.UrlConfig) { Get-ConfigFile $Base $s.UrlConfig } else { '' }) }
    }
  }
  return @{ Url = ''; Config = '' }
}
<#
.SYNOPSIS
True when both addresses are https and name the same host (any letter case) and the same port.
.DESCRIPTION
The port is part of the rule (engine-v14): an address from a file a user can change must not make RADE touch another
port of the host (AGENTS.md "No reconnaissance"). An empty or broken address gives $false.
.PARAMETER Url
The address to check.
.PARAMETER Fixed
The fixed address it must match.
.OUTPUTS
$true or $false.
#>
function Test-SameHost([string]$Url, [string]$Fixed) {
  try { $a = [uri]$Url; $b = [uri]$Fixed } catch { return $false }
  if (-not $a -or -not $b) { return $false }
  return ($a.IsAbsoluteUri -and $b.IsAbsoluteUri -and $a.Scheme -eq 'https' -and $b.Scheme -eq 'https' -and $a.Host -ieq $b.Host -and $a.Port -eq $b.Port)
}
<#
.SYNOPSIS
Makes the web request every RADE read uses: the address itself never gets the Windows sign-in.
.DESCRIPTION
One place for the request rules (engine-v14; the Administrator, 2026-11-17 and 2026-11-18): TLS 1.2 is added (Windows
PowerShell 5.1 starts with TLS 1.0, which GitHub closes), the user agent of Edge's family is sent (a request with none
can be closed by a filtering proxy), the Windows sign-in is off for the address, and only the work proxy gets it.
The request is not sent here: the caller sends it and closes the answer.
.PARAMETER Url
The address to ask.
.PARAMETER TimeoutMs
How long to wait for the answer, in milliseconds.
.OUTPUTS
The request object (System.Net.WebRequest).
#>
function Get-WebRequest([string]$Url, [int]$TimeoutMs) {
  Use-TlsFloor
  $rq = [System.Net.WebRequest]::Create($Url)
  $rq.Timeout = $TimeoutMs
  try { $rq.UserAgent = $webAgent } catch { $null = $_ }   # a file address (tests) has no user agent
  try { $rq.UseDefaultCredentials = $false } catch { $null = $_ }   # a file address (tests) has no such setting; off is also the default
  try { if ($rq.Proxy) { $rq.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials } } catch { $null = $_ }   # no proxy: nothing to sign in to
  return $rq
}
function Test-WebReach([string]$Url) {
  # Does the host answer? Any HTTP answer counts (401 or 403 = it answers but wants a sign-in), so the address itself
  # never gets the Windows sign-in (the Administrator, 2026-11-17); only the proxy does.
  # Returns no address and no message text (they can hold the site or tenant name): only the code or the error kind.
  try {
    $rq = Get-WebRequest $Url 6000   # TLS 1.2, user agent, no sign-in for the address (R19 to R21 findings live there)
    try { $rq.AllowAutoRedirect = $false } catch { $null = $_ }   # the answer of this address counts, not of the next one
    $rs = $rq.GetResponse()
    $code = 0; try { $code = [int]$rs.StatusCode } catch { $null = $_ }
    $rs.Close()
    return @{ Ok = $true; Code = $code }
  } catch {
    $e = $_.Exception
    while ($e -and -not ($e -is [System.Net.WebException]) -and $e.InnerException) { $e = $e.InnerException }
    if ($e -is [System.Net.WebException] -and $e.Response) {
      $code = 0; try { $code = [int]$e.Response.StatusCode } catch { $null = $_ }
      if ($code -eq 407) { return @{ Ok = $false; Why = 'Network sign-in required, code [407]' } }
      return @{ Ok = $true; Code = $code }
    }
    if ($e -is [System.Net.WebException]) {
      $whyMap = @{
        Timeout = 'no reply in time'; NameResolutionFailure = 'address not found'
        ConnectFailure = 'could not connect'; ProxyNameResolutionFailure = 'network proxy not found'
        TrustFailure = 'the security certificate was not trusted'; SecureChannelFailure = 'secure connection failed'
      }
      $why = $whyMap[[string]$e.Status]
      if (-not $why) { $why = 'network error' }
      $why += ' [' + [string]$e.Status + ']'
      # R21 diagnostics: the inner error kinds, a socket error code and the TLS setting (names and numbers only, no address).
      $kinds = @(); $x = $e.InnerException
      while ($x) {
        $k = $x.GetType().Name
        if ($x -is [System.Net.Sockets.SocketException]) { $k += ' ' + [int]$x.ErrorCode }
        elseif ($x.HResult) { $k += ' 0x' + ('{0:X8}' -f $x.HResult) }
        $kinds += $k; $x = $x.InnerException
      }
      $tls = ''; try { $tls = [string][Net.ServicePointManager]::SecurityProtocol } catch { $null = $_ }
      if ($kinds.Count -or $tls) { $why += ' (' + (@($kinds) + @('TLS ' + $tls) -join '; ') + ')' }
      return @{ Ok = $false; Why = $why }
    }
    return @{ Ok = $false; Why = 'network error [' + $e.GetType().Name + ']' }
  }
}
# Invoke-ChildScript (runs an embedded child script; R44 E4 stage limits): part 16, engine/ps/16-site-scripts.ps1.
# The sign-in window size block, the rights check script and the install record on the site: part 16, engine/ps/16-site-scripts.ps1.
$rightWords = @{
  ViewListItems = 'read items'; AddListItems = 'add items'; EditListItems = 'edit items'
  ManageLists = 'manage lists'; ManageWeb = 'manage the site'; ManagePermissions = 'manage permissions'
}
$rightsNeeded = @('ManageLists', 'ManageWeb', 'ManagePermissions')   # what T16 site setup and list set-up use
function Write-SiteMarker([string]$Base, [bool]$Whole) {
  # After a deploy that ran a step: a part install is recorded too (its flows may be imported already), with the word
  # "partial". Returns the one line for the log and the report.
  $m = $script:app.Marker; $site = Get-SiteUrl $Base
  $where = '"' + $m.List + '", row "' + $m.Key + '"'
  $again = ' Until it is written, another account is not stopped from a second install on this site: run this deploy again'
  if (-not (Test-SiteUrl $site)) { return ('NOTE: the install record on the site (' + $where + ') was not written: no site address.' + $again) }
  $val = [string]$script:app.Version + ' ' + (Get-Date).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) + $(if ($Whole) { '' } else { ' partial' })
  $r = Invoke-ChildScript $markerScript ('-Site "' + $site + '"' + (Get-MarkerArg) + ' -Value "' + $val + '"') 300 $null $signInStageSeconds
  $null = Get-SignInNote 'Install record' $r.Lines   # engine-v43 S2, S3: the sign-in lines in the run log
  $w = ''; foreach ($l in $r.Lines) { if ($l -match '^RESULT (\S+)') { $w = $Matches[1] } }
  if ($w -in 'added', 'updated') {
    $part = $(if ($Whole) { '' } else { ', marked partial' })
    return ('Install record on the site: ' + $where + ' now holds version ' + $script:app.Version + ' and the date' + $part + ' (' + $w + ').')
  }
  $why = $(switch ($w) {
    'no-list' { 'the list was not found' }
    'no-pnp' { 'the SharePoint tool is not installed' }
    default {
      $(if ($r.Stage -eq 'signin') { 'the sign-in did not finish in ' + [int]($signInStageSeconds / 60) + ' minutes, so RADE stopped it' }
        else { 'the sign-in or the write did not finish' })
    }
  })   # engine-v43 S1
  return ('NOTE: the install record on the site (' + $where + ') was not written: ' + $why + '.' + $again)
}
function Split-Sentence([string]$Text) {
  # One sentence per line on screen (PFM 14 Nov 26): a break after . ! or ? when a capital, a quote or a bracket follows.
  return ($Text -replace '(?<=[.!?])\s+(?=[A-Z"\[])', "`r`n")
}
function Format-CheckResult([string]$State, [string]$Detail, [string]$Fix) {
  # Text rule (the Administrator, 2026-11-14, replaces the full-stop rule): each Details line starts with a capital and ends
  # with no full stop; one fact per line, never joined with ";". Names on the screen (buttons, menus) are in "double quotes";
  # literal values the computer reports (versions, codes, error names) are in [brackets].
  if ($Detail) { $Detail = $Detail.Substring(0, 1).ToUpper() + $Detail.Substring(1); $Detail = $Detail -replace '\.$', '' }
  if ($Fix) { $Fix = $Fix -replace '\.$', '' }
  return @{ State = $State; Detail = $Detail; Fix = $Fix }
}
# Checks of this computer itself: NIPR name, PowerShell version and language mode, OneDrive, free space, a test file,
# and a child script. Takes the check id and the tick callback (for the child script); returns a check result
# (Format-CheckResult), or $null for an id it does not handle.
function Get-ComputerCheck([string]$Id, [scriptblock]$Tick) {
  $one = $null
  switch ($Id) {
  'nipr' {
    # Reads only this computer's own full name (Test-NiprDevice); the name itself is never shown or saved.
    if (Test-NiprDevice) { $one = Format-CheckResult 'PASSED' 'Read this computer''s own full name: it is in the area52 domain' '' }
    else { $one = Format-CheckResult 'FAILED' 'This application cannot be installed in your environment.' '' }
  }
  'ps' {
    $v = $PSVersionTable.PSVersion
    if ($v -ge [version]'5.1') { $one = Format-CheckResult 'PASSED' ('version [' + $v + ']') '' }
    else { $one = Format-CheckResult 'FAILED' ('version [' + $v + ']') 'Open Windows PowerShell ISE from the Start menu, then paste the round again' }
  }
  'lang' {
    $m = [string]$ExecutionContext.SessionState.LanguageMode
    if ($m -eq 'FullLanguage') { $one = Format-CheckResult 'PASSED' 'Not restricted' '' }
    else { $one = Format-CheckResult 'FAILED' ('Restricted [' + $m + ']') 'PowerShell is restricted on this computer. Contact your ISSM and send the results e-mail as is' }
  }
  'onedrive' {
    $od = Get-OneDrivePath
    if (Test-Path -LiteralPath $od -PathType Container) { $one = Format-CheckResult 'PASSED' 'found' '' }
    else { $one = Format-CheckResult 'FAILED' 'not found' 'Sign in to OneDrive, wait until it is up to date, then select "Run checks again"' }
  }
  'disk' {
    $od = Get-OneDrivePath; $root = [System.IO.Path]::GetPathRoot($od)
    if (-not $root) { $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetTempPath()) }
    $free = (New-Object System.IO.DriveInfo($root)).AvailableFreeSpace
    $need = 200MB; foreach ($f in $files) { $need += 2 * $f.Data.Length }; $mb = [math]::Floor($free / 1MB)
    $fix = 'Free up space (for example, empty the Recycle Bin), then select "Run checks again"'
    if ($free -lt $need) { $one = Format-CheckResult 'FAILED' ('{0:N0} MB free, {1:N0} MB needed' -f $mb, [math]::Ceiling($need / 1MB)) $fix }
    elseif ($free -lt 1GB) { $one = Format-CheckResult 'WARNING' ('{0:N0} MB free' -f $mb) 'Enough for this deployment. Free up space soon' }
    else { $one = Format-CheckResult 'PASSED' ('{0:N0} MB free' -f $mb) '' } }
  'write' {
    $od = Get-OneDrivePath
    if (-not (Test-Path -LiteralPath $od -PathType Container)) { $one = Format-CheckResult 'NOT RUN' 'No OneDrive folder' 'Resolve the OneDrive check first' }
    else {
      $t = Join-Path $od ('@@PREFIX@@-write-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
      [System.IO.File]::WriteAllText($t, 'test'); Remove-Item -LiteralPath $t -Force
      $one = Format-CheckResult 'PASSED' 'Test file saved and deleted' '' } }
  'child' {
    $r = Invoke-ChildScript "if (`$env:PSExecutionPolicyPreference -ceq 'Bypass') { exit 8 }`r`n'child ok'`r`nexit 7`r`n" '' 60 $Tick
    $all = @()
    try {
      $all = @(Get-ExecutionPolicy -List | Where-Object { [string]$_.ExecutionPolicy -ne 'Undefined' } |
        ForEach-Object { [string]$_.Scope + '=' + [string]$_.ExecutionPolicy })
    } catch { $null = $_ }   # no scope list: the detail says none set
    $pol = (@($all | Where-Object { $_ -match '^\w*Policy=' }) -join ', ')
    if ($r.Exit -eq 7) { $one = Format-CheckResult 'PASSED' ('Test script ran' + $(if ($pol) { ', policy [' + $pol + ']' } else { '' })) '' }
    else {
      $det = ('Test script did not run, exit code [' + $r.Exit + ']' + $(if ($r.Why) { ', ' + $r.Why } else { '' }) +
        ', scopes [' + $(if ($all.Count) { $all -join ', ' } else { 'none set' }) + ']')
      $one = Format-CheckResult 'FAILED' $det 'This computer blocks RADE scripts. Contact your ISSM and send the results e-mail as is' } }
  }
  return $one
}

# Checks of installed programs: classic Outlook (drafts), Word (renders; it must also be closed) and PnP.PowerShell.
# Takes the check id; returns a check result, or $null for an id it does not handle.
function Get-ProgramCheck([string]$Id) {
  $one = $null
  switch ($Id) {
  'outlook' {
    if ($env:OS -ne 'Windows_NT') { $one = Format-CheckResult 'WARNING' 'Not Windows' 'RADE opens the results folder and copies the summary for your e-mail' }
    elseif ([type]::GetTypeFromProgID('Outlook.Application')) { $one = Format-CheckResult 'PASSED' 'Installed' '' }
    else { $one = Format-CheckResult 'WARNING' 'Classic Outlook not found (new Outlook cannot make drafts)' 'RADE opens the results folder and copies the summary for your e-mail' }
  }
  'word' {
    if ($env:OS -eq 'Windows_NT' -and [type]::GetTypeFromProgID('Word.Application')) {
      if (Get-Process -Name WINWORD -ErrorAction SilentlyContinue) {
        $one = Format-CheckResult 'FAILED' 'Installed, but open now' 'Save your work, close Word, then select "Run checks again"'   # PFM 14 Nov 26: blocks (1B)
      }
      else { $one = Format-CheckResult 'PASSED' 'Installed' '' }
    } else { $one = Format-CheckResult 'FAILED' 'Not found' 'This application requires Microsoft Word' }
  }
  'pnp' {
    $m = @(Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending)
    if (-not $m.Count) { $one = Format-CheckResult 'FAILED' 'Not installed' 'Site steps require it. Use the manual steps in the repository' }
    elseif ([string]$m[0].Version -eq '1.12.0') { $one = Format-CheckResult 'PASSED' 'version [1.12.0]' '' }
    else { $one = Format-CheckResult 'WARNING' ('Version [' + $m[0].Version + '], tested with [1.12.0]') 'Likely compatible. If a site step fails, send the results as is' }
  }
  }
  return $one
}

# Checks that a fixed address answers (the repository's go file, the site, Power Automate). Only these addresses: no
# host finding (AGENTS.md "No reconnaissance"). Takes the check id, the RADE app folder and the site address; returns
# a check result, or $null for an id it does not handle.
function Get-NetworkCheck([string]$Id, [string]$Base, [string]$Site) {
  $one = $null
  switch ($Id) {
  'net-bookmark' {
    $w = Test-WebReach $goUrl   # the file the "newer round" notice reads
    if ($w.Ok) { $one = Format-CheckResult 'PASSED' ('reached' + $(if ($w.Code) { ', code [' + $w.Code + ']' } else { '' })) '' }
    else { $one = Format-CheckResult 'WARNING' ('Not reached: ' + $w.Why) 'Optional: only the new-round notice uses it' }
  }
  'net-site' {
    if (-not (Test-SiteUrl $Site)) { $one = Format-CheckResult 'NOT RUN' 'No site address' ('Complete the "Site address" box (it starts with ' + $sitePrefix + '), then select "Run checks again"') }
    else {
      $w = Test-WebReach $Site
      if ($w.Ok) {
        $note = $(if ($w.Code -in 401, 403) { ', code [' + $w.Code + '] (sign-in required, as expected)' } elseif ($w.Code) { ', code [' + $w.Code + ']' } else { '' })
        $one = Format-CheckResult 'PASSED' ('Reached' + $note) ''
      }
      else { $one = Format-CheckResult 'FAILED' ('Not reached: ' + $w.Why) 'Verify the address opens in Edge, then select "Run checks again"' }
    }
  }
  'net-flow' {
    $fp = Get-FlowPortal $Base
    if (-not $fp.Url) { $one = Format-CheckResult 'NOT RUN' 'No Power Automate address' '' }
    else {
      $w = Test-WebReach $fp.Url
      if ($w.Ok -and $fp.Refused) {
        $det = 'reached the app''s own address; the saved address is not on ' + ([uri]$fp.Url).Host + ' and was not used'
        $one = Format-CheckResult 'WARNING' $det 'Enter an address on that host in the Power Automate step, or leave it as it is'
      }
      elseif ($w.Ok) { $one = Format-CheckResult 'PASSED' ('reached' + $(if ($w.Code) { ', code [' + $w.Code + ']' } else { '' })) '' }
      else { $one = Format-CheckResult 'FAILED' ('Not reached: ' + $w.Why) 'If Power Automate opens in Edge, select "Check Power Automate"' }
    }
  }
  }
  return $one
}

# The site rights check: a child script signs in with the CAC and prints only right names, True/False, the admin flag
# and the install record's version ($rightsScript). Fails on a missing right or on another account's install record.
# Takes the RADE app folder, the site address and the tick callback; returns a check result.
function Get-SiteRightsCheck([string]$Base, [string]$Site, [scriptblock]$Tick) {
  if (-not (Test-SiteUrl $Site)) { $one = Format-CheckResult 'NOT RUN' 'No site address' ('Complete the "Site address" box first (it starts with ' + $sitePrefix + ')') }
  else {
    $r = Invoke-ChildScript $rightsScript ('-Site "' + $Site + '"' + (Get-MarkerArg)) 300 $Tick $signInStageSeconds   # engine-v43 S1: a frozen sign-in stops after 3 minutes
    $have = @{}; $adm = 'unknown'; $mk = ''; $signLine = ''
    foreach ($l in $r.Lines) {
      if ($l -match '^RIGHT (\w+) (True|False)$') { $have[$Matches[1]] = ($Matches[2] -eq 'True') }
      if ($l -match '^ADMIN (True|False|unknown)$') { $adm = $Matches[1] }
      if ($l -match '^MARKER (none|unknown|found [0-9.]+)$') { $mk = $Matches[1] }
    }
    $signLine = Get-SignInNote 'Rights check' $r.Lines   # R43 E4, engine-v43 S2, S3: the sign-in time, the host, the window state
    $admText = 'Site collection administrator: ' + $(switch ($adm) { 'True' { 'yes' } 'False' { 'no' } default { 'not read' } }) + ' (shown only, not required)'
    if (-not $have.Count) {
      $why = 'Sign-in did not finish'; foreach ($l in $r.Lines) { if ($l -match '^RESULT (\S+)') { $why = $Matches[1] } }
      if ($why -eq 'not-connected') { $why = 'Sign-in did not finish' }
      if ($why -eq 'no-pnp') { $one = Format-CheckResult 'FAILED' 'SharePoint tool not installed' 'See the SharePoint tool check' }
      else { $one = Format-CheckResult 'FAILED' ($why + $(if ($r.Why) { ', ' + $r.Why } else { '' })) 'Select "Sign in and check site rights" and complete the CAC sign-in' }
    } else {
      $miss = @($rightsNeeded | Where-Object { -not $have[$_] } | ForEach-Object { $rightWords[$_] })
      $got = @($have.Keys | Sort-Object | Where-Object { $have[$_] } | ForEach-Object { $rightWords[$_] })
      if ($miss.Count) { $one = Format-CheckResult 'FAILED' ('Missing: ' + ($miss -join ', ')) 'Ask a site owner to add you to the site Owners group' }
      elseif ((Test-FirstInstall) -and $mk -like 'found *') {
        $ver = $(if ($mk -eq 'found 0') { 'not readable' } else { $mk.Substring(6) })
        $det = 'This site already has an install of this application [version ' + $ver + '], made from another account or for another site'
        $one = Format-CheckResult 'FAILED' $det 'Do not install again: every flow would run twice. Ask the person who installed it to run RADE'
      }
      elseif ((Test-FirstInstall) -and $mk -ne 'none') { $one = Format-CheckResult 'FAILED' 'The install record on the site could not be read' 'Select "Sign in and check site rights" again' }
      else { $one = Format-CheckResult 'PASSED' ('Rights: ' + ($got -join ', ') + '. ' + $admText) '' }
    }
    if ($signLine) { $one.Detail = [string]$one.Detail + '. ' + $signLine }   # R43 E4, engine-v43: shown in Details and the report (also when the sign-in did not finish)
  }
  return $one
}

# The Power Automate check that a person answers by looking: in text mode at the prompt, in the window on a hand card
# ($script:guideUi). Takes the RADE app folder; returns a check result (NOT RUN when it is not answered).
function Get-FlowGuideCheck([string]$Base) {
  if ($script:textMode) {
    $fp = Get-FlowPortal $Base
    Write-Host ('  Open Power Automate (' + $fp.Url + '). Look at the left menu for "Solutions" (it may be under "More"), then select "My flows" and look for "Import".')
    $a = ([string](Read-Host 'Did you see both "Solutions" and "Import"? Type Y or N and press Enter')).Trim()
    if ($a -match '^[Yy]') { $one = Format-CheckResult 'PASSED' 'Confirmed by you' '' }
    else { $one = Format-CheckResult 'FAILED' '"Solutions" or "Import" not shown' 'Ask your Power Automate administrator for maker access' }
  }
  else {
    $fp = Get-FlowPortal $Base
    $g = @{ Name = 'Check Power Automate'; File = ''; Url = $fp.Url; DoneText = 'Yes: I see both'; NoText = 'No: one is missing'; SkipText = 'Not now'
      Guide = @('You look in Power Automate and answer (about 2 minutes, an estimate). Nothing is changed.',
        '1. Select Open in browser. Power Automate opens; sign in with your CAC if asked.',
        '2. Look at the left menu: it must show Solutions (it may be under More).',
        '3. Select My flows: Import must show at the top of the page.',
        '4. Come back here. Select Yes if you saw both, No if one is missing.') }
    $a = 'Cancel'; if ($script:guideUi) { $a = [string](@(& $script:guideUi $g '' $fp.Url $fp.Config))[-1] }
    if ($a -eq 'OK') { $one = Format-CheckResult 'PASSED' 'Confirmed by you' '' }
    elseif ($a -eq 'No') { $one = Format-CheckResult 'FAILED' '"Solutions" or "Import" not shown' 'Ask your Power Automate administrator for maker access' }
    else { $one = Format-CheckResult 'NOT RUN' 'Not answered' 'Select "Check Power Automate" when ready' }
  }
  return $one
}

# Runs one check (the ids of $checkDefs) and gives its result. States: PASSED, WARNING, FAILED, NOT RUN. Detail and Fix
# never hold the site address or the DODID. An error in a check is a FAILED result, and an advisory check never
# FAILS (WARNING instead). Takes the check definition, the RADE app folder, the site address and the tick callback.
function Invoke-Check($Def, [string]$Base, [string]$Site, [scriptblock]$Tick) {
  $one = $null
  try {
    switch ($Def.Id) {
      { $_ -in 'nipr', 'ps', 'lang', 'onedrive', 'disk', 'write', 'child' } { $one = Get-ComputerCheck $Def.Id $Tick; break }
      { $_ -in 'outlook', 'word', 'pnp' } { $one = Get-ProgramCheck $Def.Id; break }
      { $_ -in 'net-bookmark', 'net-site', 'net-flow' } { $one = Get-NetworkCheck $Def.Id $Base $Site; break }
      'site-rights' { $one = Get-SiteRightsCheck $Base $Site $Tick; break }
      'flow-guide' { $one = Get-FlowGuideCheck $Base; break }
      default { $one = Format-CheckResult 'NOT RUN' 'unknown check' '' }
    }
  } catch { $one = Format-CheckResult 'FAILED' ('Check stopped with an error [' + $_.Exception.GetType().Name + ']') 'Select "Run checks again". If it repeats, send the results as is' }
  if ($Def.Advisory -and $one.State -eq 'FAILED') { $one.State = 'WARNING' }
  return $one
}
function Get-CheckSummary($Results) {
  # For the summary and the e-mail: one count line, then one line for each check that did not pass.
  $c = @{ PASSED = 0; WARNING = 0; FAILED = 0; 'NOT RUN' = 0 }
  $rest = @(); $saved = 0
  foreach ($id in $script:appChecks) {
    $r = $Results[$id]; $d = Get-CheckDef $id
    if (-not $r) { $r = Format-CheckResult 'NOT RUN' 'not run' '' }
    $c[$r.State]++
    if ($r.Saved) { $saved++ }
    if ($r.State -ne 'PASSED') { $rest += ('  ' + $r.State + ': ' + $d.Name + '. ' + $r.Detail) }
  }
  $savedText = $(if ($saved) { ' (' + $saved + ' from saved results)' } else { '' })
  $headLine = 'Checks. Passed: ' + $c.PASSED + $savedText + '. Warnings: ' + $c.WARNING + '. Failed: ' + $c.FAILED + '. Not run: ' + $c['NOT RUN'] + '.'
  return @(@($headLine) + $rest) | ForEach-Object { ConvertTo-Masked $_ }
}
function Get-CheckBlock($Results) {
  # PFM 14 Nov 26: no deploy unless every check passes (a half-done deploy is hard to undo). FAILED or NOT RUN blocks;
  # a WARNING (an advisory check, or a problem the deploy can live with) does not. No "deploy anyway".
  foreach ($id in $script:appChecks) { $r = $Results[$id]; if (-not $r -or $r.State -in 'FAILED', 'NOT RUN', 'RUNNING') { return $true } }
  return $false
}

# RADE engine part 08, saved checks: keeps each check that passed in RADE\Config\rade-checks.json and
# decides whether a later run may skip it (age, computer, PowerShell and PnP versions, scope). Uses 07-checks.ps1.
# Joined into every bundle by engine/rade_build.py; Windows PowerShell 5.1.

# ---- Saved checks (PFM 14 Nov 26, R17): RADE\Config\rade-checks.json keeps each check that PASSED, so a later run (of
# any app on this computer) can skip it. A saved result is used only when it is at most $checkMaxDays days old, the
# PowerShell and PnP versions and the computer are the same, and its scope (the site or the Power Automate address, as a
# hash) matches. A check that did not pass is never saved. No DODID, name or address is in the file (details are masked).
$checkMaxDays = 7
# Checks whose answer can change between two runs on the same day always run (review R17 MAJOR 2: "Word is open" blocks a
# deploy, PFM 14 Nov 26 1B; free space; a test file in OneDrive).
$checkNoSave = @('nipr', 'word', 'disk', 'write')
# Fast checks that are not saved in the file either, so each run of RADE makes them once (docs/engine.md "Results": fast
# checks run fresh; from engine-v21, before it they were reused for 7 days). Their answer holds for one run of RADE, so the
# window does not make them a second time after Choose, as it does for $checkNoSave (window/06-open.ps1).
$checkEachRun = @('ps', 'lang', 'child')
# Gives the first 6 bytes (12 hex characters) of the SHA-256 of the text, lower case and without a trailing "/". Takes
# the text; gives back the hash, or an empty text for no text.
function Get-ShortHash([string]$Text) {
  if (-not $Text) { return '' }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant().TrimEnd('/'))
    return (-join ($sha.ComputeHash($bytes) | Select-Object -First 6 | ForEach-Object { $_.ToString('x2') }))
  } finally { $sha.Dispose() }
}
function Get-CheckHost {
  # What makes a saved result stale when it changes: PowerShell, the PnP module, the computer (hashed).
  if ($script:checkHost) { return $script:checkHost }
  $pnp = ''; try { $m = @(Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending); if ($m.Count) { $pnp = [string]$m[0].Version } } catch { $null = $_ }
  $script:checkHost = @{ powershell = [string]$PSVersionTable.PSVersion; pnp = $pnp; computer = (Get-ShortHash ([string]$env:COMPUTERNAME)) }
  return $script:checkHost
}
function Get-CheckScope([string]$Id, [string]$Base, [string]$Site) {
  # A result about one site or one address is good only for that site or address.
  if ($Id -in 'net-site', 'site-rights') { return ('site:' + (Get-ShortHash $Site)) }
  if ($Id -in 'net-flow', 'flow-guide') { return ('flow:' + (Get-ShortHash (Get-FlowPortal $Base).Url)) }
  return ''
}
# Reads the saved checks from RADE\Config\rade-checks.json. Takes nothing; gives back a table of saved results, empty
# when the file is missing or was made on another computer, PowerShell or PnP version.
function Read-CheckCache {
  <#
  .SYNOPSIS
  Reads the saved PASSED check results from RADE\Config\rade-checks.json.
  .DESCRIPTION
  Returns an empty hashtable if the cache file is missing, unreadable, or recorded under a different PowerShell, PnP, or computer host signature.
  .OUTPUTS
  Hashtable mapping check id to cached result hashtable (State, Detail, Fix, At, Scope).
  #>
  $p = Get-RadeConfigFile 'rade-checks.json'
  $res = @{}
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $res }
  try {
    $j = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json
    $h = Get-CheckHost
    if ([string]$j.host.powershell -ne $h.powershell -or [string]$j.host.pnp -ne $h.pnp -or [string]$j.host.computer -ne $h.computer) { return $res }
    foreach ($c in @($j.checks.PSObject.Properties)) {
      $v = $c.Value
      $at = $v.at; if ($at -is [datetime]) { $at = $at.ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture) }   # PowerShell 7 reads it as a date
      $res[$c.Name] = @{ State = [string]$v.state; Detail = [string]$v.detail; Fix = ''; At = [string]$at; Scope = [string]$v.scope }
    }
  } catch { $null = $_ }   # a damaged file is ignored: every check runs
  return $res
}
function Get-CheckAge([string]$At) {
  # Days since a saved result (fractional); -1 when the date cannot be read.
  $d = [datetime]::MinValue
  if ([datetime]::TryParseExact($At, 'yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { return ((Get-Date) - $d).TotalDays }
  return 99999   # unreadable: too old
}
function Get-SavedCheck($Cache, [string]$Id, [string]$Scope) {
  <#
  .SYNOPSIS
  Returns a reusable cached check result if still fresh and matching scope, or $null.
  .DESCRIPTION
  Skips volatile checks ($checkNoSave, $checkEachRun), rejects non-PASSED or mismatched scope entries, and records staleness reasons in $script:savedWhy.
  .PARAMETER Cache
  Hashtable returned by Read-CheckCache.
  .PARAMETER Id
  Check identifier.
  .PARAMETER Scope
  Scope key (from Get-CheckScope) that the cached entry must match.
  .OUTPUTS
  Formatted saved-check result hashtable, or $null if the check must run fresh.
  #>
  # The saved result to use, or $null (with the reason in $script:savedWhy[$Id] when one was found but is too old).
  if (($checkNoSave + $checkEachRun) -contains $Id) { return $null }
  $c = $Cache[$Id]
  if (-not $c -or $c.State -ne 'PASSED' -or $c.Scope -ne $Scope) { return $null }
  $age = Get-CheckAge $c.At
  if ($age -lt -0.01) { $script:savedWhy[$Id] = 'Last check date is in the future (clock changed)'; return $null }
  if ($age -gt $checkMaxDays) { $script:savedWhy[$Id] = ('Last check ' + [int][math]::Floor([math]::Max(0, $age)) + ' days ago, older than ' + $checkMaxDays + ' days'); return $null }
  # Two lines (the Administrator, 2026-11-14): "Last check: 17 Nov 26", then what that check found; no full stops.
  $d0 = [datetime]::ParseExact($c.At, 'yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
  $found = ([string]$c.Detail) -replace '\.$', ''; if ($found) { $found = $found.Substring(0, 1).ToUpperInvariant() + $found.Substring(1) }
  return @{ State = 'PASSED'; Detail = ('Last check: ' + $d0.ToString('d MMM yy', [System.Globalization.CultureInfo]::InvariantCulture)); Fix = $found; Saved = $true; Found = $found }
}
function Save-CheckCache($Results, [string]$Base, [string]$Site) {
  <#
  .SYNOPSIS
  Saves PASSED check results to RADE\Config\rade-checks.json and writes full details to rade-checks-last.txt.
  .DESCRIPTION
  Preserves entries for other apps when host matches, updates or removes entries for this run, and ignores write errors so saving never stops a run.
  .PARAMETER Results
  Hashtable of check results keyed by check id.
  .PARAMETER Base
  Base app folder path.
  .PARAMETER Site
  SharePoint site URL.
  .OUTPUTS
  None.
  #>
  # Keeps the old file's other entries (other apps' checks), replaces this run's: PASSED is saved, anything else removed.
  try {
    $p = Get-RadeConfigFile 'rade-checks.json'
    $keep = @{}
    if (Test-Path -LiteralPath $p -PathType Leaf) {
      try { $j = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json; foreach ($c in @($j.checks.PSObject.Properties)) { $keep[$c.Name] = $c.Value } } catch { $null = $_ }
      try {
        $h0 = Get-CheckHost
        if ([string]$j.host.powershell -ne $h0.powershell -or [string]$j.host.pnp -ne $h0.pnp -or [string]$j.host.computer -ne $h0.computer) { $keep = @{} }
      } catch { $null = $_ }
    }
    foreach ($id in @($Results.Keys)) {
      $r = $Results[$id]
      if ($r.Saved) { continue }   # a saved result keeps its first date
      if (($checkNoSave + $checkEachRun) -contains $id) { if ($keep.ContainsKey($id)) { $keep.Remove($id) }; continue }
      if ($r.State -eq 'PASSED') {
        $keep[$id] = [ordered]@{
          state = 'PASSED'; detail = (ConvertTo-Masked ([string]$r.Detail))
          at = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
          scope = (Get-CheckScope $id $Base $Site)
        }
      } elseif ($keep.ContainsKey($id) -and $r.State -ne 'RUNNING') { $keep.Remove($id) }
    }
    $sorted = [ordered]@{}; foreach ($k in @($keep.Keys | Sort-Object)) { $sorted[$k] = $keep[$k] }
    $about = ('Saved RADE checks. Any app may read this file: use an entry only when its state is PASSED, its "at" is at most ' +
      $checkMaxDays + ' days old, "host" equals this computer (PowerShell, PnP and the hashed computer name), and "scope" ' +
      'matches (site: or flow: plus the first 12 hex of the SHA-256 of the lower-case address). Write only PASSED results; ' +
      'remove an entry when the check does not pass.')
    $doc = [ordered]@{
      schema = 'rade-checks/1'
      about = $about
      maxAgeDays = $checkMaxDays
      host = (Get-CheckHost)
      checks = $sorted
    }
    Write-FileWhole $p ($doc | ConvertTo-Json -Depth 5)
  } catch { $null = $_ }   # saving is a convenience: never stop for it
  Save-CheckDetail $Results   # every check's detail, in a file beside the saved checks
}
<#
.SYNOPSIS
Writes each check of this run, with its result and its detail, to the file RADE\Config\rade-checks-last.txt.
.DESCRIPTION
The Administrator, 2026-11-18: a round's report and e-mail hold the check counts and only the detail of a check that did
not pass, so a detail such as the child check's policy scopes was only in the window's Record. This file holds every detail and
is not sent: it is in RADE\Config (the user's OneDrive), not in the results folder, so no e-mail draft attaches it (the detail of the child check
names an execution policy, a setting of this computer). The newest run replaces it. Never an error: it is a convenience.
.PARAMETER Results
The check results of this run, by check id.
#>
function Save-CheckDetail($Results) {
  try {
    $hdr = 'RADE checks of ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ', round ' + $round + ', build ' + $buildId + ', engine release ' + $engineRelease
    $note = 'RADE does not send this file: no e-mail draft attaches it. It is in your OneDrive folder, as all of RADE\Config. The newest run replaces it.'
    $lines = @($hdr, $note, '')
    foreach ($id in $script:appChecks) {
      $r = $Results[$id]; if (-not $r) { continue }
      $d = Get-CheckDef $id
      $lines += ConvertTo-Masked ([string]$r.State + ': ' + $d.Name + '. ' + [string]$r.Detail + $(if ($r.Saved -and $r.Found) { ' | ' + [string]$r.Found } else { '' }))
    }
    Write-FileWhole (Get-RadeConfigFile 'rade-checks-last.txt') (($lines -join "`r`n") + "`r`n")
  } catch { $null = $_ }   # a convenience file: a run never stops for it
}
function Get-CheckToRun($Def, $Cache, [string]$Base, [string]$Site, [bool]$Force) {
  # $null = run it now; else the saved result to show.
  if ($Force) { return $null }
  if ($Def.Id -eq 'site-rights' -and (Test-FirstInstall)) { return $null }   # a first install always reads the site's install record fresh
  return (Get-SavedCheck $Cache $Def.Id (Get-CheckScope $Def.Id $Base $Site))
}
