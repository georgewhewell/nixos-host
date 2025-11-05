{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    colmena.url = "github:zhaofengli/colmena";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    ethereum.url = "github:nix-community/ethereum.nix";

    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/release";
    nix-bitcoin.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";

    nix-ai-tools.url = "github:numtide/nix-ai-tools";

    mac-app-util.url = "github:hraban/mac-app-util";
    mac-app-util.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";

    nix-llamacpp-rocm = {
      url = "path:/Users/grw/src/nix-llamacpp-rocm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    p2pool-exporter = {
      url = "github:ForgottenBeast/p2pool-exporter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ath-kernel = {
      url = "git+https://git.kernel.org/pub/scm/linux/kernel/git/ath/ath.git?ref=ath-next&shallow=1";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    colmena,
    disko,
    ...
  } @ inputs: let
    inherit inputs;
    inherit (inputs.nixpkgs.lib) composeManyExtensions;
    inherit (builtins) attrNames readDir;

    localOverlays = map (f: import (./overlays + "/${f}")) (attrNames (readDir ./overlays));
    forAllSystems = f:
      builtins.listToAttrs (
        map
        (name: {
          inherit name;
          value = f name;
        })
        [
          "x86_64-linux"
          "aarch64-darwin"
        ]
      );
  in rec {
    colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;
    colmena =
      {
        meta = {
          description = "My personal machines";
          nixpkgs = nixpkgs.legacyPackages.x86_64-linux;
          specialArgs = {
            inherit inputs;
          };
        };
      }
      // builtins.mapAttrs
      (name: value: {
        nixpkgs.system = value.config.nixpkgs.system;
        imports = value._module.args.modules;
      })
      (self.nixosConfigurations);

    darwinConfigurations."air" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {inherit inputs localOverlays;};
      modules = [./machines/darwin-aarch64/air.nix];
    };

    darwinConfigurations."Georges-MacBook-Pro" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {inherit inputs localOverlays;};
      modules = [./machines/darwin-aarch64/mbp.nix];
    };

    nixosModules =
      nixpkgs.lib.mapAttrs'
      (name: type: {
        name = nixpkgs.lib.removeSuffix ".nix" name;
        value = import (./modules + "/${name}");
      })
      (builtins.readDir ./modules);

    nixosModule = {
      imports =
        builtins.attrValues self.nixosModules;
      nixpkgs.overlays = [
        (composeManyExtensions localOverlays)
        inputs.chaotic.overlays.default
      ];
    };

    devShells = forAllSystems (system: {
      default = let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.mkShell {
          packages = [
            inputs.colmena.defaultPackage.${system}
          ];
        };
    });

    nixosConfigurations =
      import ./machines
      self.nixosModule
      inputs;

    githubActions = let
      mkGithubMatrix = nixConf: {
        matrix = {
          include =
            builtins.map
            (x: {
              attr = "nixosConfigurations.${x}.config.system.build.toplevel";
              os = ["ubuntu-22.04"];
            })
            (builtins.attrNames nixConf);
        };
      };
    in
      mkGithubMatrix self.nixosConfigurations;
  };
}
