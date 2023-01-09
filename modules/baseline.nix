{ config, lib, pkgs, ... }:

{
  boot = {
    kernelParams = [ "amdgpu.gpu_recovery=1" "panic=30" "ixgbe.allow_unsupported_sfp=1,1" ];
  };

  nixpkgs.config.allowUnfree = true;
  environment.variables.NIXPKGS_ALLOW_UNFREE = "1";

  security.sudo.extraConfig = "Defaults lecture=never";

  systemd.tmpfiles.rules = [ "e /nix/var/log - - - 30d" ];

  networking.hostId = builtins.substring 0 8 (builtins.hashString "md5" config.networking.hostName);

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
