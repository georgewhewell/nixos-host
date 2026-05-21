{pkgs, ...}: let
  keys = import ./ssh-keys.nix;
in {
  users.extraUsers.grw = {
    shell = pkgs.zsh;
    extraGroups = [
      "wheel"
      "libvirtd"
      "docker"
      "transmission"
      "audio"
      "video"
      "render"
      "dialout"
      "plugdev"
      "wireshark"
      "lp"
      "scanner"
      "networkmanager"
      "vboxsf"
      "sway"
      "go-ethereum"
      "ipfs"
    ];
    isNormalUser = true;
    linger = true;
    openssh.authorizedKeys.keys = builtins.attrValues keys;
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
}
