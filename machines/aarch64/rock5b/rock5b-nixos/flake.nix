{
  description = "Opinionated NixOS modules and building infrastructure for Radxa Rock5B";

  nixConfig = {
    extra-substituters = ["https://rock5b-nixos.cachix.org"];
    extra-trusted-public-keys = ["rock5b-nixos.cachix.org-1:bXHDewFS0d8pT90A+/YZan/3SjcyuPZ/QRgRSuhSPnA="];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/f2537a505d45c31fe5d9c27ea9829b6f4c4e6ac5";
    kernel-src = {
      url = "github:radxa/kernel";
      flake = false;
    };
    tow-boot = {
      url = "github:aciceri/Tow-Boot/rock5b";
      flake = false;
    };
    fan-control = {
      url = "github:pymumu/fan-control-rock5b";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    kernel-src,
    tow-boot,  
    fan-control,
  }: let
    lib = nixpkgs.lib.extend (selfLib: superLib: {
      supportedSystems = selfLib.intersectLists selfLib.systems.flakeExposed [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: selfLib.genAttrs selfLib.supportedSystems (system: f system);
      evalConfig = import "${nixpkgs}/nixos/lib/eval-config.nix";
      buildConfig = hostSystem: config:
        selfLib.evalConfig {
          system = hostSystem;
          modules = [
            config
            ./modules/cross
          ];
        };
    });
    pkgs = nixpkgs.legacyPackages;
    pkgsCross = system: (import nixpkgs {localSystem = system; crossSystem = "aarch64-linux";});
  in {
    nixosModules = {
      kernel = {config, ...}: {
        imports = [./modules/kernel];
        nixpkgs.overlays = [
          (_: _: {
            inherit (self.packages.${config.nixpkgs.localSystem.system}) linux_rock5b;
          })
        ];
      };

      fan-control = {config, ...}: {
        imports = [./modules/fan-control];
        nixpkgs.overlays = [
          (_: _: {
            inherit (self.packages.${config.nixpkgs.localSystem.system}) fan-control;
          })
        ];
      };

      rootfs = {
        imports = [./modules/rootfs];
        _module.args = {nixpkgsPath = "${nixpkgs}";};
      };

      firstBoot = {
        imports = [
          self.nixosModules.default
          self.nixosModules.rootfs
        ];
        services.openssh = {
          enable = true;
        };
        users.users.root.password = "";
      };

      default = {
        imports = [
          self.nixosModules.kernel
          self.nixosModules.fan-control
        ];
      };
    };

    packages = lib.forAllSystems (system: {
      
      rootfs = (lib.buildConfig system self.nixosModules.firstBoot).config.system.build.rootfsImage;
      
      fan-control = (pkgsCross system).callPackage ./pkgs/fan-control {
        src = "${fan-control}/src";
      };
      
      linux_rock5b = (pkgsCross system).callPackage ./pkgs/kernel {
        src = "${kernel-src}";
      };
      
      uboot = (import tow-boot {
        pkgs = import "${tow-boot}/nixpkgs.nix" {
          localSystem = system;
        };
        configuration.nixpkgs.localSystem.system = system;
      }).radxa-rock5b;

      flash = pkgs.${system}.callPackage ./pkgs/flash {
        inherit (self.packages.${system}) rootfs tow-boot;
      };
      
      default = self.packages.${system}.rootfs;       
    });

    apps = lib.forAllSystems (system: {
      flash = {
        type = "app";
        program = "${self.packages.${system}.flash}/bin/flash";
      };
      default = self.apps.${system}.flash;
    });

    formatter = lib.forAllSystems (system: pkgs.${system}.alejandra);
  };
}
