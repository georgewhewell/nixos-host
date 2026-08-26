# Qwen3.8-27B production serving on strix-2's four Radeon Pro V620s
# (gfx1030, TP4). Systemd replacement for the hand-run
# nix-strix-halo/scripts/qwen38-serve.sh; see that script for the full
# rationale behind each flag.
#
# ISOLATION: HIP indices 0-3 are the V620s behind the PEX switch. Index 4 is
# the Strix Halo iGPU and belongs to the parallel DS4 campaign — never expose
# it to this service.
index: { pkgs, lib, inputs, network, ... }:
let
  hostName = "strix-${toString index}";
  self = network.hosts.${hostName};
  netboot = self.netboot or false;
  # gfx1030 sglang 0.5.14 with the V620 patch set baked in (Triton GDN
  # kernels, ROCm mamba radix cache, fp16 conv-dtype support).
  sglang =
    inputs.nix-strix-halo-qwen38.legacyPackages.${pkgs.stdenv.hostPlatform.system}.gfx1030.sglang-rocm;
  # Caches must live on persistent NFS: not /tmp (tmpfs, reboots), and not
  # /var — on these diskless nodes that is the tmpfs overlay, and filling it
  # has previously stale-handled the root.
  cacheDir = "/mnt/Home/services/qwen38/cache";
  v620IdentityGuard = pkgs.writeShellScript "qwen38-v620-identity-guard" ''
    set -eu

    for gpu_id in 0 1 2 3; do
      case "$gpu_id" in
        0) expected_bdf=0000:0f:00.0 ;;
        1) expected_bdf=0000:12:00.0 ;;
        2) expected_bdf=0000:17:00.0 ;;
        3) expected_bdf=0000:1d:00.0 ;;
      esac

      pci_device="/sys/bus/pci/devices/$expected_bdf"
      expected_path="$(${pkgs.coreutils}/bin/readlink -f "$pci_device" 2>/dev/null || true)"
      visible_path="$(${pkgs.coreutils}/bin/readlink -f "/sys/class/drm/card$gpu_id/device" 2>/dev/null || true)"
      vendor="$(${pkgs.coreutils}/bin/cat "$pci_device/vendor" 2>/dev/null || true)"
      driver="$(${pkgs.coreutils}/bin/basename "$(${pkgs.coreutils}/bin/readlink -f "$pci_device/driver" 2>/dev/null || true)")"

      if [ -z "$expected_path" ] \
        || [ "$visible_path" != "$expected_path" ] \
        || [ "$vendor" != 0x1002 ] \
        || [ "$driver" != amdgpu ]; then
        echo "HIP ordinal $gpu_id must be the AMD V620 at $expected_bdf; refusing to expose a shifted device set" >&2
        exit 2
      fi
    done
  '';
in
{
  # strix-2 (netboot) is the dedicated four-V620 serving host.
  systemd.services.qwen38-serve = lib.mkIf (netboot && index == 2) {
    description = "Serve Qwen3.8-27B with sglang on the four V620s (TP4)";
    wantedBy = [ "multi-user.target" ];
    # /models is trex's NVMe-oF snapshot, connected by nvme-trex-models and
    # mounted as models.mount (via RequiresMountsFor). The caches need the
    # NFS /mnt/Home, hence remote-fs.target.
    after = [ "nvme-trex-models.service" "remote-fs.target" ];
    wants = [ "nvme-trex-models.service" ];
    unitConfig.RequiresMountsFor = [ "/models" ];
    environment = {
      # The GDN conv state has NO CLI flag: sglang hardcodes bfloat16, and
      # with fp16 weights the Triton frontend rejects the mixed-dtype conv
      # kernel in the first prefill. It must track the weight dtype on any
      # bf16-less GPU.
      SGLANG_MAMBA_CONV_DTYPE = "float16";
      # The four V620s only; HIP index 4 is the iGPU (see header).
      HIP_VISIBLE_DEVICES = "0,1,2,3";
      # TP4 is switch-local P2P/IPC; the socket path is bootstrap only, but
      # unpinned interface selection has wedged multi-rank jobs on this fleet.
      NCCL_SOCKET_IFNAME = "lo";
      NCCL_P2P_DISABLE = "0";
      XDG_CACHE_HOME = cacheDir;
      TRITON_CACHE_DIR = "${cacheDir}/triton";
      TORCHINDUCTOR_CACHE_DIR = "${cacheDir}/inductor";
      HF_HOME = "${cacheDir}/hf";
    };
    serviceConfig = {
      # The NFS paths are owned by grw and trex may root-squash, so run —
      # and create the cache dirs — as that user, not root.
      User = "grw";
      Group = "users";
      ExecStartPre = [
        v620IdentityGuard
        "${pkgs.coreutils}/bin/mkdir -p ${cacheDir}/triton ${cacheDir}/inductor ${cacheDir}/hf"
      ];
      ExecStart = lib.escapeShellArgs [
        "${sglang}/bin/sglang"
        # sglang 0.5.14: `serve` replaced the removed launch_server entry point.
        "serve"
        "--model-path"
        "/models/Qwen3.8-27B"
        "--tp-size"
        "4"
        # fp16, not bf16: gfx1030 has no bf16 ALU but native packed fp16 at
        # 2x rate, and fp16's 10 mantissa bits make the conversion exact for
        # every weight in range.
        "--dtype"
        "float16"
        # The model config pins the DeltaNet recurrent state to fp32; keep it
        # there regardless of the weight dtype.
        "--mamba-ssm-dtype"
        "float32"
        # Forced, not preferred: the alternative attention and linear-attn
        # backends are all CUDA-only, so Triton is the ONLY backend that can
        # drive the GDN and full-attention layers on gfx1030.
        "--attention-backend"
        "triton"
        "--linear-attn-backend"
        "triton"
        "--context-length"
        "32768"
        "--mem-fraction-static"
        "0.85"
        "--host"
        "0.0.0.0"
        "--port"
        "30800"
        # qwen3_coder, not qwen: the chat template emits the XML-ish
        # <function=...> form the qwen25 JSON parser cannot extract.
        "--tool-call-parser"
        "qwen3_coder"
        "--reasoning-parser"
        "qwen3"
        "--served-model-name"
        "qwen38"
        "--log-level"
        "info"
      ];
      Restart = "on-failure";
      RestartSec = 15;
      # Cold boot loads 52 GB of weights and captures CUDA graphs; 10+ min.
      TimeoutStartSec = 1800;
      # sglang tears down four TP rank processes: SIGTERM the leader only,
      # then let systemd sweep the remaining cgroup members.
      KillMode = "mixed";
      TimeoutStopSec = 300;
    };
  };
}
