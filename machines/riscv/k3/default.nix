{
  inputs,
  lib,
  network,
  pkgs,
  ...
}: let
  sshKeys = import ../../../profiles/ssh-keys.nix;
  self = network.hosts.k3;
in {
  imports = [
    inputs.nanokvm.nixosModules.boards.k3.pico-itx.uefi
    inputs.nanokvm.nixosModules.spacemitK3UfsDisko
    ../../../profiles/fleet-core.nix
    ../../../profiles/headless.nix
    ../../../profiles/pray-for-sd-card.nix
    ../../../profiles/wireless.nix
    ../../../profiles/watchdog.nix
  ];

  sconfig.profile = "server";
  system.stateVersion = "25.05";

  spacemit.k3 = {
    authorizedKeys = builtins.attrValues sshKeys;
    serialConsole.enable = false;
  };

  networking.hostName = "k3";
  networking.firewall.enable = lib.mkForce false;
  system.nixos-init.enable = lib.mkForce false;
  system.etc.overlay.enable = lib.mkForce false;
  services.userborn.enable = lib.mkForce false;
  services.nscd.enable = lib.mkForce false;
  system.nssModules = lib.mkForce [];
  nixpkgs.overlays = [
    inputs.nix-strix-halo.overlays.spacemitK3
  ];

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = ["systemd"];
    openFirewall = true;
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="misc", KERNEL=="tcm", SYMLINK+="tcm_sync_mem"
  '';

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand";
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  environment.systemPackages = with pkgs; [
    ethtool
    iw
    pciutils
    fastfetch
    btop
    llama-cpp-spacemit
  ] ++ [
    pkgs.pkgsBuildBuild.ghostty.terminfo
  ];

  fileSystems."/boot" = {
    device = lib.mkForce "/dev/disk/by-partlabel/ESP";
    fsType = lib.mkForce "vfat";
    options = lib.mkForce [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  systemd.network.wait-online.enable = lib.mkForce false;
  systemd.network.netdevs."10-bond0" = {
    netdevConfig = {
      Kind = "bond";
      Name = "bond0";
      MACAddress = self.mac;
    };
    bondConfig = {
      Mode = "active-backup";
      MIIMonitorSec = "1s";
    };
  };
  systemd.network.networks = {
    "20-end0-bond-slave" = {
      matchConfig.Name = "end0";
      networkConfig = {
        Bond = "bond0";
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "enslaved";
    };
    "20-enP2p1s0-bond-slave" = {
      matchConfig.Name = "enP2p1s0";
      networkConfig = {
        Bond = "bond0";
        ConfigureWithoutCarrier = true;
      };
      linkConfig.RequiredForOnline = "enslaved";
    };
    "30-bond0" = {
      matchConfig.Name = "bond0";
      address = [(network.cidrOf "lan" self.addresses.lan)];
      dns = [network.routerIp];
      routes = [
        {
          Gateway = network.gatewayIp "lan";
          Metric = 10;
        }
      ];
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
      };
      linkConfig.RequiredForOnline = "no";
    };
  };

  boot.kernelParams = lib.mkAfter [
    "noefi"
    "panic_on_oops=1"
    "softlockup_panic=1"
    "hung_task_panic=1"
    "workqueue.panic_on_stall=1"
    "workqueue.watchdog_thresh=60"
    "rcupdate.rcu_cpu_stall_timeout=60"
    "rcupdate.rcu_cpu_stall_suppress=0"
  ];

  boot.kernel.sysctl = {
    "kernel.panic" = lib.mkForce 5;
    "kernel.watchdog" = lib.mkForce 1;
    "kernel.panic_on_oops" = lib.mkForce 1;
    "kernel.softlockup_panic" = lib.mkForce 1;
    "kernel.hung_task_panic" = lib.mkForce 1;
    "kernel.hardlockup_panic" = lib.mkForce 1;
    "kernel.panic_on_rcu_stall" = lib.mkForce 1;
    "kernel.max_rcu_stall_to_panic" = lib.mkForce 1;
    "kernel.watchdog_thresh" = lib.mkForce 30;
    "kernel.hung_task_timeout_secs" = lib.mkForce 120;
    "kernel.panic_print" = lib.mkForce 63;
  };

  systemd.settings.Manager = {
    RuntimeWatchdogSec = lib.mkForce "30s";
    RuntimeWatchdogPreSec = lib.mkForce "off";
    RebootWatchdogSec = lib.mkForce "60s";
    KExecWatchdogSec = lib.mkForce "60s";
  };

  deployment = {
    targetHost = lib.mkDefault (network.ipOf "lan" self.addresses.lan);
    targetUser = "root";
    buildOnTarget = false;
  };
}
