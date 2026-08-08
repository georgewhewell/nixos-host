{
  description = "satanic.link fleet: NixOS (x86/aarch64/riscv), nix-darwin, OpenWrt and RouterOS configs, deployed with colmena";

  inputs = {
    nixpkgs.follows = "nix-strix-halo/nixpkgs";

    # ESPHome only. The fleet nixpkgs (via nix-strix-halo) carries esphome
    # 2026.6.2, which predates the mipi_spi board presets we want for the
    # Waveshare AMOLED panels. Bumping the whole fleet for a devShell tool is
    # not worth a world rebuild, so track a separate unstable purely for
    # `pkgs.esphome`; nothing else consumes this input.
    nixpkgs-esphome.url = "github:NixOS/nixpkgs/nixos-unstable";

    colmena.url = "github:zhaofengli/colmena";
    colmena.inputs.nixpkgs.follows = "nixpkgs";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";
    nixos-hardware.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.inputs.home-manager.follows = "home-manager";

    ethereum.url = "github:nix-community/ethereum.nix/8f01580481e88e169b7ada56f1500dccd6cefe61";
    ethereum.inputs.nixpkgs.follows = "nixpkgs";

    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/release";
    nix-bitcoin.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    # No nixpkgs follow: its flake eagerly instantiates x86_64-darwin, which
    # nixpkgs 26.11 (via nix-strix-halo) no longer supports.
    vscode-server.url = "github:nix-community/nixos-vscode-server";

    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    nix-ai-tools.inputs.nixpkgs.follows = "nixpkgs";

    mac-app-util.url = "github:hraban/mac-app-util";
    mac-app-util.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Declarative OpenWrt image builder — used to build the custom UniFi AC-Pro
    # firmware (full wpad-mbedtls for 802.11v, luci, baked dumb-AP config).
    openwrt-imagebuilder.url = "github:astro/nix-openwrt-imagebuilder";
    openwrt-imagebuilder.inputs.nixpkgs.follows = "nixpkgs";

    nix-strix-halo = {
      # Keep ignored benchmark artifacts out of the flake source. A raw path
      # input hashed the multi-gigabyte .bench-artifacts tree and invalidated
      # every fleet evaluation whenever a run appended a log.
      url = "git+file:///mnt/Home/src/nix-strix-halo?shallow=1";
      inputs.thunderbolt-ibverbs.follows = "thunderbolt-ibverbs-kernel";
    };

    thunderbolt-ibverbs-kernel = {
      url = "path:/mnt/Home/src/thunderbolt-ibverbs-gda-v2-rebase";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.linux-src.follows = "linux-src";
    };

    # NOTE: this flake pins its own nixpkgs fork (vitis-ai branch) because
    # xrt / xrt-plugin-amdxdna / xrt-amdxdna live there; do not add
    # `inputs.nixpkgs.follows = "nixpkgs"`.
    nix-amd-npu.url = "github:robcohen/nix-amd-npu";

    hellas = {
      # Local deploy input while Codex Fetch support is ahead of the remote branch.
      url = "git+file:///mnt/Home/src/hellas?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    nanokvm = {
      # Keep .git, ignored captures, and local Wi-Fi credentials out of the
      # flake source. Keep NanoKVM's tested nixpkgs pin as well: following the
      # Strix pin invalidates the cached RISC-V cross closure and rebuilds the
      # toolchain without changing the host integration contract.
      url = "git+file:///mnt/Home/src/nixos-nanokvm?shallow=1";
      inputs.disko.follows = "disko";
    };

    p2pool-exporter = {
      url = "github:ForgottenBeast/p2pool-exporter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ath-kernel = {
      url = "git+https://git.kernel.org/pub/scm/linux/kernel/git/ath/ath.git?ref=for-next&shallow=1";
      flake = false;
    };

    # Collabora RK3588 hardware enablement kernel (rockchip-devel branch)
    linux-rockchip-src = {
      url = "git+https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux.git?ref=rockchip-devel&shallow=1";
      flake = false;
    };

    linux-src = {
      url = "git+https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git?ref=refs/tags/v7.2-rc2&shallow=1";
      flake = false;
    };

    # Broadcom PCI/PCIe SDK 8.23 source used by PlxSvc and PlxCm.
    # The extracted vendor tree is kept on the shared /mnt/Home volume.
    plx-sdk = {
      url = "path:/mnt/Home/pde/PlxSdk";
      flake = false;
    };

    # Local btop checkout with GPU clock/power history graphs and
    # gpu_graph_upper/lower selection (gpu-metric-graphs branch), for
    # testing on fuckup before upstreaming.
    btop-src = {
      url = "git+file:///mnt/Home/src/btop?ref=gpu-metric-graphs";
      flake = false;
    };

    # Track OpenZFS upstream directly for ZFS package source
    openzfs = {
      url = "github:openzfs/zfs";
      flake = false;
    };

    # DisplayLink EVDI kernel module — track upstream for nix flake update
    evdi-src = {
      url = "github:DisplayLink/evdi";
      flake = false;
    };

    mt7927.url = "github:cmspam/mt7927-nixos";
    mt7927.inputs.nixpkgs.follows = "nixpkgs";

    mlnx-ofed-nixos = {
      url = "github:codgician/mlnx-ofed-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Applied globally in allOverlays but consumed only by packages/tari
    # (rust-bin.fromRustupToolchainFile); goes away if tari mining does.
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , nixpkgs
    , darwin
    , colmena
    , disko
    , ...
    } @ inputs:
    let
      inherit inputs;
      inherit (inputs.nixpkgs.lib) composeManyExtensions;
      inherit (builtins) attrNames readDir;

      localOverlays = map (f: import (./overlays + "/${f}")) (attrNames (readDir ./overlays));

      # Unified overlay list - applied consistently across all outputs
      allOverlays = [
        (composeManyExtensions localOverlays)
        inputs.rust-overlay.overlays.default
        inputs.hellas.overlays.default
        # Experimental NVIDIA DOCA-OFED packages. Keep the overlay before the
        # custom kernel definitions so its packagesFor extension also applies
        # to linux_7_2_rc2; hosts opt in to the modules separately.
        inputs.mlnx-ofed-nixos.overlays.default
        (final: prev: {
          firefox-addons = final.callPackage "${inputs.firefox-addons}" {
            buildMozillaXpiAddon =
              (import "${inputs.firefox-addons}/../../lib/mozilla.nix" { lib = final.lib; }).mkBuildMozillaXpiAddon { inherit (final) stdenv fetchurl; };
          };
          # Pull antigravity (Google's gemini-cli replacement) from nix-ai-tools
          # so it's available as a top-level pkg attribute.
          antigravity = inputs.nix-ai-tools.packages.${final.stdenv.hostPlatform.system}.antigravity-cli;
        })
        # Collabora RK3588 hardware enablement kernel
        (final: prev: {
          linux-rockchip = prev.callPackage ./packages/linux-rockchip {
            src = inputs.linux-rockchip-src;
          };
          linuxPackages_rockchip = prev.linuxKernel.packagesFor final.linux-rockchip;
        })
        # Local btop with GPU metric graphs (see btop-src input). Same 1.4.7
        # base as nixpkgs, so the existing derivation (no patches) applies.
        (final: prev: {
          btop = prev.btop.overrideAttrs (old: {
            version = "1.4.7-gpu-graphs";
            src = inputs.btop-src;
            # Binary still reports plain 1.4.7; skip versionCheckHook.
            doInstallCheck = false;
          });
        })
        # Torvalds release-candidate kernel used by the router while validating
        # networking fixes ahead of the next nixpkgs linux_testing bump.
        (final: prev: {
          linux_7_2_rc2 = prev.linuxKernel.kernels.linux_testing.override {
            structuredExtraConfig = with final.lib.kernel; {
              CRYPTO_DRBG_CTR = final.lib.mkForce unset;
              CRYPTO_DRBG_HASH = final.lib.mkForce unset;
              RANDOM_KMALLOC_CACHES = final.lib.mkForce unset;
            };
            argsOverride = {
              src = inputs.linux-src;
              version = "7.2-rc2";
              modDirVersion = "7.2.0-rc2";
            };
          };
          linuxKernel =
            prev.linuxKernel
            // {
              packages =
                prev.linuxKernel.packages
                // {
                  linux_7_2_rc2 =
                    (prev.linuxKernel.packagesFor final.linux_7_2_rc2).extend (lpFinal: lpPrev: {
                      ryzen-smu = lpPrev.ryzen-smu.overrideAttrs (old: {
                        patches = (old.patches or [ ]) ++ [
                          ./profiles/patches/ryzen-smu-linux-7.2-cpuid-header.patch
                        ];
                      });
                    });
                };
            };
        })
        # OpenZFS 2.4.99 for kernel 7.2-rc support (remove when nixpkgs zfs_unstable >= 2.5).
        # nixpkgs' postPatch pins the Linux-Maximum META check to 7.0 and still
        # references the pre-2.4.99 libshare paths; retarget both for the openzfs
        # master snapshot, and temporarily lift its declared maximum for 7.2-rc.
        (final: prev:
          let
            fixPostPatch = pp:
              builtins.replaceStrings
                [
                  "7\\.0"
                  "./lib/libshare/os/linux/nfs.c"
                  "./lib/libshare/smb.h"
                  "echo 'Supported Kernel versions:'"
                ]
                [
                  "7\\.2"
                  "./lib/libzfs/os/linux/libzfs_share_nfs.c"
                  "./lib/libzfs/libzfs_share.h"
                  ''
                    sed -i -E 's/^Linux-Maximum:.*/Linux-Maximum: 7.2/' META
                    echo 'Supported Kernel versions:'
                  ''
                ]
                pp;
            zfsOverride = old: {
              version = "2.4.99";
              src = inputs.openzfs;
              postPatch = fixPostPatch old.postPatch;
              meta = old.meta // { broken = false; };
              passthru =
                old.passthru
                // {
                  userspaceTools = old.passthru.userspaceTools.overrideAttrs (uOld: {
                    version = "2.4.99";
                    src = inputs.openzfs;
                    postPatch = fixPostPatch uOld.postPatch;
                    meta = uOld.meta // { broken = false; };
                  });
                };
            };
            extendLp = ps:
              ps.extend (lpF: lpP: {
                zfs_unstable = lpP.zfs_unstable.overrideAttrs zfsOverride;
              });
          in
          {
            zfs_unstable = prev.zfs_unstable.overrideAttrs zfsOverride;
            linuxPackages_latest = extendLp prev.linuxPackages_latest;
            linuxKernel =
              prev.linuxKernel
              // {
                packages = builtins.mapAttrs (n: extendLp) prev.linuxKernel.packages;
              };
          })
        # EVDI (DisplayLink) kernel module from upstream source
        (final: prev:
          let
            evdiOverride = old: {
              src = inputs.evdi-src;
              version = inputs.evdi-src.shortRev or "unstable";
              patches = [ ];
            };
            extendLpEvdi = ps:
              ps.extend (lpF: lpP: {
                evdi = lpP.evdi.overrideAttrs evdiOverride;
              });
          in
          {
            linuxKernel =
              prev.linuxKernel
              // {
                packages = builtins.mapAttrs (n: extendLpEvdi) prev.linuxKernel.packages;
              };
          })
        # nixpkgs uses requireFile for the proprietary DisplayLink archive,
        # which breaks fresh/remote builds unless the zip was manually
        # seeded into the store. Fetch the same release directly instead.
        (final: prev: {
          displaylink = prev.displaylink.overrideAttrs (_: {
            src = final.fetchurl {
              name = "displaylink-620.zip";
              url = "https://www.synaptics.com/sites/default/files/exe_files/2025-09/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.2-EXE.zip";
              hash = "sha256-JQO7eEz4pdoPkhcn9tIuy5R4KyfsCniuw6eXw/rLaYE=";
            };
          });
        })
        # NanoKVM userspace (nanokvm-server, nanokvm-web). Also defines
        # sg2002-* board-support packages, but those only evaluate when
        # accessed — on aarch64 only nanokvm-* is reached.
        inputs.nanokvm.overlays.default
        # Disable nix's own test suite on aarch64. trex (x86_64) runs
        # aarch64 binaries via binfmt-qemu, which doesn't preserve real
        # signal semantics — WriteFull.RespectsAllowInterrupts fails
        # (1/689 tests). cache.nixos.org's CI runs these on real aarch64
        # hardware so we trust upstream coverage.
        (final: prev:
          prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system == "aarch64-linux") {
            nix = prev.nix.overrideAttrs (_: { doCheck = false; });
          })
      ];

      ryzenadjDragonRangeOverlay = final: prev: {
        ryzenadj = prev.ryzenadj.overrideAttrs (old: {
          version = "0.19.0-dragon-range-a4a44eb";
          src = final.fetchFromGitHub {
            owner = "inode64";
            repo = "RyzenAdj";
            rev = "a4a44ebeb4d88f4dc22550bdf910737a5f1dc794";
            hash = "sha256-uLnF+VNmQLQ0OFpWNKWLMKXNM9UB6eF9QEtbcSz1aVA=";
          };
          cmakeFlags = (old.cmakeFlags or [ ]) ++ [
            "-DENABLE_IPO=OFF"
          ];
          patches = (old.patches or [ ]) ++ [
            ./profiles/patches/ryzenadj-strix-halo-gfx-telemetry.patch
            ./profiles/patches/ryzenadj-strix-halo-stapm-time.patch
          ];
          meta = (old.meta or { }) // {
            homepage = "https://github.com/inode64/RyzenAdj/tree/feature/Dragon-Range";
          };
        });
      };

      # Base config shared across all pkgs instantiations
      baseConfig = {
        allowUnfree = true;
        allowBroken = true;
        # permittedInsecurePackages = [
        #   "qtwebengine-5.15.19"
        # ];
      };

      # Base pkgs - no GPU acceleration
      # Nix does not memoize function application: a bare
      # `system: import nixpkgs { ... }` re-instantiates nixpkgs for every
      # machine that calls it. genAttrs is lazy, so each variant/system pair
      # is imported at most once and shared by all consumers (machine
      # builders, packages, devShells, colmena meta).
      memoizePerSystem =
        mk:
        let
          instances = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] mk;
        in
        system: instances.${system};

      pkgsFor = memoizePerSystem (system:
        import nixpkgs {
          inherit system;
          overlays = allOverlays;
          config = baseConfig;
        });

      # CUDA-enabled pkgs for NVIDIA machines
      pkgsForCuda = memoizePerSystem (system:
        import nixpkgs {
          inherit system;
          overlays = allOverlays;
          config =
            baseConfig
            // {
              cudaSupport = true;
              cudaCapabilities = [ "8.9" ];
            };
        });

      # ROCm-enabled pkgs for AMD GPU machines
      pkgsForRocm = memoizePerSystem (system:
        import nixpkgs {
          inherit system;
          overlays = allOverlays;
          config = baseConfig // { rocmSupport = true; };
        });

      pkgsForRocmStrixHalo = memoizePerSystem (system:
        import nixpkgs {
          inherit system;
          overlays = allOverlays ++ [ ryzenadjDragonRangeOverlay ];
          config = baseConfig // { rocmSupport = true; };
        });

      # ROCm-enabled pkgs, rebuilt with `-march=znver5 -mtune=znver5`
      # for Strix Halo (Zen 5). Every C/C++ derivation in the closure
      # is auto-tagged `requiredSystemFeatures = ["gccarch-znver5"]`,
      # so distributed builds only land on builders advertising the
      # matching cascade: strix-1, strix-2, and fuckup. The `gccarch-*`
      # store-path divergence also keeps these binaries from being
      # accidentally substituted onto a weaker CPU.
      pkgsForRocmZnver5 = memoizePerSystem (_system:
        import nixpkgs {
          localSystem = {
            config = "x86_64-unknown-linux-gnu";
            gcc = {
              arch = "znver5";
              tune = "znver5";
            };
          };
          overlays = allOverlays;
          config = baseConfig // { rocmSupport = true; };
        });

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

      moduleAttrs =
        nixpkgs.lib.mapAttrs'
          (name: type: {
            name = nixpkgs.lib.removeSuffix ".nix" name;
            value = import (./modules + "/${name}");
          })
          (builtins.readDir ./modules);

      # ——— interdependent outputs, let-bound so the output set below needs
      # neither `rec` nor self.outputs backreferences ———

      # Define mkSecret once and pass it to both machines and colmena
      secretsRegistry = import ./secrets/default.nix;
      mkSecret = name: overrides:
        secretsRegistry.${name} // overrides;

      # Single source of truth for network topology (hosts, vlans, IPs, helpers).
      # Threaded via specialArgs into NixOS/darwin configs and imported directly by
      # the standalone esphome generator.
      network = import ./network.nix nixpkgs.lib;

      nixosModules = builtins.removeAttrs moduleAttrs [ "xmrig-darwin" ];

      nixosModule = {
        imports =
          builtins.attrValues nixosModules
          ++ [
            inputs.impermanence.nixosModules.impermanence
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
            ./profiles/sops.nix
          ];
      };

      nixosConfigurations =
        import ./machines
          nixosModule
          inputs
          mkSecret
          network
          { inherit pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmStrixHalo pkgsForRocmZnver5 allOverlays; };

      # Image artifacts (ISOs, SD cards, USB sticks) that evaluate as full
      # NixOS systems but are never colmena deployment targets.
      imageOnlyNixosConfigurations = [
        "router-usb"
        "strix-installer"
        "strix-2-nvme-image"
        "k3SdImage"
      ];
      deployableNixosConfigurations =
        builtins.removeAttrs nixosConfigurations imageOnlyNixosConfigurations;

      colmena =
        {
          meta = {
            description = "My personal machines";
            nixpkgs = pkgsFor "x86_64-linux";
            # NOTE: do not be tempted to derive this as
            #   mapAttrs (_: v: v.pkgs) deployableNixosConfigurations
            # — nixosSystem's result.pkgs is NOT the pkgs passed in. The
            # nixpkgs module does `cfg.pkgs.appendOverlays cfg.overlays`
            # (nixos/modules/misc/nixpkgs.nix), so any module-contributed
            # nixpkgs.overlays (e.g. nix-strix-halo's) is already baked into
            # result.pkgs. Handing that back to colmena re-appends the same
            # overlay a second time when the node's modules re-evaluate,
            # double-applying its overrides and drifting every derivation the
            # overlay touches away from the standalone configuration.
            nodeNixpkgs = {
              fuckup = pkgsForCuda "x86_64-linux";
              strix-1 = pkgsForRocmStrixHalo "x86_64-linux";
              strix-2 = pkgsForRocmStrixHalo "x86_64-linux";
              strix-3 = pkgsForRocmStrixHalo "x86_64-linux";
              strix-4 = pkgsForRocmStrixHalo "x86_64-linux";
              # trex uses Vulkan/RADV for llama.cpp on Navi 10. Keep it on the
              # base package set so Open WebUI/Torch and routine system rebuilds
              # do not pull the ROCm package set unless a package asks for it.
              trex = pkgsFor "x86_64-linux";
            };
            specialArgs = {
              inherit inputs mkSecret pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmStrixHalo pkgsForRocmZnver5 network;
            };
          };
        }
        # Colmena re-instantiates every node from `_module.args.modules`
        # with the hive's specialArgs. All node module lists — including
        # the nanokvm board stack, whose flake-level args ride inside the
        # list as `_module.args` — are self-contained, so this is
        # lossless and each hive node matches its standalone
        # nixosConfiguration.
        // builtins.mapAttrs
          (name: value: {
            nixpkgs.system = value.config.nixpkgs.system;
            imports = value._module.args.modules;
          })
          deployableNixosConfigurations;
    in
    {
      inherit
        secretsRegistry
        mkSecret
        network
        nixosModules
        nixosModule
        nixosConfigurations
        imageOnlyNixosConfigurations
        deployableNixosConfigurations
        colmena;

      # expose local packages (using shared pkgsFor)
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        (import ./packages pkgs)
        // {
          # Keep `nix run .#colmena` on the same Colmena input that provides
          # `colmenaHive`; nixpkgs currently carries an older 0.4 CLI.
          colmena = inputs.colmena.packages.${system}.colmena;
          disko = inputs.disko.packages.${system}.disko;
          disko-install = inputs.disko.packages.${system}.disko-install;
        }
        # OpenWrt "machines" (mips_24kc / ath79). ImageBuilder is x86-only.
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
          openwrt-unifiac-pro = import ./machines/openwrt-mips/unifi-ac-pro {
            inherit pkgs;
            openwrt-imagebuilder = inputs.openwrt-imagebuilder;
          };
          openwrt-10g-onti = import ./machines/openwrt-mips/xikestor-sks8300-8x {
            inherit pkgs;
            openwrt-imagebuilder = inputs.openwrt-imagebuilder;
          };
        });

      diskoConfigurations = {
        trex-boot-ssds = import ./machines/x86/trex/root-btrfs.disko.nix;
      };

      colmenaHive = inputs.colmena.lib.makeHive colmena;

      darwinConfigurations."air" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs localOverlays mkSecret network; };
        modules = [
          ./machines/darwin-aarch64/air.nix
          inputs.sops-nix.darwinModules.sops
        ];
      };

      darwinConfigurations."mbp" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs localOverlays mkSecret network; };
        modules = [
          ./machines/darwin-aarch64/mbp.nix
          inputs.sops-nix.darwinModules.sops
        ];
      };

      darwinConfigurations."goblin" = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = { inherit inputs localOverlays mkSecret network; };
        modules = [
          ./machines/darwin-aarch64/goblin.nix
          inputs.sops-nix.darwinModules.sops
        ];
      };


      darwinModules = {
        xmrig-darwin = moduleAttrs.xmrig-darwin;
      };

      devShells = forAllSystems (system: {
        default =
          let
            pkgs = pkgsFor system;
            esphomePkgs = import inputs.nixpkgs-esphome {
              inherit system;
              config = baseConfig;
            };
            load-mcp-tokens = pkgs.writeShellScriptBin "load-mcp-tokens" ''
              # Outputs export statements - use with: eval "$(load-mcp-tokens)"
              if ! command -v pass &>/dev/null; then
                echo "echo 'pass not found'" >&2
                exit 1
              fi
              if pass show hass/mcp-token &>/dev/null 2>&1; then
                echo "export HASS_TOKEN='$(pass show hass/mcp-token)'"
                echo "echo 'Loaded HASS_TOKEN'" >&2
              fi
              if pass show ${network.publicFqdn "grafana"}/service-account-token &>/dev/null 2>&1; then
                echo "export GRAFANA_TOKEN='$(pass show ${network.publicFqdn "grafana"}/service-account-token)'"
                echo "echo 'Loaded GRAFANA_TOKEN'" >&2
              fi
            '';
          in
          pkgs.mkShell {
            packages = [
              inputs.colmena.packages.${system}.colmena
              pkgs.sops
              pkgs.ssh-to-age
              pkgs.uv
              pkgs.mcp-grafana
              esphomePkgs.esphome
              load-mcp-tokens
            ];
            shellHook = ''
              echo "Run 'eval \"\$(load-mcp-tokens)\"' to load MCP tokens from pass"
              unset PYTHONPATH
            '';
          };

        playwright =
          let
            pkgs = pkgsFor system;
          in
          pkgs.mkShell {
            packages = [ pkgs.chromium pkgs.nodejs ];
            shellHook = ''
              export PLAYWRIGHT_CHROMIUM_PATH=${pkgs.chromium}/bin/chromium
              echo "playwright devshell — chromium at $PLAYWRIGHT_CHROMIUM_PATH"
            '';
          };
      });

      checks = {
        x86_64-linux =
          let
            pkgs = pkgsFor "x86_64-linux";
          in
          {
            mtail-xmrig = pkgs.testers.runNixOSTest (import ./tests/mtail-xmrig.nix { inherit pkgs; });
            beegfs = pkgs.testers.runNixOSTest (import ./tests/beegfs.nix { inherit pkgs; });
          };
      };

      # # The Strix fleet normally netboots, but every node also carries a
      # # complete local fallback installation. These configurations reuse the
      # # production host modules while changing only that host's boot mode;
      # # they are install artifacts, not additional Colmena deployment nodes.
      # localBootNixosConfigurations =
      #   nixpkgs.lib.genAttrs
      #     [ "strix-1" "strix-2" "strix-3" "strix-4" ]
      #     (hostName:
      #       let
      #         localBootNetwork = network // {
      #           hosts = network.hosts // {
      #             ${hostName} = network.hosts.${hostName} // {
      #               netboot = false;
      #             };
      #           };
      #         };
      #       in
      #       nixosConfigurations.${hostName}.extendModules {
      #         specialArgs.network = localBootNetwork;
      #       });

      githubActions =
        let
          mkGithubMatrix = nixConf: {
            matrix = {
              include =
                builtins.map
                  (x: {
                    attr = "nixosConfigurations.${x}.config.system.build.toplevel";
                    os = [ "ubuntu-22.04" ];
                  })
                  (builtins.attrNames nixConf);
            };
          };
        in
        mkGithubMatrix deployableNixosConfigurations;
    };
}
