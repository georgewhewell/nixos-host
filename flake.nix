{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";
    nixpkgs-wayland.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    ethereum.url = "github:nix-community/ethereum.nix";
    #ethereum.inputs.nixpkgs.follows = "nixpkgs";

    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/release";
    nix-bitcoin.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";

    foundry.url = "github:shazow/foundry.nix";
    foundry.inputs.nixpkgs.follows = "nixpkgs";

    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";

    apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    apple-silicon.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self
    , nixpkgs
    , darwin
    , nixos-hardware
    , home-manager
    , colmena
    , ...
    } @ inputs:
    let
      mypkgs = import ./packages;
      deploy = import lib/deploy.nix;

      inherit (inputs.nixpkgs.lib) composeManyExtensions;
      inherit (builtins) attrNames readDir;

      overlayCompat = { pkgs, lib, ... }: {
        # nix.nixPath = [
        #   "nixpkgs-overlays=/etc/overlays-compat/"
        # ];
        environment.etc."overlays-compat/overlays.nix".text = ''
          self: super:
          with super.lib;
          let
            # Load the system config and get the `nixpkgs.overlays` option
            overlays = [
            ];
          in
            # Apply all overlays to the input of the current "main" overlay
            foldl' (flip extends) (_: super) overlays self
        '';
      };

      localOverlays = map
        (f: import (./overlays + "/${f}"))
        (attrNames (readDir ./overlays)) ++ [
        # forced
        (_: super:
          let
            addPatches = pkg: patches:
              pkg.overrideAttrs (oldAttrs: {
                patches = (oldAttrs.patches or [ ]) ++ patches;
              });
          in
          {
            nixpkgs_src = toString nixpkgs;
            # hyprland-displaylink = with inputs.hyprland.packages.${super.system};
            #   hyprland.override {
            # wlroots = addPatches super.wlroots [ ./displaylink.psatch ];
            # wlroots-hyprland = addPatches wlroots-hyprland [ ./displaylink.patch ];
            # };
          })

      ];

      hardware =
        nixos-hardware.nixosModules //
        import lib/hardware.nix "${nixpkgs}/nixos/modules";

      hm =
        home-manager.nixosModules.home-manager;

      vscode-server =
        vscode-server.nixosModules.home;

      forAllSystems = f: builtins.listToAttrs (map
        (name: { inherit name; value = f name; })
        [
          "x86_64-linux"
          # "aarch64-linux"
        ]);
      consts = import ./consts.nix { inherit (inputs.nixpkgs) lib; };
    in
    {
      lib = { inherit forAllSystems hardware deploy; };

      colmena = {
        meta = {
          description = "My personal machines";
          nixpkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ (composeManyExtensions localOverlays) ];
          };
          specialArgs = {
            inherit inputs;
            inherit consts;
          };
        };

      } // builtins.mapAttrs
        (name: value: {
          nixpkgs.system = value.config.nixpkgs.system;
          imports = value._module.args.modules;
        })
        (self.nixosConfigurations);

      darwinConfigurations."air" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          ./machines/darwin-aarch64/darwin-configuration.nix
          inputs.home-manager.darwinModules.home-manager
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [
              darwin.overlays.default
            ];
          })
        ];
      };

      nixosModules =
        {
          inherit hm;
          inherit overlayCompat;
        } //
        nixpkgs.lib.mapAttrs'
          (name: type: {
            name = nixpkgs.lib.removeSuffix ".nix" name;
            value = import (./modules + "/${name}");
          })
          (builtins.readDir ./modules);

      nixosModule = {
        imports = builtins.attrValues self.nixosModules;
        nixpkgs.overlays = [
          (composeManyExtensions localOverlays)
          (self: super:
            let
              addPatches = pkg: patches:
                pkg.overrideAttrs (oldAttrs: {
                  patches = (oldAttrs.patches or [ ]) ++ patches;
                });
            in
            {
              nixpkgs_src = toString nixpkgs;
              # wlroots-patched-1 = super.wlroots_0_17.override {
              #   enableXWayland = true;
              # };
              # wlroots-patched = addPatches self.wlroots-patched-1 [ ./packages/patches/displaylink.patch ];
              # sway-unwrapped = super.sway-unwrapped.override ({
              #   wlroots = self.wlroots-patched;
              # });
            })
          (_: mypkgs)
        ];
      };

      nixosConfigurations = import
        ./machines
        colmena
        nixpkgs
        hardware
        self.nixosModule
        inputs
        consts;

      packages = forAllSystems
        (system: mypkgs nixpkgs.legacyPackages.${system});

      githubActions =
        let
          mkGithubMatrix = nixConf: {
            matrix = {
              include = builtins.map
                (x: {
                  attr = "nixosConfigurations.${x}.config.system.build.toplevel";
                  os = [ "ubuntu-22.04" ];
                })
                (builtins.attrNames nixConf);
            };
          };
        in
        mkGithubMatrix
          self.nixosConfigurations;
    };
}
