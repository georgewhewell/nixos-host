{ config, lib, pkgs, ... }:

{
  # Turn on virt
  virtualisation.libvirtd = {
    enable = true;
    qemuVerbatimConfig = ''
      namespaces = []

      # Whether libvirt should dynamically change file ownership
      dynamic_ownership = 0
    '';
  };

  environment.systemPackages = with pkgs; [
    virtmanager
    virt-viewer
    spice-gtk # fix usb redirect
  ];

  boot.kernelParams = [
    "kvm.report_ignored_msrs=0"
    "hugepagesz=1GB" "default_hugepagesz=1G" "hugepages=16"
    "transparent_hugepages=never"
    "kvm.ignore_msrs=1"
    "vfio_iommu_type1.allow_unsafe_interrupts=1"
  ];

  systemd.mounts = [
      # disable mounting hugepages by systemd,
      # it doesn't know about 1G pagesize
      { where = "/dev/hugepages";
	  enable = false;
      }
      { where = "/dev/hugepages/hugepages-1048576kB";
	  enable  = true;
	  what  = "hugetlbfs";
	  type  = "hugetlbfs";
	  options = "pagesize=1G";
	  requiredBy  = [ "basic.target" ];
      }
  ];

  environment.etc."tmpfiles.d/thp.conf".text = ''
    w /sys/kernel/mm/transparent_hugepage/enabled         - - - - never
  '';

  boot.kernel.sysctl = {
    "vm.nr_hugepages" = lib.mkForce 16;
  };

  environment.etc."qemu-ifup" = rec {
    target = "qemu-ifup";
    text = ''
      #!${pkgs.stdenv.shell}
      echo "Executing ${target}"
      echo "Bringing up $1 for bridged mode..."
      ${pkgs.iproute}/bin/ip link set $1 up promisc on
      echo "Adding $1 to br0..."
      ${pkgs.bridge-utils}/bin/brctl addif br0 $1
      sleep 2
    '';
    mode = "0744";
    uid = config.ids.uids.root;
  };

  /* systemd.services.libvirtd.preStart = let
    cpuset-script = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/PassthroughPOST/VFIO-Tools/master/libvirt_hooks/hooks/cset.sh";
      sha256 = "0vmbgsdym2j0wn907arh5y5kqlq55i77vy4nif4nm0ckf507hi22";
    };
    qemuHookFile = pkgs.writeText "qemu" ''

    '';
  in ''
      mkdir -p /var/lib/libvirt/hooks
      chmod 755 /var/lib/libvirt/hooks

      # Copy hook files
      cp -f ${cpuset-script} /var/lib/libvirt/hooks/qemu

      # Make them executable
      chmod +x /var/lib/libvirt/hooks/qemu
  ''; */
}
