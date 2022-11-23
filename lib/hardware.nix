modulesPath: {
  physical = { lib, ... }: lib.mkMerge
    [
      (import "${modulesPath}/installer/scan/not-detected.nix" { inherit lib; })
      { hardware.cpu.amd.updateMicrocode = true; }
      { hardware.cpu.intel.updateMicrocode = true; }
    ];

  qemu = { lib, ... }: lib.mkMerge
    [
      (import "${modulesPath}/profiles/qemu-guest.nix" { })
      { services.qemuGuest.enable = true; }
    ];

  vmware = { lib, ... }: lib.mkMerge
    [
      { virtualisation.vmware.guest.enable = true; }
      { boot.initrd.availableKernelModules = [ "mptspi" ]; }
    ];
}
