# Fleet identity — the part of common.nix every member shares,
# including tiny embedded targets (the 256 MB riscv64 NanoKVM).
# Anything with a hardware or closure-size cost (enableAllFirmware,
# all-terminfo, pcscd, fwupd, irqbalance, udev hardware rules, …)
# stays in common.nix, which imports this.
{
  pkgs,
  lib,
  ...
}: let
  network = import ../network.nix lib;
in {
  imports = [
    ./users.nix
  ];

  # Expose `network` as a free function arg to every module in the same
  # NixOS evaluation. Set here because every host AND every container
  # imports this profile (via common.nix or directly), so it covers both
  # top-level and nested-container modules (containers don't inherit
  # parent specialArgs).
  _module.args.network = network;

  networking.hosts =
    {"127.0.0.1" = ["localhost"];}
    // network.toNixosHosts;

  environment.pathsToLink = ["/share/zsh"];

  programs.zsh = {
    enable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      AllowTcpForwarding = "yes";
      # Keys only, fleet-wide: several machines are directly reachable from
      # the internet (router WAN SSH, global IPv6), so no password paths.
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    extraConfig = ''
      MaxStartups 100:30:200
      MaxAuthTries 20
      MaxSessions 100
      StreamLocalBindUnlink yes
    '';
  };

  console = {
    font = lib.mkDefault "Lat2-Terminus16";
    keyMap = "uk";
  };

  i18n.defaultLocale = "en_GB.UTF-8";

  # nixpkgs.config is now set in pkgsFor (flake.nix) and read-only via readOnlyPkgs

  # Core nix settings are in modules/nix.nix (auto-imported)
  nix.gc = {
    automatic = true;
    dates = pkgs.lib.mkDefault "weekly";
  };
}
