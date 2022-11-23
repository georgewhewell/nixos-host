{ config, lib, pkgs, ... }:

let
  cfg = config.sconfig.home-manager;
in
{
  options.sconfig.home-manager.enable = lib.mkEnableOption "Enable Home Manager";
  options.sconfig.home-manager.enableGraphical = lib.mkEnableOption "Enable graphical HM";
  options.sconfig.home-manager.enableLaptop = lib.mkEnableOption "Enable laptop";
  options.sconfig.home-manager.enableVscodeServer = lib.mkEnableOption "Enable vscode";

  config = lib.mkIf cfg.enable
    {
      environment.systemPackages = [ pkgs.home-manager ];

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.grw = { ... }: {
        hostId = config.networking.hostName;
        imports = [
          ../home/common.nix
          ../home/linux.nix
        ] ++ lib.optionals cfg.enableGraphical [
          ../home/graphical.nix
        ] ++ lib.optionals cfg.enableLaptop [
          ../home/laptop.nix
        ] ++ lib.optionals cfg.enableVscodeServer [
          ../home/vscode-server.nix
        ];
      };
    };
}
