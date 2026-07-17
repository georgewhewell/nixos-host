nixosModule: inputs: mkSecret: network: pkgsFns:
let
  inherit (inputs.nixpkgs) lib;
  inherit (pkgsFns) pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmStrixHalo pkgsForRocmZnver5 allOverlays;

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
  sysRocmStrixHalo = system: machine: mkRocmSystem (pkgsForRocmStrixHalo system) machine;
  sysRocmZnver5 = system: machine: mkRocmSystem (pkgsForRocmZnver5 system) machine;

  # RISC-V (Sipeed NanoKVM / SG2002): a regular fleet member. The
  # board's hardware/boot stack (cross pins, kernel, DTB, SD image,
  # nanokvm services) comes from the nanokvm flake as a plain module
  # (`nixosModules.boards.pcie.mainline.sd`), composed with the same
  # shared `nixosModule` base every other host gets. The board module
  # pins nixpkgs host/buildPlatform itself (x86_64 → riscv64 cross),
  # so no `pkgs`/system is passed here. The machine file imports the
  # lightweight `profiles/fleet-core.nix` rather than common.nix —
  # 256 MB has no room for enableAllFirmware and friends.
  sysRiscvNanokvm = machine:
    lib.nixosSystem {
      modules = [
        { _module.args = inputs; }
        inputs.nanokvm.nixosModules.boards.pcie.mainline.sd
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

  # RISC-V SpacemiT K3 Pico-ITX. The reusable board support, kernel,
  # firmware, and cross-platform setup come from the nanokvm flake; this
  # builder adds the fleet base and disko module.
  sysRiscvK3 = machine:
    lib.nixosSystem {
      modules = [
        {
          nixpkgs.overlays = allOverlays;
        }
        { _module.args = inputs; }
        inputs.disko.nixosModules.disko
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

in
{
  router = sys "x86_64-linux" ./x86/router;
  router-usb = sys "x86_64-linux" ./x86/router;
  n100 = sys "x86_64-linux" ./x86/n100;

  # NVIDIA GPU machine
  fuckup = sysCuda "x86_64-linux" ./x86/fuckup;

  # AMD GPU machines. trex uses Vulkan/RADV and stays on the base package set;
  # the Strix machines use the ROCm package set for gfx1151 work.
  trex = sys "x86_64-linux" ./x86/trex;
  strix-1 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 1);
  # Keep both Strix machines on the same generic ROCm package set for
  # reliability work. The znver5 package set is useful for performance A/B
  # runs, but it makes routine system rebuilds depend on gccarch-specific
  # builders.
  strix-2 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 2);
  strix-3 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 3);
  strix-4 = sysRocmStrixHalo "x86_64-linux" (import ./x86/strix-halo 4);

  rock-5b = sys "aarch64-linux" ./aarch64/rock5b;
  prime = sys "aarch64-linux" ./aarch64/prime;
  neo2 = sys "aarch64-linux" ./aarch64/nanopi-neo2;
  bluefield2 = sys "aarch64-linux" ./aarch64/bluefield2;

  # Cross-compiled aarch64 (built on x86_64)
  rock-5b-cross = sysCross ./aarch64/rock5b;
  prime-cross = sysCross ./aarch64/prime;
  neo2-cross = sysCross ./aarch64/nanopi-neo2;
  bluefield2-cross = sysCross ./aarch64/bluefield2;
  bluefield2-rescue = sysCross ./aarch64/bluefield2/rescue.nix;

  # RISC-V (cross-built on x86_64)
  nanokvm = sysRiscvNanokvm ./riscv/nanokvm;
  k3 = sysRiscvK3 ./riscv/k3;
  k3Installer = sysRiscvK3 ./riscv/k3/kexec-installer.nix;
  k3InitrdRescue = sysRiscvK3 ./riscv/k3/initrd-rescue.nix;
  k3SdImage = sysRiscvK3 ./riscv/k3/sd-image.nix;

  strix-installer = sys "x86_64-linux" ./x86/strix-installer.nix;
}
