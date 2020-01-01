{ config, pkgs, lib, ... }:

{

  imports = [
    ../profiles/common.nix
    <nixpkgs/nixos/modules/profiles/minimal.nix>
  ];

  boot = {
    cleanTmpDir = true;
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    kernelParams = [ "boot.shell_on_fail" "panic=20"];
    supportedFilesystems = lib.mkForce [ "vfat" "nfs" ];
    initrd.supportedFilesystems = lib.mkForce [ "vfat" "nfs" ];
  };

  # failing builds
  # services.udisks2.enable = lib.mkDefault false;
  # security.polkit.enable = lib.mkDefault false;
  security.rngd.enable = lib.mkDefault true;

  # installation-device.nix disables this stuff- re-enable
  security.sudo.enable = true;
  systemd.services.sshd.wantedBy = pkgs.lib.mkForce [ "multi-user.target" ];
  systemd.services.sshd.serviceConfig.restartSec = 3;

  sdImage.compressImage = false;

  # no documentation :X
  documentation = {
    enable = lib.mkOverride 0 false;
    nixos = lib.mkOverride 0 false;
  };

  services.nixosManual.showManual = lib.mkForce false;

  # `xterm` is being included even though this is GUI-less.
  # → https://github.com/NixOS/nixpkgs/pull/62852
  services.xserver.enable = lib.mkDefault false;
  services.xserver.desktopManager.xterm.enable = lib.mkForce false;

  zramSwap.enable = true;

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

  /* services.journald.extraConfig = ''
    SystemMaxUse=5M
    MaxLevelStore=err
  ''; */

  users.extraUsers.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCyo9ZxvNb/4GJ78r5vi+rWehxjdMUNY4yA/7ze7EXRi1AvUzfAJx04OGaq9oj1FDSnac3BeeIuYTqmE13ZS9amiVf2HasBWUqEQC1FHOBiqqzacijzheWC0E7CXa1xGaYETZzBhjxgVYWTKWRm6GSGQMzVvjt/LZ0dqXWyqArC3t7gbmsFVCT1q3O2oSaE7G61xrqZjxWZqtE3EOu8+nnEHhBomqav1Ap+RDoWXuooNBdX9KkKofqA2aM9+UF5TMKi8CrrmBzYjHTkTH+5yRhj5kq/xnegY1/qYd6FFuQuZ/TvtDqpB/CGNZtiVXXLGhw+WZQ8iUu8qA1uSKL8md1d root@fuckup"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCoqpsUUtxaO0QzI9MxCs5tRjsbORDwpjFjuUFdGHJwZqm7A2MzrRV7EKfqfolgxnyaAFs7IM9AZ7o9Lus2MWX89c4OAW0upeoj2qsXMiFZH7z50Cdmg/YMw5DtVMZwPBTl0S1COWfhw959QntlTjhcYh3usIq9b3XeTELGtJSk5RmTjPIA2LJ4cemx3Ru11SySvk0LsI3uCv0Vhy9n17g1sg5eekRs5Nvg1AJtOQcH4Du/0rUwwEDd9Zjn0YiF/uPVMVh22JzWVE5dbe81g8dw+mR6GRnN3vlYbU+JgGvMKgs2DeGvPHSJWl9rwKUVO6wuruzZH+1q2HxAr58ndz81 root@nixhost"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/yARn1J0K+z8kdhLGxZgCe0kIrCJg5o7DC0oITmbzE3YKrubFVNn7zHkwzRw0b8kjfZFIxFbo5toOFCO0VN5biujrWbutzlLjTnFP0YqoL47XD58gU+TWZb/9qoV1Yjj1OUXJ+93ZTGjXGyZ+0FDtp84lFoDgSvBXf8C742g4gm6KkXYFfGYMz8LRKSnXYpeuMu18UdZVo33m8aweTvZ+m7riD6YCJILNIPFIvVExg+UNzOh4t0Hrj+O5ir9NNCqQeu633yXKlOMShbQVmmPZfrxpg24Fv5orX/pZZM+fHB94yO5wunlzxVsF5GVjCKJL5Gj/SqCRePohDiePNdP/ grw@fuckup"
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHCp/KhshTrp+p1TQOp3PZfwvj+pAGzm7Z4tbRYImpHNS9octfJ4sSmL4X4YQSu4PbpM/9Jo5UzVPpCRpD6OOiA= grw@nixhost"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDezYhZFCQE3M73WZOeotwWqqzbZgBRlL11n8lwJt+t/3uoSHO3C4iY2FfIwzB/FkSDIL9cLYrCTghwQZ3QmdGM5wGv1NjizVL6+HWO82a3xmqV1Cv0fTlalEiQ7LazotLIk3pWOTmJ5ZIqNnGHFVME6R6Yz8NGaws/CyY1LxQuM9vRwO1H+3a2Y6vVaURQvY6sM5XtTgcvH/db84UU2uqIPsyTbBUyh5Quq7hcViWk8kvZHc2UIrpWBh48A+r8vkj3UvBlEIRSP8QjI3W+2bIMgk6quWs1IjiCXgLH0eT3my0iA04p/SI3hSLyigGkd/YuJxSm2v9sLfQWm5A9h3Z/"
  ];

  users.extraUsers.grw = {
    extraGroups = [
      "wheel"
      "libvirtd"
      "docker"
      "transmission"
      "audio"
      "dialout"
      "plugdev"
      "wireshark"
      "lp"
      "scanner"
      "networkmanager"
      "vboxsf"
    ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHCp/KhshTrp+p1TQOp3PZfwvj+pAGzm7Z4tbRYImpHNS9octfJ4sSmL4X4YQSu4PbpM/9Jo5UzVPpCRpD6OOiA= grw@nixhost"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBZ7a3vc5ex0sSTz8uitNrf96k5iURfRL8e9AoM93Yw1oKk5CD4mOZLOb7Av7SwFLtvgGMTnpLsxuusj2QoGTCk= grw@h9fp4whfi.local"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/yARn1J0K+z8kdhLGxZgCe0kIrCJg5o7DC0oITmbzE3YKrubFVNn7zHkwzRw0b8kjfZFIxFbo5toOFCO0VN5biujrWbutzlLjTnFP0YqoL47XD58gU+TWZb/9qoV1Yjj1OUXJ+93ZTGjXGyZ+0FDtp84lFoDgSvBXf8C742g4gm6KkXYFfGYMz8LRKSnXYpeuMu18UdZVo33m8aweTvZ+m7riD6YCJILNIPFIvVExg+UNzOh4t0Hrj+O5ir9NNCqQeu633yXKlOMShbQVmmPZfrxpg24Fv5orX/pZZM+fHB94yO5wunlzxVsF5GVjCKJL5Gj/SqCRePohDiePNdP/ grw@fuckup"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDezYhZFCQE3M73WZOeotwWqqzbZgBRlL11n8lwJt+t/3uoSHO3C4iY2FfIwzB/FkSDIL9cLYrCTghwQZ3QmdGM5wGv1NjizVL6+HWO82a3xmqV1Cv0fTlalEiQ7LazotLIk3pWOTmJ5ZIqNnGHFVME6R6Yz8NGaws/CyY1LxQuM9vRwO1H+3a2Y6vVaURQvY6sM5XtTgcvH/db84UU2uqIPsyTbBUyh5Quq7hcViWk8kvZHc2UIrpWBh48A+r8vkj3UvBlEIRSP8QjI3W+2bIMgk6quWs1IjiCXgLH0eT3my0iA04p/SI3hSLyigGkd/YuJxSm2v9sLfQWm5A9h3Z/"
    ];
  };
}
