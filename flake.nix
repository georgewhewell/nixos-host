{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";
    impermanence.inputs.nixpkgs.follows = "nixpkgs";
    impermanence.inputs.home-manager.follows = "home-manager";

    ethereum.url = "github:nix-community/ethereum.nix/8f01580481e88e169b7ada56f1500dccd6cefe61";

    nix-bitcoin.url = "github:fort-nix/nix-bitcoin/release";
    nix-bitcoin.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:lnl7/nix-darwin/master";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    vscode-server.url = "github:nix-community/nixos-vscode-server";
    vscode-server.inputs.nixpkgs.follows = "nixpkgs";

    nix-ai-tools.url = "github:numtide/nix-ai-tools";

    mac-app-util.url = "github:hraban/mac-app-util";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-strix-halo = {
      url = "github:hellas-ai/nix-strix-halo";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.thunderbolt-ibverbs.follows = "thunderbolt-ibverbs-kernel";
    };

    thunderbolt-ibverbs-kernel = {
      url = "path:/mnt/Home/src/thunderbolt-ibverbs-gda-iommu-revive";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NOTE: this flake pins its own nixpkgs fork (vitis-ai branch) because
    # xrt / xrt-plugin-amdxdna / xrt-amdxdna live there; do not add
    # `inputs.nixpkgs.follows = "nixpkgs"`.
    nix-amd-npu.url = "github:robcohen/nix-amd-npu";

    hellas = {
      # Local deploy input while Codex Fetch support is ahead of the remote branch.
      url = "git+file:///mnt/Home/src/node?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nanokvm = {
      url = "git+ssh://trex/home/grw/src/nixos-nanokvm.git";
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

    # Collabora RK3588 hardware enablement kernel (rockchip-devel branch)
    linux-rockchip-src = {
      url = "git+https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux.git?ref=rockchip-devel&shallow=1";
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

    rust-overlay.url = "github:oxalica/rust-overlay";

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
        (final: prev: {
          firefox-addons = final.callPackage "${inputs.firefox-addons}" {
            buildMozillaXpiAddon =
              (import "${inputs.firefox-addons}/../../lib/mozilla.nix" { lib = final.lib; }).mkBuildMozillaXpiAddon { inherit (final) stdenv fetchurl; };
          };
          # Pull antigravity (Google's gemini-cli replacement) from nix-ai-tools
          # so it's available as a top-level pkg attribute.
          antigravity = inputs.nix-ai-tools.packages.${final.stdenv.hostPlatform.system}.antigravity;
        })
        # Collabora RK3588 hardware enablement kernel
        (final: prev: {
          linux-rockchip = prev.callPackage ./packages/linux-rockchip {
            src = inputs.linux-rockchip-src;
          };
          linuxPackages_rockchip = prev.linuxKernel.packagesFor final.linux-rockchip;
        })
        # OpenZFS 2.4.99 for kernel 7.0 support (remove when nixpkgs zfs_unstable >= 2.5)
        (final: prev:
          let
            fixPostPatch = pp:
              builtins.replaceStrings
                [ "6\\.19" "./lib/libshare/os/linux/nfs.c" "./lib/libshare/smb.h" ]
                [ "7\\.0" "./lib/libzfs/os/linux/libzfs_share_nfs.c" "./lib/libzfs/libzfs_share.h" ]
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

      # Base config shared across all pkgs instantiations
      baseConfig = {
        allowUnfree = true;
        allowBroken = true;
        # permittedInsecurePackages = [
        #   "qtwebengine-5.15.19"
        # ];
      };

      # Base pkgs - no GPU acceleration
      pkgsFor = system:
        import nixpkgs {
          inherit system;
          overlays = allOverlays;
          config = baseConfig;
        };

      # CUDA-enabled pkgs for NVIDIA machines
      pkgsForCuda = system:
        import nixpkgs {
          inherit system;
          overlays = allOverlays;
          config =
            baseConfig
            // {
              cudaSupport = true;
              cudaCapabilities = [ "8.9" ];
            };
        };

      # ROCm-enabled pkgs for AMD GPU machines
      pkgsForRocm = system:
        import nixpkgs {
          inherit system;
          overlays = allOverlays;
          config = baseConfig // { rocmSupport = true; };
        };

      # ROCm-enabled pkgs, rebuilt with `-march=znver5 -mtune=znver5`
      # for Strix Halo (Zen 5). Every C/C++ derivation in the closure
      # is auto-tagged `requiredSystemFeatures = ["gccarch-znver5"]`,
      # so distributed builds only land on builders advertising the
      # matching cascade: strix-1, strix-2, and fuckup. The `gccarch-*`
      # store-path divergence also keeps these binaries from being
      # accidentally substituted onto a weaker CPU.
      pkgsForRocmZnver5 = system:
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
        };

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
    in
    rec {
      # Define mkSecret once and pass it to both machines and colmena
      secretsRegistry = import ./secrets/default.nix;
      mkSecret = name: overrides:
        secretsRegistry.${name} // overrides;

      # Single source of truth for network topology (hosts, vlans, IPs, helpers).
      # Threaded via specialArgs into NixOS/darwin configs and imported directly by
      # the standalone esphome generator.
      network = import ./network.nix nixpkgs.lib;

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
        });

      colmenaHive = inputs.colmena.lib.makeHive self.outputs.colmena;
      imageOnlyNixosConfigurations = [ "router-usb" ];
      deployableNixosConfigurations =
        builtins.removeAttrs self.nixosConfigurations imageOnlyNixosConfigurations;
      colmena =
        {
          meta = {
            description = "My personal machines";
            nixpkgs = pkgsFor "x86_64-linux";
            nodeNixpkgs = {
              fuckup = pkgsForCuda "x86_64-linux";
              strix-1 = pkgsForRocm "x86_64-linux";
              # Keep the Strix machines on the same generic ROCm package set
              # for routine reliability work; znver5 can be reintroduced only
              # for focused performance A/B runs.
              strix-2 = pkgsForRocm "x86_64-linux";
              # trex uses Vulkan/RADV for llama.cpp on Navi 10. Keep it on the
              # base package set so Open WebUI/Torch and routine system rebuilds
              # do not pull the ROCm package set unless a package asks for it.
              trex = pkgsFor "x86_64-linux";
            };
            specialArgs = {
              inherit inputs mkSecret pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmZnver5 network;
            };
            nodeSpecialArgs = {
              router = {
                routerStorageProfile = ./profiles/router/impermanence.nix;
              };
            };
          };
        }
        // builtins.mapAttrs
          (name: value: {
            nixpkgs.system = value.config.nixpkgs.system;
            imports = value._module.args.modules;
          })
          deployableNixosConfigurations;

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


      nixosModules = builtins.removeAttrs moduleAttrs [ "xmrig-darwin" ];

      darwinModules = {
        xmrig-darwin = moduleAttrs.xmrig-darwin;
      };

      nixosModule = {
        imports =
          builtins.attrValues self.nixosModules
          ++ [
            inputs.impermanence.nixosModules.impermanence
            inputs.sops-nix.nixosModules.sops
            inputs.disko.nixosModules.disko
            ./profiles/sops.nix
          ];
      };

      devShells = forAllSystems (system: {
        default =
          let
            pkgs = pkgsFor system;
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
              pkgs.esphome
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
          };
      };

      nixosConfigurations =
        import ./machines
          self.nixosModule
          inputs
          mkSecret
          network
          { inherit pkgsFor pkgsForCuda pkgsForRocm pkgsForRocmZnver5 allOverlays; };

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
