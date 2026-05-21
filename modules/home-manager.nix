{
  config,
  lib,
  pkgs,
  inputs,
  network,
  ...
}: let
  cfg = config.sconfig.home-manager;
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  options.sconfig.home-manager = {
    enable = lib.mkEnableOption "Enable Home Manager";
    enableGraphical = lib.mkEnableOption "Enable graphical HM";
    enableLaptop = lib.mkEnableOption "Enable laptop";
    enableVscodeServer = lib.mkEnableOption "Enable vscode";
    enableDevelopment = lib.mkEnableOption "Enable dev tools";
    enableCad = lib.mkEnableOption "Enable CAD tools (KiCad, FreeCAD, etc)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      environment.systemPackages = [pkgs.home-manager];

      home-manager.extraSpecialArgs = {inherit inputs network;};
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "hm-backup";
      home-manager.users.grw = {...}: {
        hostId = config.networking.hostName;
        imports =
          [
            ../home/common.nix
            ../home/linux.nix
          ]
          ++ (
            if cfg.enableGraphical
            then [
              ../home/graphical.nix
              ../home/gpg.nix
              ../home/zed.nix
            ]
            else [../home/headless.nix]
          )
          ++ lib.optionals cfg.enableLaptop [
            ../home/laptop.nix
          ]
          ++ lib.optionals cfg.enableVscodeServer [
            # ../home/zed.nix
            ../home/vscode-server.nix
          ]
          ++ lib.optionals cfg.enableDevelopment [
            ../home/development.nix
          ]
          ++ lib.optionals cfg.enableCad [
            ../home/cad.nix
          ];
      };
    })

    # When Home Manager is disabled, create minimal zshrc to prevent zsh-newuser-install prompt
    (lib.mkIf (!cfg.enable) {
      system.activationScripts.zshrc-fallback = ''
        if [ ! -e /home/grw/.zshrc ]; then
          echo "# Minimal zshrc (Home Manager not enabled)" > /home/grw/.zshrc
          chown grw:users /home/grw/.zshrc
        fi
      '';
    })
  ];
}
