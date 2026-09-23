{
  pkgs,
  lib,
  ...
}: let
  # Weights live on mbp's own disk, not in the nix store.
  modelDir = "/Users/grw/models/muse-glimmer-30b";
in {
  imports = [
    ./darwin-configuration.nix
    ../../profiles/darwin-no-power-management.nix
    ../../services/hydra-builder-slave-darwin.nix
    ../../modules/llama-server-darwin.nix
  ];

  networking.hostName = "mbp";
  # Dedicated Thunderbolt link between MBP and Goblin; no default route.
  system.activationScripts.postActivation.text = ''
    /usr/sbin/networksetup -setmanual "Thunderbolt Bridge" 10.55.0.1 255.255.255.252 ""
  '';
  ids.gids.nixbld = 350;
  # Store optimisation hard-links every store file into /nix/store/.links
  # (millions of entries). syspolicyd's Gatekeeper checks of unsigned Nix
  # executables then enumerate that directory endlessly (getdirentries64 on
  # .links, a full core for weeks), during Metal benchmarks too.
  nix.optimise.automatic = lib.mkForce false;
  nix.settings.auto-optimise-store = lib.mkForce false;
  environment.enableAllTerminfo = lib.mkForce false;

  # mbp is a laptop; `pmset autorestart` (power.restartAfterPowerFailure, set by
  # darwin-no-power-management) isn't supported on portables and aborts activation.
  power.restartAfterPowerFailure = lib.mkForce null;

  # Preserve the home created for this existing account by the original
  # nix-darwin generation; nix-darwin deliberately refuses to move user homes.
  users.users.hydra-builder.home = lib.mkForce "/private/var/empty_1";

  # macOS 27's enlarged dyld shared cache breaks the SBCL-backed mac-app-util:
  # the deployed runtime cannot start, and its replacement graph cannot yet
  # build in the local Nix sandbox. Keep this optional launcher integration off
  # on MBP; normal applications remain available under Nix Apps.
  services.mac-app-util.enable = false;

  home-manager.users.grw.targets.darwin.mac-app-util.enable = false;

  # Muse-Glimmer-30B served over the LAN from the M4 Max's 128 GB of unified
  # memory. Full BF16 (~56 GiB of weights across two shards), so no quantisation
  # loss at all; the DFlash sidecar is what keeps generation usable at that
  # width. 128k is the model's own max_position_embeddings, and it is cheap
  # here: only 13 of 52 layers are full-attention (the rest are
  # sliding-window-2048), so the KV cache is ~1.8 GiB rather than tens of GiB.
  sconfig.llama-server = {
    enable = true;
    alias = "muse-glimmer-30b";
    modelPath = "${modelDir}/Muse-Glimmer-30B-BF16-00001-of-00002.gguf";
    mmprojPath = "${modelDir}/mmproj-Muse-Glimmer-30B-BF16.gguf";
    draftModelPath = "${modelDir}/dflash-kquant.gguf";
    contextSize = 131072;
  };

  sconfig.xmrig = {
    enable = true;
    package = pkgs.xmrig;
    rigId = "mbp";
    httpApi.accessToken = "xmrig";
    inhibit.nixBuilds.enable = true;
    mqttSwitch.passwordFile = "/Users/grw/.config/xmrig/mosquitto-password";
  };
}
