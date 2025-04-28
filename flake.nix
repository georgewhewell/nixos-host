{
  nixConfig = {
    extra-substituters = [
      "https://colmena.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "colmena.cachix.org-1:7BzpDnjjH8ki2CT3f6GdOk7QAzPOl+1t3LvTLXqYcSg="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";

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

    foundry.url = "github:shazow/foundry.nix";
    foundry.inputs.nixpkgs.follows = "nixpkgs";

    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";

    apple-silicon.url = "github:tpwrules/nixos-apple-silicon";
    apple-silicon.inputs.nixpkgs.follows = "nixpkgs";

    mac-app-util.url = "github:hraban/mac-app-util";
    mac-app-util.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
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
    zen4localSystem = {
      gcc.arch = "znver4";
      gcc.tune = "znver4";
      system = "x86_64-linux";
    };
    zen4Pkgs = import nixpkgs {
      localSystem = zen4localSystem;

      # sphinx tests need clear network namespace
      overlays =
        localOverlays
        ++ [
          (self: super: {
            # vpp = super.vpp.override {
            #   doCheck = false;
            # };
            haskellPackages = super.haskellPackages.override {
              overrides = hself: hsuper: {
                # flaky tests
                tls = super.haskell.lib.dontCheck hsuper.tls;
                crypton = super.haskell.lib.dontCheck hsuper.crypton;
                crypton-x509 = super.haskell.lib.dontCheck hsuper.crypton-x509;
                crypton-x509-validation = super.haskell.lib.dontCheck hsuper.crypton-x509-validation;
              };
            };
            python312 = super.python312.override {
              packageOverrides = pyself: pysuper: {
                # flaky tests
                sphinx = pysuper.sphinx.overridePythonAttrs {
                  doCheck = false;
                };
              };
            };
          })
        ];
    };
  in rec {
    colmena =
      {
        meta = {
          description = "My personal machines";
          nixpkgs = nixpkgs.legacyPackages.x86_64-linux;
          specialArgs = {
            inherit inputs zen4Pkgs;
          };
        };
      }
      // builtins.mapAttrs
      (name: value: {
        nixpkgs.system = value.config.nixpkgs.system;
        imports = value._module.args.modules;
      })
      (self.nixosConfigurations);

    darwinConfigurations."air" =
      darwin.lib.darwinSystem
      {
        system = "aarch64-darwin";
        specialArgs = {inherit inputs;};
        modules = [
          ./machines/darwin-aarch64/darwin-configuration.nix
          inputs.home-manager.darwinModules.home-manager
          inputs.mac-app-util.darwinModules.default
          (
            {...}: {
              # nixpkgs.pkgs = patchedPkgs;
              nixpkgs.config.allowUnfree = true;
              nixpkgs.overlays =
                [
                  darwin.overlays.default
                ]
                ++ localOverlays;
            }
          )
        ];
      };
    darwinConfigurations."Georges-MacBook-Pro" = darwinConfigurations.air;

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
      self.nixosModule
      inputs;

    packages = nixpkgs.legacyPackages;

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
