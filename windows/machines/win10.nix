# The Windows 10 build VM on fuckup (machines/x86/fuckup/windows-vm.nix).
# Deploy: nix run .#deploy-win10 [-- --dry-run]
{
  lib,
  network,
  nixosConfigurations,
  ...
}: let
  self = network.hosts.windows;
  ip = network.primaryIp self;
  lan = network.vlans.lan;
  keys = import ../../profiles/ssh-keys.nix;
in {
  # Was DESKTOP-OV78VU7; matches the fleet DNS name.
  hostName = "windows";

  deployment = {
    targetHost = ip;
    targetUser = "George";
  };

  networking = {
    # Static, from the fleet inventory, so the host is reachable before (and
    # regardless of) the router's DHCP reservation.
    ipv4 = {
      address = ip;
      prefixLength = lan.cidr;
      gateway = network.routerIp;
      dns = [network.dnsIp (network.primaryIp network.hosts.k3)];
    };
    category.Ethernet = "Private";

    # WSL2 on Windows 10 has NAT networking only. wslrelay forwards the
    # distro's sshd to loopback; publish it on the LAN (see network.nix).
    portProxies = [
      {
        listenAddress = "0.0.0.0";
        listenPort = self.wslSsh.port;
        connectAddress = "127.0.0.1";
        connectPort = self.wslSsh.innerPort;
      }
    ];
    firewall."NixOS-WSL sshd" = {
      localPorts = [self.wslSsh.port];
      remoteAddresses = [(network.cidrOf "lan" 0)];
    };
  };

  services = {
    sshd = {};
    # IP Helper carries netsh portproxy.
    iphlpsvc = {};
  };

  openssh.adminAuthorizedKeys = map lib.trim (lib.attrValues keys);

  registry = [
    # A build box: never reboot underneath a running build for updates.
    {
      path = "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU";
      name = "NoAutoRebootWithLoggedOnUsers";
      value = 1;
    }
    {
      path = "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU";
      name = "AUOptions";
      # 3 = download automatically, notify to install.
      value = 3;
    }
  ];

  packages = [
    "Git.Git"
    {
      id = "Microsoft.PowerShell";
      installerType = "wix"; # the default is an MSIX bundle
    }
    "7zip.7zip"
  ];

  users.George = {
    profileDir = "C:\\Users\\George";
    files.".wslconfig".text = ''
      [wsl2]
      # The VM has 64 GiB and 12 vCPUs; leave Windows ~16 GiB.
      memory=48GB
      processors=12
    '';
  };

  wsl.distros.NixOS = {
    nixosConfiguration = nixosConfigurations.windows-wsl;
    user = "George";
    installDir = "C:\\WSL\\NixOS";
    default = true;
    keepAlive = true;
  };
}
