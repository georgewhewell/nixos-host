{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.sconfig.home-manager;
in
{
  options.sconfig.home-manager = {
    enable = lib.mkEnableOption "Enable Home Manager";
    enableGraphical = lib.mkEnableOption "Enable graphical HM";
    enableLaptop = lib.mkEnableOption "Enable laptop";
    enableVscodeServer = lib.mkEnableOption "Enable vscode";
    enableDevelopment = lib.mkEnableOption "Enable dev tools";
  };

  config = lib.mkIf cfg.enable
    {
      environment.systemPackages = [ pkgs.home-manager ];

      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.users.grw = { ... }: {
        hostId = config.networking.hostName;
        imports = [
          ../home/common.nix
          ../home/linux.nix
        ] ++ (if cfg.enableGraphical then [
          ../home/graphical.nix
          ../home/gpg.nix
          ../home/zed.nix
        ] else [ ../home/headless.nix ]) ++ lib.optionals cfg.enableLaptop [
          ../home/laptop.nix
        ] ++ lib.optionals cfg.enableVscodeServer [
          ../home/vscode-server.nix
        ] ++ lib.optionals cfg.enableDevelopment [
          ../home/development.nix
        ];
      };
    };
}
