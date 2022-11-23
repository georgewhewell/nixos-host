{ config, lib, pkgs, ... }:

{
  boot = {
    kernelParams = [ "amdgpu.gpu_recovery=1" "panic=30" ];
  };

  nixpkgs.config.allowUnfree = true;
  environment.variables.NIXPKGS_ALLOW_UNFREE = "1";

  security.sudo.extraConfig = "Defaults lecture=never";

  systemd.tmpfiles.rules = [ "e /nix/var/log - - - 30d" ];

  networking.hostId = builtins.substring 0 8 (builtins.hashString "md5" config.networking.hostName);

  # # lower ipv4 DNS priority for networkmanager
  # networking.networkmanager.extraConfig = ''
  #   [connection]
  #   ipv4.dns-priority=101
  # '';

  nix = {
    daemonCPUSchedPolicy = "idle";
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  services = {
    earlyoom.enable = true;
  };
}
