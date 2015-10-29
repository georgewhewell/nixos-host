{ config, lib, pkgs, ... }:

{
    boot.kernelModules = [
        "vfio"
        "vfio_pci"
        "vfio_iommu_type1"
    ];

    boot.blacklistedKernelModules = [
        "nouveau"
    ];

    boot.kernelParams = [
        # Use IOMMU
        "intel_iommu=on"
        "vfio_iommu_type1.allow_unsafe_interrupts=1"

        # Assign devices to vfio
        "vfio-pci.ids=10de:17c8,10de:0fb0"

        # Needed by OS X
        "kvm.ignore_msrs=1"

        # Dont know if this is needed.
        "i915.enable_hd_vgaarb=1"

        # Only schedule cpus 0,1
        "isolcpus=2-7"
    ];

}
