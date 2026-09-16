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
  # Refuse to start if HIP ordinals 0-3 are not the four V620s. HIP orders
  # GPUs by KFD topology node, and that ordering HAS shifted on this host
  # (2026-08-24: a PCI rescan moved the iGPU from node 5 to node 1, so
  # "devices 0-3" would have included the iGPU and collided with the DS4
  # campaign). Check silicon identity, never PCI bus addresses: the PEX
  # switch renumbers the bus between power events (0f/12/17/1d one boot,
  # 4c/4f/54/57 the next), so a BDF pin fails on every re-enumeration even
  # when the device set is perfectly sound.
  v620IdentityGuard = pkgs.writeShellScript "qwen38-v620-identity-guard" ''
    set -eu

    # KFD GPU nodes (simd_count > 0) in node order = HIP ordinal order.
    gpu_ids=$(
      for n in /sys/class/kfd/kfd/topology/nodes/*; do
        simd=$(${pkgs.gnugrep}/bin/grep -m1 '^simd_count' "$n/properties" | ${pkgs.gawk}/bin/awk '{print $2}')
        [ "''${simd:-0}" -gt 0 ] || continue
        ${pkgs.gnugrep}/bin/grep -m1 '^device_id' "$n/properties" | ${pkgs.gawk}/bin/awk '{print $2}'
      done
    )

    # 0x73a1 = 29601 = Navi 21 GL-XL (Radeon Pro V620).
    expected="29601
    29601
    29601
    29601"
    first_four=$(printf '%s\n' $gpu_ids | ${pkgs.coreutils}/bin/head -n4)
    if [ "$(printf '%s\n' $first_four)" != "$(printf '%s\n' $expected)" ]; then
      echo "HIP ordinals 0-3 must all be V620s (device_id 29601); got: $(printf '%s ' $gpu_ids). Refusing to expose a shifted device set" >&2
      exit 2
    fi
  '';
in
{
  # strix-2 (netboot) is the dedicated four-V620 serving host.
  systemd.services.qwen38-serve = lib.mkIf (netboot && index == 2) {
    description = "Serve Qwen3.8-27B with sglang on the four V620s (TP4)";
    # Also wanted by the mount itself: at boot the fabric link races
    # nvme-trex-models, and a dependency-failed start job is never retried
    # even after the mount appears (observed 2026-08-26 23:49 boot). The
    # mount pulling the service closes that gap.
    wantedBy = [
      "multi-user.target"
      "models.mount"
    ];
    # sglang's get_amdgpu_memory_capacity shells out to `rocm-smi | awk`, and
    # its TVM-FFI JIT runs ninja, whose nixpkgs wrapper execs `sh` via PATH
    # (strace-verified: it never tries the literal /bin/sh) and whose
    # merge_objects rule invokes bare `ld`. A unit's minimal PATH has none of
    # these and the server dies before or during its first JIT compile; the
    # compilers themselves are absolute store paths in the sglang wrapper.
    path = [
      pkgs.bash
      pkgs.gawk
      pkgs.gnugrep
      pkgs.coreutils
      pkgs.binutils
    ];
    # /models is trex's NVMe-oF snapshot, connected by nvme-trex-models and
    # mounted as models.mount (via RequiresMountsFor). The caches need the
    # NFS /mnt/Home, hence remote-fs.target.
    # Never begin the GPU workload until every expected card has a verified
    # cap. A missing card or an unpatched running kernel fails this dependency.
    requires = [ "v620-powercap.service" ];
    after = [ "nvme-trex-models.service" "remote-fs.target" "v620-powercap.service" ];
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
        # The model's native max_position_embeddings (no rope scaling). This
        # caps request length; the KV/mamba pools are still sized from free
        # VRAM by --mem-fraction-static, so capacity, not this flag, bounds
        # concurrent long contexts. Expect long cold TTFT near the limit
        # (~35 s at 31K measured; the radix cache is what makes warm long
        # prompts cheap).
        "--context-length"
        "262144"
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
