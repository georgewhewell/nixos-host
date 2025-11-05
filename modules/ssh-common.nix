{config, lib, ...}: {
  # This module adds common SSH config to system-level SSH
  programs.ssh.extraConfig = lib.mkBefore ''
    # ProxyJump logic for satanic.link hosts
    Match host *.satanic.link exec "! (ifconfig 2>/dev/null || ip addr 2>/dev/null) | grep -q '192\.168\.23\.'"
      ProxyJump grw@satanic.link
    
    # Direct connection when on local network  
    Match host *.satanic.link exec "(ifconfig 2>/dev/null || ip addr 2>/dev/null) | grep -q '192\.168\.23\.'"
      ProxyJump none
    
    # Also handle direct IPs
    Host 78.47.106.113
      ProxyJump none
    
    # Control master settings
    Host *
      ControlMaster auto
      ControlPath ~/.ssh/control-%r@%h:%p
      ControlPersist 10m
      ServerAliveInterval 60
      ServerAliveCountMax 5
  '';
}
