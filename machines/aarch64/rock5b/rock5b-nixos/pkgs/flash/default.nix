{
  pkgs,
  rootfs,
  tow-boot,
  ...
}: pkgs.writeShellApplication {
  name = "flash";
  text = ''
    TOW_BOOT=${tow-boot}/shared.disk-image.img
    ROOTFS_ZST=${rootfs}
  '' + builtins.readFile ./flash.sh;
  runtimeInputs = with pkgs; [
    coreutils
    zstd
  ];
}
