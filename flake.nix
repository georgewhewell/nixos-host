{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nixpkgs.url = "path:/home/grw/src/nixpkgs";
    nixos-hardware.url = "github:NixOS/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    ethereum.url = "github:nix-community/ethereum.nix/feat/reth";

    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    foundry.url = "github:shazow/foundry.nix";
    foundry.inputs.nixpkgs.follows = "nixpkgs";

    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";

    vpp.url = "github:georgewhewell/vpp-flake";
    # vpp.inputs.nixpkgs.follows = "nixpkgs";

    rock5b.url = "github:aciceri/rock5b-nixos";
    # rock5b.url = "path:/home/grw/src/rock5b-nixos";

    apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    # rock5b.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { self
    , nixpkgs
    , darwin
    , nixos-hardware
    , home-manager
    , colmena
    , rust-overlay
    , foundry
    , vscode-server
    , vpp
    , rock5b
    , apple-silicon
    , ethereum
    , ...
    }:
    let
      mypkgs = import ./packages;
      deploy = import lib/deploy.nix;

      inherit (nixpkgs.lib) composeManyExtensions;
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
              (import ${rust-overlay}/default.nix)
            ];
          in
            # Apply all overlays to the input of the current "main" overlay
            foldl' (flip extends) (_: super) overlays self
        '';
      };

      flakeOverlay = (final: prev: {
        inherit vscode-server;
        vppPkgs = vpp.packages."x86_64-linux";
        ethPkgs = ethereum.packages."x86_64-linux";
      } // mypkgs { });

      localOverlays = map
        (f: import (./overlays + "/${f}"))
        (attrNames (readDir ./overlays)) ++ [
        rust-overlay.overlays.default
        flakeOverlay
        foundry.overlay
        # ethereum.overlays.default
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
        [ "x86_64-linux" "aarch64-linux" ]);
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
        };

      } // builtins.mapAttrs
        (name: value: {
          nixpkgs.system = value.config.nixpkgs.system;
          imports = value._module.args.modules;
        })
        (self.nixosConfigurations);

      darwinConfigurations."air" = darwin.lib.darwinSystem {
        system = "x86_64-darwin";
        modules = [
          ./machines/darwin-aarch64/darwin-configuration.nix
          home-manager.darwinModules.home-manager
          ({ config, pkgs, ... }: {
            nixpkgs.overlays = [ rust-overlay.overlays.default ];
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
          (_: _: { nixpkgs_src = toString nixpkgs; })
          (_: mypkgs)
        ];
      };

      nixosConfigurations = import ./machines colmena nixpkgs hardware self.nixosModule apple-silicon;

      packages = forAllSystems
        (system: mypkgs nixpkgs.legacyPackages.${system});

      apps = forAllSystems (system:
        with nixpkgs.legacyPackages.${system};
        {
          gnome-extensions = writeShellScriptBin "gnome-extensions" ''
            cat ${path}/pkgs/desktops/gnome/extensions/extensions.json |
            ${jq}/bin/jq -c '.[]|{name,ver:(.shell_version_map|keys)}'
          '';
        }
      );
    };
}
