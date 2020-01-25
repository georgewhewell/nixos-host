{ config, pkgs, lib, ... }:

{

  imports = [
    ../profiles/common.nix
    ../services/buildfarm.nix
    <nixpkgs/nixos/modules/profiles/minimal.nix>
  ];

  boot = {
    cleanTmpDir = true;
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    kernelParams = [ "boot.shell_on_fail" "panic=20"];
    supportedFilesystems = lib.mkForce [ "vfat" "nfs" ];
    initrd.supportedFilesystems = lib.mkForce [ "vfat" "ext4" ];
  };

  # installation-device.nix disables this stuff- re-enable
  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
  systemd.services.sshd.serviceConfig.restartSec = 3;

  sdImage.compressImage = false;

  # no documentation :X
  documentation = {
    enable = lib.mkOverride 0 false;
    nixos = lib.mkOverride 0 false;
  };

  services.nixosManual.showManual = lib.mkForce false;
  services.xserver.enable = lib.mkDefault false;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  fileSystems."/".options = [
    "relatime"
  ];

  powerManagement.enable = lib.mkDefault true;
  powerManagement.cpuFreqGovernor = "ondemand";

  nix.gc = {
    automatic = true;
    dates = "weekly";
  };

  systemd.services."lights-off" = let
    turn-off-leds = pkgs.writeScriptBin "turn-off-leds" ''
      for i in /sys/class/leds/* ; do
        echo 0 > $i/brightness
      done
    '';
    in {
      description = "turn off leds";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${turn-off-leds}/bin/turn-off-leds";
      };
  };

  systemd.services."io-is-busy" = let
    io-is-busy = pkgs.writeScriptBin "io-is-busy" ''
      cd /sys/devices/system/cpu
      for i in cpufreq/ondemand cpu0/cpufreq/ondemand cpu4/cpufreq/ondemand ; do
        if [ -d $i ]; then
          echo 1  >$i/io_is_busy
          echo 25 >$i/up_threshold
          echo 10 >$i/sampling_down_factor
        fi
      done
    '';
    in {
      description = "set io_is_busy";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${io-is-busy}/bin/io-is-busy";
      };
  };

  services.journald.extraConfig = ''
    SystemMaxUse=5M
    MaxLevelStore=err
  '';

}
