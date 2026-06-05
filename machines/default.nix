nixosModule: inputs: mkSecret: network: pkgsFns:
let
  inherit (inputs.nixpkgs) lib;
  inherit (pkgsFns) pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmZnver5 allOverlays;

  # Base system builder - no GPU acceleration
  sys = system: machine:
    let
      pkgs = pkgsFor system;
    in
    lib.nixosSystem {
      inherit system pkgs;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  sysWithSpecialArgs = system: extraSpecialArgs: machine:
    let
      pkgs = pkgsFor system;
    in
    lib.nixosSystem {
      inherit system pkgs;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      } // extraSpecialArgs;
    };

  # Cross-compilation builder - builds on x86_64 for aarch64
  sysCross = machine:
    lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        {
          nixpkgs.buildPlatform = "x86_64-linux";
          nixpkgs.hostPlatform = "aarch64-linux";
          nixpkgs.overlays = allOverlays;
          nixpkgs.config = {
            allowUnfree = true;
            allowBroken = true;
          };
        }
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  # CUDA-enabled system builder for NVIDIA machines
  sysCuda = system: machine:
    let
      pkgs = pkgsForCuda system;
    in
    lib.nixosSystem {
      inherit system pkgs;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  # ROCm-enabled system builder for AMD GPU machines. Takes the
  # `pkgs` instance to use as an arg (so callers can swap between
  # the stock `pkgsForRocm` and the znver5-rebuilt
  # `pkgsForRocmZnver5` per-machine).
  mkRocmSystem = pkgs: machine:
    lib.nixosSystem {
      inherit pkgs;
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        { _module.args = inputs; }
        nixosModule
        machine
      ];
      extraModules = [
        inputs.colmena.nixosModules.deploymentOptions
      ];
      specialArgs = {
        inherit inputs mkSecret network;
      };
    };

  sysRocm = system: machine: mkRocmSystem (pkgsForRocm system) machine;
  sysRocmZnver5 = system: machine: mkRocmSystem (pkgsForRocmZnver5 system) machine;
in
{
  router = sysWithSpecialArgs "x86_64-linux"
    {
      routerStorageProfile = ../profiles/router/impermanence.nix;
    } ./x86/router;
  router-usb = sysWithSpecialArgs "x86_64-linux"
    {
      routerStorageProfile = ../profiles/router/usb-btrfs.nix;
    } ./x86/router;
  n100 = sys "x86_64-linux" ./x86/n100;

  # NVIDIA GPU machine
  fuckup = sysCuda "x86_64-linux" ./x86/fuckup;

  # AMD GPU machines. trex uses Vulkan/RADV and stays on the base package set;
  # the Strix machines use the ROCm package set for gfx1151 work.
  trex = sys "x86_64-linux" ./x86/trex;
  strix-1 = sysRocm "x86_64-linux" (import ./x86/strix-halo 1);
  # Keep both Strix machines on the same generic ROCm package set for
  # reliability work. The znver5 package set is useful for performance A/B
  # runs, but it makes routine system rebuilds depend on gccarch-specific
  # builders.
  strix-2 = sysRocm "x86_64-linux" (import ./x86/strix-halo 2);

  rock-5b = sys "aarch64-linux" ./aarch64/rock5b;
  prime = sys "aarch64-linux" ./aarch64/prime;
  neo2 = sys "aarch64-linux" ./aarch64/nanopi-neo2;

  # Cross-compiled aarch64 (built on x86_64)
  rock-5b-cross = sysCross ./aarch64/rock5b;
  prime-cross = sysCross ./aarch64/prime;
  neo2-cross = sysCross ./aarch64/nanopi-neo2;
}
