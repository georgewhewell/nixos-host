# Idempotent converger for windowsConfigurations.* (see windows/module.nix).
#
# Reads the desired state rendered by Nix (state.json next to this script)
# and makes the machine match it. Every step is Test-then-Set, so re-running
# is a no-op. Things this script created on an earlier run but which are no
# longer declared (packages, files, firewall rules, port proxies) are removed:
# the managed sets are recorded under HKLM:\SOFTWARE\nix-windows.
#
# Windows PowerShell 5.1, run elevated (an admin OpenSSH session is).
param(
  [string]$StatePath = (Join-Path $PSScriptRoot 'state.json'),
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$state = Get-Content -Raw -Encoding UTF8 $StatePath | ConvertFrom-Json
$regRoot = 'HKLM:\SOFTWARE\nix-windows'
$script:changed = 0
$script:rebootRequired = $false

function Say($msg) { Write-Output $msg }
function Change($what, [scriptblock]$do) {
  $script:changed++
  if ($DryRun) { Say "would: $what"; return }
  Say "apply: $what"
  & $do
}
function Arr($x) { if ($null -eq $x) { @() } else { @($x) } }

function Get-Managed($kind) {
  $v = (Get-ItemProperty -Path $regRoot -Name $kind -ErrorAction SilentlyContinue).$kind
  if ($v) { @($v | ConvertFrom-Json) } else { @() }
}
function Set-Managed($kind, $items) {
  if ($DryRun) { return }
  if (-not (Test-Path $regRoot)) { New-Item -Path $regRoot -Force | Out-Null }
  Set-ItemProperty -Path $regRoot -Name $kind -Value (ConvertTo-Json -Compress @(Arr $items))
}

# --- hostname -------------------------------------------------------------
# Compare the *pending* name: $env:COMPUTERNAME only changes at reboot.
$pendingName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
$activeName = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
if ($state.hostName -and $activeName -ne $state.hostName.ToUpper() -and $pendingName -eq $activeName) {
  Change "rename computer $env:COMPUTERNAME -> $($state.hostName)" {
    Rename-Computer -NewName $state.hostName -Force -WarningAction SilentlyContinue
  }
  $script:rebootRequired = $true
} elseif ($state.hostName -and $activeName -ne $state.hostName.ToUpper()) {
  $script:rebootRequired = $true
}

# --- registry -------------------------------------------------------------
foreach ($r in (Arr $state.registry)) {
  $cur = (Get-ItemProperty -Path $r.path -Name $r.name -ErrorAction SilentlyContinue).($r.name)
  if ("$cur" -ne "$($r.value)") {
    Change "registry $($r.path)\$($r.name) = $($r.value)" {
      if (-not (Test-Path $r.path)) { New-Item -Path $r.path -Force | Out-Null }
      New-ItemProperty -Path $r.path -Name $r.name -PropertyType $r.type -Value $r.value -Force | Out-Null
    }
  }
}

# --- network category -----------------------------------------------------
foreach ($p in (Arr $state.networkCategories)) {
  $cur = Get-NetConnectionProfile -InterfaceAlias $p.interfaceAlias -ErrorAction SilentlyContinue
  if ($cur -and "$($cur.NetworkCategory)" -ne $p.category) {
    Change "network category $($p.interfaceAlias) -> $($p.category)" {
      Set-NetConnectionProfile -InterfaceAlias $p.interfaceAlias -NetworkCategory $p.category
    }
  }
}

# --- services -------------------------------------------------------------
foreach ($s in (Arr $state.services)) {
  $svc = Get-Service -Name $s.name -ErrorAction SilentlyContinue
  if (-not $svc) { Say "warn: service $($s.name) not installed"; continue }
  if ("$($svc.StartType)" -ne $s.startupType) {
    Change "service $($s.name) startup -> $($s.startupType)" {
      Set-Service -Name $s.name -StartupType $s.startupType
    }
  }
  if ($s.state -eq 'Running' -and $svc.Status -ne 'Running') {
    Change "start service $($s.name)" { Start-Service -Name $s.name }
  } elseif ($s.state -eq 'Stopped' -and $svc.Status -ne 'Stopped') {
    Change "stop service $($s.name)" { Stop-Service -Name $s.name -Force }
  }
}

# --- firewall -------------------------------------------------------------
# Rules are owned by group "nix-windows"; anything in the group that is not
# declared is deleted.
$fwGroup = 'nix-windows'
$wantFw = @{}
foreach ($f in (Arr $state.firewall)) { $wantFw[$f.name] = $f }
foreach ($rule in @(Get-NetFirewallRule -Group $fwGroup -ErrorAction SilentlyContinue)) {
  if (-not $wantFw.ContainsKey($rule.DisplayName)) {
    Change "remove firewall rule $($rule.DisplayName)" { $rule | Remove-NetFirewallRule }
  }
}
# Windows reports 10.0.0.0/8 back as 10.0.0.0/255.0.0.0.
function Normalize-Address($a) {
  if ($a -match '^(\d+\.\d+\.\d+\.\d+)/(\d+)$') {
    $bits = [int]$Matches[2]
    $mask = if ($bits -eq 0) { 0 } else { [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $bits)) }
    $b = [BitConverter]::GetBytes($mask); [array]::Reverse($b)
    return "$($Matches[1])/$(([Net.IPAddress]::new($b)).ToString())"
  }
  return $a
}
foreach ($f in $wantFw.Values) {
  $ports = (Arr $f.localPorts | ForEach-Object { "$_" })
  $remote = if ($f.remoteAddresses) { @(Arr $f.remoteAddresses | ForEach-Object { Normalize-Address $_ }) } else { @('Any') }
  $rule = @(Get-NetFirewallRule -Group $fwGroup -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $f.name) | Select-Object -First 1
  $ok = $false
  if ($rule) {
    $pf = $rule | Get-NetFirewallPortFilter
    $af = $rule | Get-NetFirewallAddressFilter
    $ok = ("$($pf.Protocol)" -eq $f.protocol) -and
      ((@($pf.LocalPort) -join ',') -eq ($ports -join ',')) -and
      ((@($af.RemoteAddress) -join ',') -eq ($remote -join ',')) -and
      ("$($rule.Direction)" -eq 'Inbound') -and ("$($rule.Action)" -eq 'Allow') -and
      ("$($rule.Enabled)" -eq 'True')
  }
  if (-not $ok) {
    Change "firewall rule $($f.name): $($f.protocol) $($ports -join ',') from $($remote -join ',')" {
      if ($rule) { $rule | Remove-NetFirewallRule }
      New-NetFirewallRule -Group $fwGroup -DisplayName $f.name -Direction Inbound -Action Allow `
        -Protocol $f.protocol -LocalPort $ports -RemoteAddress $remote -Profile Any | Out-Null
    }
  }
}

# --- port proxies ---------------------------------------------------------
function Get-PortProxies {
  $out = netsh interface portproxy show v4tov4
  foreach ($line in $out) {
    if ($line -match '^\s*(\S+)\s+(\d+)\s+(\S+)\s+(\d+)\s*$') {
      [pscustomobject]@{ listenAddress = $Matches[1]; listenPort = [int]$Matches[2]; connectAddress = $Matches[3]; connectPort = [int]$Matches[4] }
    }
  }
}
function ProxyKey($p) { "$($p.listenAddress):$($p.listenPort)" }
$haveProxy = @{}
foreach ($p in @(Get-PortProxies)) { $haveProxy[(ProxyKey $p)] = $p }
$wantProxy = @{}
foreach ($p in (Arr $state.portProxies)) { $wantProxy[(ProxyKey $p)] = $p }
foreach ($k in (Get-Managed 'portProxies')) {
  if ($haveProxy.ContainsKey($k) -and -not $wantProxy.ContainsKey($k)) {
    $p = $haveProxy[$k]
    Change "remove port proxy $k" {
      netsh interface portproxy delete v4tov4 listenaddress=$($p.listenAddress) listenport=$($p.listenPort) | Out-Null
    }
  }
}
foreach ($k in $wantProxy.Keys) {
  $w = $wantProxy[$k]; $h = $haveProxy[$k]
  if (-not $h -or $h.connectAddress -ne $w.connectAddress -or $h.connectPort -ne $w.connectPort) {
    Change "port proxy $k -> $($w.connectAddress):$($w.connectPort)" {
      netsh interface portproxy set v4tov4 listenaddress=$($w.listenAddress) listenport=$($w.listenPort) `
        connectaddress=$($w.connectAddress) connectport=$($w.connectPort) | Out-Null
    }
  }
}
Set-Managed 'portProxies' @($wantProxy.Keys)

# --- files ----------------------------------------------------------------
# Text files with Nix-rendered content (the home-manager-ish half).
$utf8 = New-Object System.Text.UTF8Encoding($false)
$wantFiles = @{}
foreach ($f in (Arr $state.files)) { $wantFiles[$f.path.ToLower()] = $f }
foreach ($p in (Get-Managed 'files')) {
  if (-not $wantFiles.ContainsKey($p.ToLower()) -and (Test-Path -LiteralPath $p)) {
    Change "remove file $p" { Remove-Item -LiteralPath $p -Force }
  }
}
foreach ($f in $wantFiles.Values) {
  $cur = if (Test-Path -LiteralPath $f.path) { [IO.File]::ReadAllText($f.path) } else { $null }
  if ($cur -ne $f.text) {
    Change "write $($f.path)" {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f.path) | Out-Null
      [IO.File]::WriteAllText($f.path, $f.text, $utf8)
    }
  }
}
Set-Managed 'files' @($wantFiles.Values | ForEach-Object { $_.path })

# --- administrators' SSH keys ----------------------------------------------
if ($null -ne $state.adminAuthorizedKeys) {
  $akPath = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
  $want = ((Arr $state.adminAuthorizedKeys) -join "`r`n") + "`r`n"
  $cur = if (Test-Path $akPath) { [IO.File]::ReadAllText($akPath) } else { $null }
  if ($cur -ne $want) {
    Change "write $akPath ($((Arr $state.adminAuthorizedKeys).Count) keys)" {
      [IO.File]::WriteAllText($akPath, $want, $utf8)
      # sshd ignores this file unless only SYSTEM and Administrators can write it.
      icacls.exe $akPath /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
    }
  }
}

# --- winget packages ------------------------------------------------------
$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if ($winget) {
  function Test-Package($id) {
    winget list --id $id --exact --accept-source-agreements --disable-interactivity | Out-Null
    return ($LASTEXITCODE -eq 0)
  }
  # In a non-interactive (SSH) session winget cannot register its own source
  # MSIX and every query fails with 0x8A15000F; register it directly.
  if ((Arr $state.packages).Count -gt 0) {
    winget search --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -eq -1978335217) {
      Change 'register winget source package' {
        Add-AppxPackage -Path 'https://cdn.winget.microsoft.com/cache/source2.msix'
      }
    }
  }
  $wantPkgs = @(Arr $state.packages)
  $wantIds = @($wantPkgs | ForEach-Object { $_.id })
  foreach ($id in (Get-Managed 'packages')) {
    if ($wantIds -notcontains $id -and (Test-Package $id)) {
      Change "uninstall $id" {
        winget uninstall --id $id --exact --silent --disable-interactivity --accept-source-agreements | Out-Null
      }
    }
  }
  foreach ($p in $wantPkgs) {
    if (-not (Test-Package $p.id)) {
      Change "install $($p.id)" {
        $wgArgs = @('install', '--id', $p.id, '--exact', '--source', 'winget', '--silent',
          '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
        if ($p.scope) { $wgArgs += @('--scope', $p.scope) }
        if ($p.installerType) { $wgArgs += @('--installer-type', $p.installerType) }
        & winget @wgArgs | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "winget install $($p.id) failed: $LASTEXITCODE" }
      }
    }
  }
  Set-Managed 'packages' $wantIds
} elseif ((Arr $state.packages).Count -gt 0) {
  Say 'warn: winget.exe not found; packages skipped'
}

# --- WSL distributions ------------------------------------------------------
function Get-WslDistros {
  # wsl.exe writes UTF-16; decode explicitly.
  $old = [Console]::OutputEncoding
  [Console]::OutputEncoding = [Text.Encoding]::Unicode
  try { @(wsl.exe --list --quiet | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }) }
  finally { [Console]::OutputEncoding = $old }
}
foreach ($d in (Arr $state.wsl)) {
  if ((Get-WslDistros) -notcontains $d.name) {
    # Images live beside, not inside, the per-generation bundle directories.
    $tarball = if ($d.tarball) { Join-Path (Split-Path -Parent $PSScriptRoot) $d.tarball } else { $null }
    if (-not $tarball -or -not (Test-Path $tarball)) {
      Say "warn: WSL distro $($d.name) missing and no tarball shipped (deploy with --wsl-image)"
      continue
    }
    Change "import WSL distro $($d.name) into $($d.installDir)" {
      New-Item -ItemType Directory -Force -Path $d.installDir | Out-Null
      wsl.exe --import $d.name $d.installDir $tarball --version 2
      if ($LASTEXITCODE -ne 0) { throw "wsl --import $($d.name) failed: $LASTEXITCODE" }
      Remove-Item -LiteralPath $tarball -Force
    }
  }
  if ($d.default) {
    # Distros are registered per user under HKCU; this session is the owner.
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $defaultGuid = (Get-ItemProperty $lxss -ErrorAction SilentlyContinue).DefaultDistribution
    $defaultName = if ($defaultGuid) { (Get-ItemProperty "$lxss\$defaultGuid" -ErrorAction SilentlyContinue).DistributionName }
    if ($defaultName -ne $d.name) {
      Change "WSL default distro $defaultName -> $($d.name)" { wsl.exe --set-default $d.name | Out-Null }
    }
  }
  if ($d.keepAlive) {
    # WSL stops a distro's VM once nothing runs in it. A boot-time task,
    # running as the distro's owner without an interactive logon, keeps it
    # (and its sshd) up for the fleet.
    $task = "nix-windows WSL $($d.name)"
    $exe = (Get-Command wsl.exe).Source
    $arg = "-d $($d.name) --exec /bin/sh -c `"exec sleep infinity`""
    $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    $ok = $t -and $t.Actions[0].Execute -eq $exe -and $t.Actions[0].Arguments -eq $arg -and
      $t.Principal.UserId -eq $d.user -and "$($t.Principal.LogonType)" -eq 'S4U'
    if (-not $ok) {
      Change "scheduled task '$task'" {
        $action = New-ScheduledTaskAction -Execute $exe -Argument $arg
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId $d.user -LogonType S4U -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) `
          -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries
        Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger `
          -Principal $principal -Settings $settings -Force | Out-Null
      }
    }
    $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    if ($t -and "$($t.State)" -ne 'Running') {
      Change "start scheduled task '$task'" { Start-ScheduledTask -TaskName $task }
    }
  }
}

# --- IPv4 address (last: it can cut this very SSH session) -------------------
$ip = $state.ipv4
if ($ip) {
  $iface = Get-NetIPInterface -InterfaceAlias $ip.interfaceAlias -AddressFamily IPv4
  $addrs = @(Get-NetIPAddress -InterfaceAlias $ip.interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue)
  $gw = @(Get-NetRoute -InterfaceAlias $ip.interfaceAlias -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
  $dns = @((Get-DnsClientServerAddress -InterfaceAlias $ip.interfaceAlias -AddressFamily IPv4).ServerAddresses)
  $ok = ("$($iface.Dhcp)" -eq 'Disabled') -and
    ($addrs.Count -eq 1) -and ($addrs[0].IPAddress -eq $ip.address) -and ($addrs[0].PrefixLength -eq $ip.prefixLength) -and
    ($gw.Count -eq 1) -and ($gw[0].NextHop -eq $ip.gateway) -and
    (($dns -join ',') -eq ((Arr $ip.dns) -join ','))
  if (-not $ok) {
    # Run detached, a few seconds from now, so this session can report back
    # before its address changes underneath it.
    Change "IPv4 $($ip.interfaceAlias) -> $($ip.address)/$($ip.prefixLength) via $($ip.gateway), dns $((Arr $ip.dns) -join ',')" {
      $cmd = @"
Start-Sleep 5
Set-NetIPInterface -InterfaceAlias '$($ip.interfaceAlias)' -Dhcp Disabled
Get-NetIPAddress -InterfaceAlias '$($ip.interfaceAlias)' -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:`$false
Get-NetRoute -InterfaceAlias '$($ip.interfaceAlias)' -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:`$false
New-NetIPAddress -InterfaceAlias '$($ip.interfaceAlias)' -IPAddress '$($ip.address)' -PrefixLength $($ip.prefixLength) -DefaultGateway '$($ip.gateway)'
Set-DnsClientServerAddress -InterfaceAlias '$($ip.interfaceAlias)' -ServerAddresses $((Arr $ip.dns | ForEach-Object { "'$_'" }) -join ',')
"@
      $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
      $task = 'nix-windows ipv4'
      $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -EncodedCommand $enc"
      $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
      Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Force | Out-Null
      Start-ScheduledTask -TaskName $task
      Say "note: address change scheduled; reconnect at $($ip.address)"
    }
  }
}

$verb = if ($DryRun) { 'pending' } else { 'applied' }
Say "nix-windows: $script:changed change(s) $verb"
if ($script:rebootRequired) { Say 'nix-windows: REBOOT REQUIRED' }
