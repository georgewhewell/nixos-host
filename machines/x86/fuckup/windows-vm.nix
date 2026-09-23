{
  config,
  lib,
  pkgs,
  network,
  ...
}: let
  # The Windows build VM, moved from trex on 2026-09-23 because trex can no
  # longer spare the RAM. Same domain UUID as on trex: swtpm keys its state
  # directory by UUID, and Windows may have BitLocker sealed to that TPM.
  name = "win10";
  uuid = "495fb261-6c4f-419c-970b-89e95495fbac";
  host = network.hosts.windows;

  # 12 vCPUs = six SMT pairs on CCD1 (cores 10-15). CCD0 (threads 0-7,16-23)
  # carries the 96 MB V-cache and is left to the desktop and games; QEMU's
  # own threads get the remaining CCD1 cores 8-9.
  vcpuPairs = [[10 26] [11 27] [12 28] [13 29] [14 30] [15 31]];
  emulatorCpus = "8-9,24-25";
  memoryGiB = 64;

  # The guest NIC is a macvtap in passthrough mode on a ConnectX VF, not a
  # PCI passthrough of the VF: the ConnectX shares IOMMU group 17 with the
  # WiFi, I226, AQC113, chipset USB and SATA behind the AMD chipset switch,
  # which has no ACS. The PF's eswitch applies the VLAN tag in hardware (see
  # fabric-rdma-vf.nix), and the guest keeps the virtio-net driver it has.
  vfName = "cx4win0";

  vcpupins = lib.concatStrings (lib.imap0 (i: cpu: ''
      <vcpupin vcpu="${toString i}" cpuset="${toString cpu}"/>
    '')
    (lib.flatten vcpuPairs));

  domainXml = pkgs.writeText "${name}.xml" ''
    <domain type="kvm">
      <name>${name}</name>
      <uuid>${uuid}</uuid>
      <memory unit="GiB">${toString memoryGiB}</memory>
      <currentMemory unit="GiB">${toString memoryGiB}</currentMemory>
      <vcpu placement="static">${toString (2 * builtins.length vcpuPairs)}</vcpu>
      <cputune>
        ${vcpupins}
        <emulatorpin cpuset="${emulatorCpus}"/>
      </cputune>
      <os>
        <type arch="x86_64" machine="q35">hvm</type>
        <loader readonly="yes" type="pflash" format="raw">/run/libvirt/nix-ovmf/edk2-x86_64-code.fd</loader>
        <nvram template="/run/libvirt/nix-ovmf/edk2-i386-vars.fd" templateFormat="raw" format="raw">/var/lib/libvirt/qemu/nvram/win10-3_VARS.fd</nvram>
        <bootmenu enable="no"/>
      </os>
      <features>
        <acpi/>
        <apic/>
        <hyperv mode="custom">
          <relaxed state="on"/>
          <vapic state="on"/>
          <spinlocks state="on" retries="8191"/>
          <vpindex state="on"/>
          <runtime state="on"/>
          <synic state="on"/>
          <stimer state="on"/>
          <frequencies state="on"/>
          <tlbflush state="on"/>
          <ipi state="on"/>
          <avic state="on"/>
        </hyperv>
        <vmport state="off"/>
      </features>
      <cpu mode="host-passthrough" check="none" migratable="off">
        <topology sockets="1" dies="1" cores="${toString (builtins.length vcpuPairs)}" threads="2"/>
        <cache mode="passthrough"/>
      </cpu>
      <clock offset="localtime">
        <timer name="rtc" tickpolicy="catchup"/>
        <timer name="pit" tickpolicy="delay"/>
        <timer name="hpet" present="no"/>
        <timer name="hypervclock" present="yes"/>
      </clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <pm>
        <suspend-to-mem enabled="no"/>
        <suspend-to-disk enabled="no"/>
      </pm>
      <devices>
        <emulator>/run/libvirt/nix-emulators/qemu-system-x86_64</emulator>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2" cache="none" io="native" discard="unmap"/>
          <source file="/var/lib/libvirt/images/win10-3.qcow2"/>
          <target dev="vda" bus="virtio"/>
          <boot order="1"/>
        </disk>
        <interface type="direct">
          <mac address="${host.mac}"/>
          <source dev="${vfName}" mode="passthrough"/>
          <model type="virtio"/>
        </interface>
        <serial type="pty"><target port="0"/></serial>
        <console type="pty"><target type="serial" port="0"/></console>
        <channel type="unix">
          <target type="virtio" name="org.qemu.guest_agent.0"/>
        </channel>
        <input type="tablet" bus="usb"/>
        <tpm model="tpm-crb">
          <backend type="emulator" version="2.0"/>
        </tpm>
        <!-- Local only: use virt-manager over qemu+ssh://fuckup/system. -->
        <graphics type="spice" autoport="yes" listen="127.0.0.1"/>
        <video><model type="virtio" heads="1" primary="yes"/></video>
        <watchdog model="itco" action="reset"/>
        <memballoon model="none"/>
      </devices>
    </domain>
  '';
in {
  virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;
    # Autostart is per-domain (virsh autostart, below); do not also resume
    # whatever happened to be running at shutdown.
    onBoot = "ignore";
    onShutdown = "shutdown";
    shutdownTimeout = 180;
  };

  # Keep the image, NVRAM and TPM off any future tmpfs/impermanence surprise.
  systemd.services.libvirtd.unitConfig.RequiresMountsFor = ["/var/lib/libvirt"];

  # (Re)define the domain from the XML above and make sure it is running.
  # Redefining a running domain only updates its persistent config; changes
  # apply at the guest's next cold boot.
  systemd.services."libvirt-domain-${name}" = {
    description = "Define and start the ${name} build VM";
    wantedBy = ["multi-user.target"];
    requires = ["libvirtd.service" "fuckup-rdma-vf.service"];
    after = ["libvirtd.service" "fuckup-rdma-vf.service" "network-online.target"];
    wants = ["network-online.target"];
    path = [config.virtualisation.libvirtd.package];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      virsh define ${domainXml}
      virsh autostart ${name}
      if [[ "$(virsh domstate ${name})" != running ]]; then
        virsh start ${name}
      fi
    '';
  };
}
