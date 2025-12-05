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

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-llamacpp-rocm = {
      url = "path:/Users/grw/src/nix-llamacpp-rocm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    p2pool-exporter = {
      url = "github:ForgottenBeast/p2pool-exporter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ath-kernel = {
      url = "git+https://git.kernel.org/pub/scm/linux/kernel/git/ath/ath.git?ref=for-current&shallow=1";
      flake = false;
    };

    # Track OpenZFS upstream directly for ZFS package source
    openzfs = {
      url = "github:openzfs/zfs";
      flake = false;
    };

    rust-overlay.url = "github:oxalica/rust-overlay";
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
    # Define mkSecret once and pass it to both machines and colmena
    secretsRegistry = import ./secrets/default.nix;
    mkSecret = name: overrides:
      secretsRegistry.${name} // overrides;

    # expose packages (after overlay)
    packages = forAllSystems (
      system:
        import nixpkgs {
          inherit system;
          overlays = [
            (composeManyExtensions localOverlays)
            inputs.chaotic.overlays.default
            inputs.rust-overlay.overlays.default
          ];
        }
    );

    colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;
    colmena =
      {
        meta = {
          description = "My personal machines";
          nixpkgs = nixpkgs.legacyPackages.x86_64-linux;
          specialArgs = {
            inherit inputs mkSecret;
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
        builtins.attrValues self.nixosModules
        ++ [
          inputs.sops-nix.nixosModules.sops
          ./profiles/sops.nix
        ];
      nixpkgs.overlays = [
        (composeManyExtensions localOverlays)
        # inputs.chaotic.overlays.default
        # inputs.rust-overlay.overlay
        (final: prev: let
          # Helper function to override ZFS in any linuxPackages set
          # Build with configFile = "all" to include both kernel modules and userspace tools
          mkZfsOverride = lpsuper: let
            zfsPkg = lpsuper.zfs_unstable.override {
              # Override the build to include both kernel and userspace
              configFile = "all";
            };
          in
            zfsPkg.overrideAttrs (o: {
              version = "openzfs-${inputs.openzfs.rev or "unknown"}";
              src = inputs.openzfs;
              configureFlags =
                o.configureFlags
                ++ [
                  "--enable-linux-experimental"
                ];
            });
        in {
          # Override base zfs_unstable for compatibility
          zfs_unstable = prev.zfs_unstable.overrideAttrs (o: {
            version = "openzfs-${inputs.openzfs.rev or "unknown"}";
            src = inputs.openzfs;
            configureFlags =
              o.configureFlags
              ++ [
                "--enable-linux-experimental"
              ];
          });

          # Override all standard kernel package sets
          linuxPackages = prev.linuxPackages.extend (lpself: lpsuper: {
            zfs_unstable = mkZfsOverride lpsuper;
          });
          linuxPackages_testing = prev.linuxPackages_testing.extend (lpself: lpsuper: {
            zfs_unstable = mkZfsOverride lpsuper;
          });
          linuxPackages_latest = prev.linuxPackages_latest.extend (lpself: lpsuper: {
            zfs_unstable = mkZfsOverride lpsuper;
          });

          # Override linuxPackagesFor to ensure custom kernels get the ZFS override
          linuxPackagesFor = kernel:
            (prev.linuxPackagesFor kernel).extend (lpself: lpsuper: {
              zfs_unstable = mkZfsOverride lpsuper;
            });
        })
      ];
    };

    devShells = forAllSystems (system: {
      default = let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.mkShell {
          packages = [
            inputs.colmena.defaultPackage.${system}
            pkgs.sops
            pkgs.ssh-to-age
          ];
        };
    });

    checks = {
      x86_64-linux = let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in {
        mtail-xmrig = pkgs.testers.runNixOSTest (import ./tests/mtail-xmrig.nix {inherit pkgs;});
      };
    };

    nixosConfigurations =
      import ./machines
      self.nixosModule
      inputs
      mkSecret;

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
