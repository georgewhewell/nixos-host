{
  nixConfig = {
    extra-substituters = [
      "https://colmena.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    extra-trusted-public-keys = [
      "colmena.cachix.org-1:7BzpDnjjH8ki2CT3f6GdOk7QAzPOl+1t3LvTLXqYcSg="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/master";

    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    # nixpkgs-wayland.url = "github:nix-community/nixpkgs-wayland";
    # nixpkgs-wayland.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    ethereum.url = "github:nix-community/ethereum.nix";
    #ethereum.inputs.nixpkgs.follows = "nixpkgs";

    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/release";
    nix-bitcoin.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    foundry.url = "github:shazow/foundry.nix";
    foundry.inputs.nixpkgs.follows = "nixpkgs";

    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";

    apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    apple-silicon.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    nixos-hardware,
    home-manager,
    ...
  } @ inputs: let
    deploy = import lib/deploy.nix;

    inherit (inputs.nixpkgs.lib) composeManyExtensions;
    inherit (builtins) attrNames readDir;

    localOverlays = map (f: import (./overlays + "/${f}")) (attrNames (readDir ./overlays));

    hardware = nixos-hardware.nixosModules // import lib/hardware.nix "${nixpkgs}/nixos/modules";

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
    lib = {inherit forAllSystems hardware deploy;};

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
      // builtins.mapAttrs (name: value: {
        nixpkgs.system = value.config.nixpkgs.system;
        imports = value._module.args.modules;
      }) (self.nixosConfigurations);

    darwinConfigurations."air" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {inherit inputs;};
      modules = [
        ./machines/darwin-aarch64/darwin-configuration.nix
        inputs.home-manager.darwinModules.home-manager
        inputs.nix-homebrew.darwinModules.nix-homebrew
        (
          {...}: {
            nixpkgs.overlays = [
              darwin.overlays.default
            ];
          }
        )
      ];
    };
    darwinConfigurations."Georges-MacBook-Pro" = darwinConfigurations.air;
    inherit inputs;
    nixosModules =
      {
        inherit (home-manager.nixosModules) home-manager;
      }
      // nixpkgs.lib.mapAttrs' (name: type: {
        name = nixpkgs.lib.removeSuffix ".nix" name;
        value = import (./modules + "/${name}");
      }) (builtins.readDir ./modules);

    nixosModule = {
      imports = builtins.attrValues self.nixosModules;
      nixpkgs.overlays = [
        (composeManyExtensions localOverlays)
        # (_: mypkgs)
      ];
    };

    devShells = forAllSystems (system: {
      default = let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.mkShell {
          packages = [
            pkgs.nixVersions.nix_2_24
            inputs.colmena.defaultPackage.${system}
          ];

          shellHook = ''
            echo "Development shell loaded with colmena"
          '';
        };
    });

    nixosConfigurations =
      import ./machines
      hardware
      self.nixosModule
      inputs;

    packages = nixpkgs.legacyPackages;

    githubActions = let
      mkGithubMatrix = nixConf: {
        matrix = {
          include = builtins.map (x: {
            attr = "nixosConfigurations.${x}.config.system.build.toplevel";
            os = ["ubuntu-22.04"];
          }) (builtins.attrNames nixConf);
        };
      };
    in
      mkGithubMatrix self.nixosConfigurations;
  };
}
