{
  pkgs,
  lib,
  ...
}: let
  # The BlueField-2 shares PCI slot c3:00 with the CX5 SharedIO on other
  # strix hosts and can move between slots, so both services discover the
  # card by PCI ID instead of by address. a2d6 is the integrated
  # ConnectX-6 Dx NIC PF, c2d3 the SoC management (rshim) function.
  findFunction = device: ''
    addr=""
    for dev in /sys/bus/pci/devices/*; do
      [ "$(cat "$dev/vendor")" = "0x15b3" ] || continue
      [ "$(cat "$dev/device")" = "${device}" ] || continue
      addr="$(basename "$dev")"
      break
    done
  '';

  # The DPU's ARM cores own the NIC (EMBEDDED_CPU mode) and its firmware
  # only completes host-PF init once they have booted. From a cold start
  # that takes a few minutes, while the kernel's boot-time probe gives up
  # after 120s, so keep retrying the bind until the firmware comes up.
  # Each failed attempt itself blocks up to 120s in wait_fw_init.
  nicBind = pkgs.writeShellScript "bluefield-nic-bind" ''
    set -u
    ${findFunction "0xa2d6"}
    if [ -z "$addr" ]; then
      echo "no BlueField NIC function present, nothing to do"
      exit 0
    fi
    ${pkgs.kmod}/bin/modprobe mlx5_core
    for _ in $(${pkgs.coreutils}/bin/seq 1 8); do
      [ -e "/sys/bus/pci/devices/$addr/driver" ] && exit 0
      echo "$addr" > /sys/bus/pci/drivers/mlx5_core/bind 2>/dev/null || true
      [ -e "/sys/bus/pci/devices/$addr/driver" ] && exit 0
      ${pkgs.coreutils}/bin/sleep 10
    done
    echo "BlueField firmware never left pre-init; is the DPU booting?" >&2
    exit 1
  '';

  nicUnbind = pkgs.writeShellScript "bluefield-nic-unbind-if-shared" ''
    set -u
    ${findFunction "0xa2d6"}
    nic_addr="$addr"
    ${findFunction "0xc2d3"}
    rshim_addr="$addr"

    if [ -z "$nic_addr" ] || [ -z "$rshim_addr" ]; then
      exit 0
    fi

    nic_group="$(${pkgs.coreutils}/bin/readlink -f "/sys/bus/pci/devices/$nic_addr/iommu_group" 2>/dev/null || true)"
    rshim_group="$(${pkgs.coreutils}/bin/readlink -f "/sys/bus/pci/devices/$rshim_addr/iommu_group" 2>/dev/null || true)"

    # VFIO requires exclusive ownership of an IOMMU group.  Some hosts put
    # both BlueField functions in one group; this router isolates them, so its
    # mlx5 PF can remain bound while RShim owns only the management function.
    if [ -n "$nic_group" ] && [ "$nic_group" = "$rshim_group" ] \
       && [ -e "/sys/bus/pci/devices/$nic_addr/driver" ]; then
      echo "$nic_addr" > "/sys/bus/pci/devices/$nic_addr/driver/unbind"
    fi
  '';
in {
  environment.systemPackages = [
    pkgs.mstflint
    pkgs.rdma-core
    pkgs.rshim-user-space
  ];

  boot.kernelModules = [
    "mlx5_core"
    "mlx5_ib"
    "vfio-pci"
  ];

  systemd.services.bluefield-nic-bind = {
    description = "Bind the BlueField-2 host PF once DPU firmware is ready";
    wantedBy = ["multi-user.target"];
    after = [
      "systemd-modules-load.service"
      # In a transaction that stops rshim and starts this unit, order the
      # rshim stop (and its vfio group release) first.
      "bluefield-rshim.service"
    ];
    serviceConfig = {
      Type = "simple";
      ExecStart = nicBind;
    };
  };

  # Recovery console/boot channel to the DPU. Started manually by default.
  # When PCIe ACS gives the management function its own IOMMU group, RShim and
  # mlx5 can coexist; otherwise ExecStartPre releases the NIC PF first.
  systemd.services.bluefield-rshim = {
    description = "BlueField RShim PCIe management interface";
    conflicts = ["bluefield-nic-bind.service"];
    # The userspace backend invokes modprobe while selecting VFIO/UIO.  NixOS
    # units have a minimal PATH, so expose kmod explicitly rather than silently
    # falling back to direct BAR mapping.
    path = [pkgs.kmod];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = nicUnbind;
      ExecStart = "${pkgs.rshim-user-space}/bin/rshim -b pcie -f -l 2";
      ExecStopPost = "${pkgs.systemd}/bin/systemctl --no-block start bluefield-nic-bind.service";
    };
  };

  # Host side of the rshim/tmfifo recovery link; the DPU owns
  # 192.168.100.2/30. Only carries traffic while bluefield-rshim runs.
  systemd.network.networks."50-bluefield-tmfifo" = {
    matchConfig.Name = "tmfifo_net0";
    address = [
      "192.168.100.1/30"
    ];
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
      ConfigureWithoutCarrier = true;
    };
    linkConfig.RequiredForOnline = "no";
  };
}
