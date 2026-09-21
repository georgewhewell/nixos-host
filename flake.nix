{
  description = "satanic.link fleet: NixOS (x86/aarch64/riscv), nix-darwin, OpenWrt and RouterOS configs, deployed with colmena";

  inputs = {
    # The fleet owns its base system pin. Consume nix-strix-halo's selected
    # packages and modules without inheriting its development nixpkgs pin.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keep the historical application input name, using the fleet package set.
    nixpkgs-esphome.follows = "nixpkgs";

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
    # nixpkgs 26.11 no longer supports.
    vscode-server.url = "github:nix-community/nixos-vscode-server";

    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    #    nix-ai-tools.inputs.nixpkgs.follows = "nixpkgs";

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

    # Maintained local fork: staged existing-device imports plus the CRS bridge,
    # physical Ethernet, VLAN-table, and switch-chip resources we need.
    nix-routeros = {
      url = "git+file:///mnt/Home/src/nix-routeros?ref=crs812-adoption&rev=d549aa410d053a7bd7e5c1aa95fa3ad13b9e26eb&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-strix-halo = {
      # Keep ignored benchmark artifacts out of the flake source. A raw path
      # input hashed the multi-gigabyte .bench-artifacts tree and invalidated
      # every fleet evaluation whenever a run appended a log.
      url = "git+file:///mnt/Home/src/nix-strix-halo?shallow=1";
      inputs.thunderbolt-ibverbs.follows = "thunderbolt-ibverbs-kernel";
    };

    nix-strix-halo-multikernel = {
      # Keep the experimental host kernel and management module isolated from
      # the fleet's production Halo overlay. This branch can advance without
      # pulling unrelated NPU/ROCm package changes onto the strix-4 canary.
      # Same reviewed tree with the stdenv.hostPlatform API migration.
      url = "git+file:///mnt/Home/src/nix-strix-halo?ref=ci/multikernel-platform-predicates&rev=4a19717e771150820e4b3995bcf527da34ec8e1b&shallow=1";
      flake = false;
    };

    mklinux-multikernel = {
      # Exact local checkout used by the multikernel canary. Keeping the
      # kernel as a raw input makes source iteration explicit and lockable.
      url = "git+file:///mnt/Home/src/mklinux-7.0-mk2?ref=refs/tags/v7.0-mk2&rev=3bdd35b64413da0b4e089ce931bfc2e8b031cbf7&shallow=1";
      flake = false;
    };

    nix-strix-halo-qwen38 = {
      # Qwen3.8-27B serving stack for the four V620s on strix-2: the reviewed
      # feat/qwen38-v620-roofline branch carries the gfx1030 sglang patch set
      # (Triton GEMV, radix extra_buffer on ROCm, prefill retiles). Pinned as
      # its own input -- like nix-strix-halo-ds4 -- so each serving campaign
      # is independently upgradable and revertable. Deliberately NO follows
      # overrides: the branch's own lock produced the closure that was
      # perf/parity-validated on the hardware, and redirecting its inputs
      # would silently rebuild a different one.
      url = "git+file:///mnt/Home/src/nix-strix-halo?ref=feat/qwen38-v620-roofline&shallow=1";
    };

    nix-strix-halo-ds4 = {
      # Reviewed DS4 production server and OpenCode client. Keep this separate
      # from both the fleet host modules and the V620/Qwen serving input.
      url = "git+file:///mnt/Home/src/nix-strix-halo?ref=prod/ds4-agent&rev=8e6cc4f0f03088d22743d9e1a3db841e067971d9&shallow=1";
      inputs.nixpkgs.follows = "nix-strix-halo/nixpkgs";
      inputs.thunderbolt-ibverbs.follows = "thunderbolt-ibverbs-kernel";
    };

    atlas = {
      # Consume pexctl from Atlas' durable merged repository.
      url = "git+file:///mnt/Home/src/atlas-work?ref=master&dir=packages/pexctl&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hellas-ai-video = {
      # Media-model runners are part of the diskless Strix closures. Pin the
      # reviewed deployment ref so ignored renders, model data, local secrets,
      # and the mutable git index never enter the flake source hash.
      url = "git+file:///mnt/Home/src/hellas-ai-video?ref=codex/h3-deploy&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-strix-halo.follows = "nix-strix-halo";
      # Deliberately NOT redirected to thunderbolt-ibverbs-kernel the way
      # nix-strix-halo is above: this input needs the codex/apple-xdomain
      # branch, which is the only one exporting overlays.rdma-core-usb4
      # (nix/pkgs.nix:37 consumes it). The gda-v2-rebase tree builds that
      # package but does not expose the overlay, so following it fails.
    };

    thunderbolt-ibverbs-kernel = {
      url = "git+file:///mnt/Home/src/thunderbolt-ibverbs-gda-v2-rebase?ref=codex/gda-v2-rebased-port&rev=93cfff16b7be025bbf993d761406c3b1fb8122c6&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.linux-src.follows = "linux-src";
    };

    # NOTE: this flake pins its own nixpkgs fork (vitis-ai branch) because
    # xrt / xrt-plugin-amdxdna / xrt-amdxdna live there; do not add
    # `inputs.nixpkgs.follows = "nixpkgs"`.
    nix-amd-npu.url = "github:robcohen/nix-amd-npu";

    # Temporary local Catena inputs while its runner API is developed in
    # tandem with Hellas. Pin reviewed commits so fleet evaluation never
    # captures either worktree's build products or other untracked files.
    catena-runner = {
      url = "git+file:///mnt/Home/src/catena-runner?ref=grw/hellas-interface&rev=407b3162e36703ffeb6a9789dccf4014bd735358&shallow=1";
      flake = false;
    };

    exploratory-catena = {
      url = "git+file:///mnt/Home/src/exploratory-catena?ref=grw/hellas-runner-hygiene-v2&rev=ac58d7ee4325c8e59da7cbf4b0e8173e5d7b22bc&shallow=1";
      flake = false;
    };

    hellas = {
      # Provider revisions are carried by the served Strix boot images. Keep
      # this pin independent of gateway-only client changes so deploying trex
      # does not rebuild every image.
      url = "git+file:///mnt/Home/src/hellas-strix-paid-gateway?ref=codex/strix-paid-gateway&rev=b0bb7940734d90fd90af9b1e7de6468148c430d3&shallow=1";
    };

    hellas-gateway = {
      # The gateway is deployed independently of the netboot providers.
      url = "git+file:///mnt/Home/src/hellas-strix-paid-gateway?ref=codex/strix-paid-gateway&rev=6e1f3bc269afd8a9e166758a95237d41986d9909&shallow=1";
      inputs.nixpkgs.follows = "hellas/nixpkgs";
      inputs.rust-overlay.follows = "hellas/rust-overlay";
      inputs.nix-strix-halo.follows = "hellas/nix-strix-halo";
    };

    nanokvm = {
      # Keep .git, ignored captures, and local Wi-Fi credentials out of the
      # flake source. Keep NanoKVM's tested nixpkgs pin as well: following the
      # Strix pin invalidates the cached RISC-V cross closure and rebuilds the
      # toolchain without changing the host integration contract.
      url = "git+file:///mnt/Home/src/nixos-nanokvm?ref=master&shallow=1";
      inputs.disko.follows = "disko";
      inputs.impermanence.follows = "impermanence";
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

    # Unified overlay list - applied consistently across all outputs
    allOverlays = [
      (composeManyExtensions localOverlays)
      (import (inputs.nix-strix-halo-multikernel + "/overlays/multikernel.nix"))
      (
        final: prev: let
          linux-multikernel = prev.linux-multikernel.override {
            source = inputs.mklinux-multikernel;
          };
        in {
          inherit linux-multikernel;
          linuxPackages_multikernel = final.linuxPackagesFor linux-multikernel;
        }
      )
      # These media applications use the fleet's unstable package set through
      # the historical input alias; Qui requires its Go 1.27 toolchain.
      (final: _prev: let
        leafPkgs = inputs.nixpkgs-esphome.legacyPackages.${final.stdenv.hostPlatform.system};
      in {
        qbittorrent-nox = leafPkgs.qbittorrent-nox;
        qui = leafPkgs.callPackage ./packages/qui {};
      })
      (final: _prev: {
        pexctl = inputs.atlas.packages.${final.stdenv.hostPlatform.system}.pexctl;
      })
      inputs.rust-overlay.overlays.default
      # The pinned Hellas overlay still uses the deprecated final.system.
      (final: _prev: {
        hellas = inputs.hellas.packages.${final.stdenv.hostPlatform.system};
        hellasLib = import (inputs.hellas + "/nix/lib") {
          pkgs = final;
          inherit (inputs.hellas.inputs) nix-strix-halo;
        };
      })
      # Experimental NVIDIA DOCA-OFED packages. Keep the overlay before the
      # custom kernel definitions so its packagesFor extension also applies
      # to linux_7_2_rc2; hosts opt in to the modules separately.
      inputs.mlnx-ofed-nixos.overlays.default
      (final: prev: {
        firefox-addons = final.callPackage "${inputs.firefox-addons}" {
          buildMozillaXpiAddon =
            (import "${inputs.firefox-addons}/../../lib/mozilla.nix" {lib = final.lib;}).mkBuildMozillaXpiAddon {inherit (final) stdenv fetchurl;};
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
                linux_7_2_rc2 = (prev.linuxKernel.packagesFor final.linux_7_2_rc2).extend (lpFinal: lpPrev: {
                  ryzen-smu = lpPrev.ryzen-smu.overrideAttrs (old: {
                    patches =
                      (old.patches or [])
                      ++ [
                        ./profiles/patches/ryzen-smu-linux-7.2-cpuid-header.patch
                      ];
                  });
                });
              };
          };
      })
      # OpenZFS master, including Linux 7.2 support. Keep nixpkgs' kernel
      # compatibility checks: the updated snapshot declares 7.2 support in
      # META itself. Adapt the renamed libshare paths and remove the obsolete
      # helper-path rewrite: snapshot mounts now happen inside the kernel.
      (final: prev: let
        zfsVersion = "2.4.99";
        fixPostPatch = pp:
          builtins.replaceStrings
          [
            ''
              substituteInPlace ./module/os/linux/zfs/zfs_ctldir.c \
                --replace-fail '"/usr/bin/env", "umount"' '"${prev.util-linux}/bin/umount", "-n"' \
                --replace-fail '"/usr/bin/env", "mount"'  '"${prev.util-linux}/bin/mount", "-n"'
            ''
            "./lib/libshare/os/linux/nfs.c"
            "./lib/libshare/smb.h"
          ]
          [
            ""
            "./lib/libzfs/os/linux/libzfs_share_nfs.c"
            "./lib/libzfs/libzfs_share.h"
          ]
          pp;
        zfsSourceOverride = old: {
          version = zfsVersion;
          name = builtins.replaceStrings [old.version] [zfsVersion] old.name;
          src = inputs.openzfs;
          postPatch = fixPostPatch old.postPatch;
        };
        zfsOverride = old: zfsSourceOverride old // {
          passthru =
            old.passthru
            // {
              userspaceTools = old.passthru.userspaceTools.overrideAttrs zfsSourceOverride;
            };
        };
        extendLp = ps:
          ps.extend (lpF: lpP: {
            zfs_unstable = lpP.zfs_unstable.overrideAttrs zfsOverride;
          });
      in {
        zfs_unstable = prev.zfs_unstable.overrideAttrs zfsOverride;
        linuxPackages_latest = extendLp prev.linuxPackages_latest;
        linuxKernel =
          prev.linuxKernel
          // {
            packages = builtins.mapAttrs (n: extendLp) prev.linuxKernel.packages;
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
          nix = prev.nix.overrideAttrs (_: {doCheck = false;});
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
        cmakeFlags =
          (old.cmakeFlags or [])
          ++ [
            "-DENABLE_IPO=OFF"
          ];
        patches =
          (old.patches or [])
          ++ [
            ./profiles/patches/ryzenadj-strix-halo-gfx-telemetry.patch
            ./profiles/patches/ryzenadj-strix-halo-stapm-time.patch
          ];
        meta =
          (old.meta or {})
          // {
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
    memoizePerSystem = mk: let
      instances = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"] mk;
    in
      system: instances.${system};

    pkgsFor = memoizePerSystem (system:
      import nixpkgs {
        inherit system;
        overlays = allOverlays;
        config = baseConfig;
      });

    # Colmena needs the same raw cross package set that the self-contained
    # NanoKVM board gets from its own tested nixpkgs input. The board module
    # applies its SG2002 overlay and unfree policy during module evaluation.
    pkgsForNanokvm = import inputs.nanokvm.inputs.nixpkgs {
      localSystem = "x86_64-linux";
      crossSystem = "riscv64-linux";
    };

    # CUDA-enabled pkgs for NVIDIA machines
    pkgsForCuda = memoizePerSystem (system:
      import nixpkgs {
        inherit system;
        overlays = allOverlays;
        config =
          baseConfig
          // {
            cudaSupport = true;
            cudaCapabilities = ["8.9"];
          };
      });

    # ROCm-enabled pkgs for AMD GPU machines
    pkgsForRocm = memoizePerSystem (system:
      import nixpkgs {
        inherit system;
        overlays = allOverlays;
        config = baseConfig // {rocmSupport = true;};
      });

    pkgsForRocmStrixHalo = memoizePerSystem (system:
      import nixpkgs {
        inherit system;
        overlays = allOverlays ++ [ryzenadjDragonRangeOverlay];
        config = baseConfig // {rocmSupport = true;};
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
        config = baseConfig // {rocmSupport = true;};
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

    # Darwin-only modules must be excluded here: everything left in
    # moduleAttrs is imported into *every* NixOS host via nixosModule below,
    # and a module that defines `launchd.*` fails evaluation on Linux where
    # that option does not exist. An `stdenv.hostPlatform.isDarwin` guard inside mkIf does
    # not help — mkIf defers the value, not the option path. Darwin hosts pick
    # these up by explicit path import instead (see darwin-configuration.nix
    # for xmrig-darwin, mbp.nix for llama-server-darwin).
    nixosModules = builtins.removeAttrs moduleAttrs [
      "xmrig-darwin"
      "llama-server-darwin"
    ];

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

    # The NanoKVM board module is deliberately self-contained: it brings
    # the disko and impermanence option providers needed by its SD image.
    # Keep the rest of the fleet module stack, but do not import those two
    # providers a second time when Colmena reconstructs the node.
    nixosModuleNanokvm = {
      imports =
        builtins.attrValues nixosModules
        ++ [
          inputs.sops-nix.nixosModules.sops
          ./profiles/sops.nix
        ];
    };

    nixosConfigurations =
      import ./machines
      nixosModule
      nixosModuleNanokvm
      inputs
      mkSecret
      network
      {inherit pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmStrixHalo pkgsForRocmZnver5 allOverlays;};

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
            nanokvm = pkgsForNanokvm;
            licheerv = pkgsForNanokvm;
            claw = pkgsForNanokvm;
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
  in {
    inherit
      secretsRegistry
      mkSecret
      network
      nixosModules
      nixosModule
      nixosModuleNanokvm
      nixosConfigurations
      imageOnlyNixosConfigurations
      deployableNixosConfigurations
      colmena
      ;

    # expose local packages (using shared pkgsFor)
    packages = forAllSystems (system: let
      pkgs = pkgsFor system;
    in
      (import ./packages pkgs)
      // {
        # Public Atlas input is the sole maintained pexctl source.
        pexctl = inputs.atlas.packages.${system}.pexctl;
        # Keep `nix run .#colmena` on the same Colmena input that provides
        # `colmenaHive`; nixpkgs currently carries an older 0.4 CLI.
        colmena = inputs.colmena.packages.${system}.colmena;
        disko = inputs.disko.packages.${system}.disko;
        disko-install = inputs.disko.packages.${system}.disko-install;
      }
      # OpenWrt "machines" (mips_24kc / ath79). ImageBuilder is x86-only.
      // pkgs.lib.optionalAttrs (system == "x86_64-linux") (
        let
          crs812Routeros = import ./machines/routeros/crs812/terranix.nix {
            inherit inputs pkgs system network;
          };
        in {
          openwrt-unifiac-pro = import ./machines/openwrt-mips/unifi-ac-pro {
            inherit pkgs;
            openwrt-imagebuilder = inputs.openwrt-imagebuilder;
          };
          openwrt-10g-onti = import ./machines/openwrt-mips/xikestor-sks8300-8x {
            inherit pkgs;
            openwrt-imagebuilder = inputs.openwrt-imagebuilder;
          };
          # Deliberately expose only read-only rendering and planning during
          # existing-state adoption. Applying comes after import/plan review.
          crs812-routeros-show = crs812Routeros;
          crs812-routeros-plan = crs812Routeros.plan;
          # Complete desired bridge/VLAN/Ethernet JSON with ownership gates
          # lifted only inside this renderer.  No apply output is exposed.
          crs812-routeros-staged-show = crs812Routeros.staged;
          # Exact current live shape for zero-change ownership import.
          crs812-routeros-ownership-show = crs812Routeros.ownership;
          crs812-routeros-ownership-plan = crs812Routeros.ownership.plan;
          # Phase-one gateway handoff: legacy untagged inside plus tagged
          # WAN/WiFi. The plan is exposed for attended pre-staging only.
          crs812-routeros-transition-show = crs812Routeros.transition;
          crs812-routeros-transition-plan = crs812Routeros.transition.plan;
          # Exact cable-move state.  Still show-only: applying the filtering
          # boundary requires the attended cutover and rollback guard.
          crs812-routeros-cutover-show = crs812Routeros.cutover;
          crs812-routeros-cutover-plan = crs812Routeros.cutover.plan;
          crs812-routeros-rollback-show = crs812Routeros.rollback;
          crs812-routeros-rollback-plan = crs812Routeros.rollback.plan;
        }
      ));

    diskoConfigurations = {
      trex-boot-ssds = import ./machines/x86/trex/root-btrfs.disko.nix;
    };

    colmenaHive = inputs.colmena.lib.makeHive colmena;

    darwinConfigurations."air" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {inherit inputs localOverlays mkSecret network;};
      modules = [
        ./machines/darwin-aarch64/air.nix
        inputs.sops-nix.darwinModules.sops
      ];
    };

    darwinConfigurations."mbp" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {inherit inputs localOverlays mkSecret network;};
      modules = [
        ./machines/darwin-aarch64/mbp.nix
        inputs.sops-nix.darwinModules.sops
      ];
    };

    darwinConfigurations."goblin" = darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {inherit inputs localOverlays mkSecret network;};
      modules = [
        ./machines/darwin-aarch64/goblin.nix
        inputs.sops-nix.darwinModules.sops
      ];
    };

    darwinModules = {
      xmrig-darwin = moduleAttrs.xmrig-darwin;
      llama-server-darwin = moduleAttrs.llama-server-darwin;
    };

    devShells = forAllSystems (system: {
      default = let
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

      playwright = let
        pkgs = pkgsFor system;
      in
        pkgs.mkShell {
          packages = [pkgs.chromium pkgs.nodejs];
          shellHook = ''
            export PLAYWRIGHT_CHROMIUM_PATH=${pkgs.chromium}/bin/chromium
            echo "playwright devshell — chromium at $PLAYWRIGHT_CHROMIUM_PATH"
          '';
        };
    });

    checks = {
      x86_64-linux = let
        pkgs = pkgsFor "x86_64-linux";
      in {
        mtail-xmrig = pkgs.testers.runNixOSTest (import ./tests/mtail-xmrig.nix {inherit pkgs;});
        beegfs = pkgs.testers.runNixOSTest (import ./tests/beegfs.nix {inherit pkgs;});
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
      mkGithubMatrix deployableNixosConfigurations;
  };
}
