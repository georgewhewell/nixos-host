{
  config,
  lib,
  pkgs,
  inputs,
  network,
  ...
}: let
  windows = network.hosts.windows;
  # WSL2 on Windows 10 has no mirrored networking, so the distro sits behind
  # the VM's NAT; see hosts.windows.wslSsh in network.nix and the port proxy
  # in windows/machines/win10.nix.
  inherit (windows) wslSsh;
in {
  # NixOS as the WSL2 distro inside the Windows build VM on fuckup
  # (machines/x86/fuckup/windows-vm.nix). The Windows host itself is
  # described by windowsConfigurations.win10; this is its Linux half and the
  # fleet's Hydra builder endpoint for that VM.
  imports = [
    inputs.nixos-wsl.nixosModules.default
    ../../../profiles/fleet-core.nix
    ../../../services/buildfarm-slave.nix
    ../../../services/hydra-builder-slave.nix
  ];

  wsl = {
    enable = true;
    defaultUser = "grw";
    # Keep `.exe` execution working from the distro (and from builds that
    # are allowed to see the interop socket).
    interop.register = true;
    wslConf = {
      network.hostname = config.networking.hostName;
      # Resolve through the LAN DNS (fleet names), not WSL's NAT proxy.
      network.generateResolvConf = false;
      # Windows' PATH inside every Linux shell only slows completion down.
      interop.appendWindowsPath = false;
    };
  };

  networking.hostName = "windows-wsl";
  networking.nameservers = [network.dnsIp];
  networking.search = [network.domains.lan];

  sconfig.profile = "server";
  sconfig.home-manager.enable = true;

  # Windows' own sshd owns :22 on the VM; WSL's localhost relay would
  # otherwise fight it for the port.
  services.openssh.ports = [wslSsh.innerPort];

  # The distro's disk is a VHDX on the VM's C:, not tmpfs-friendly RAM.
  boot.tmp.useTmpfs = lib.mkForce false;

  nix.settings = {
    # 12 vCPUs, 64 GiB (see windows-vm.nix).
    max-jobs = 4;
    cores = 12;
    system-features = ["big-parallel" "wsl"];
    # Let sandboxed `wsl` builds run Windows executables through WSL
    # interop: the binfmt handler is /init, which reaches Windows over the
    # socket in /run/WSL. Such builds must set WSL_INTEROP=/run/WSL/1_interop
    # and exec the .exe from a directory that also exists outside the
    # sandbox (`/` or /nix/store) -- interop translates the cwd to a Windows
    # path and fails with EINVAL on the sandbox-only /build. Verified
    # 2026-09-23 with a store-path whoami.exe.
    extra-sandbox-paths = ["/init" "/run/WSL"];
  };

  deployment = {
    targetHost = network.primaryIp windows;
    targetPort = wslSsh.port;
    targetUser = "grw";
  };

  system.stateVersion = "26.05";
}
