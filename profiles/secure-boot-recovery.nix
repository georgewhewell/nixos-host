{ pkgs }:
pkgs.writeShellApplication {
  name = "strix-secure-boot-recovery";
  runtimeInputs = [ pkgs.coreutils pkgs.sbsigntool pkgs.openssl pkgs.parted pkgs.dosfstools pkgs.mtools ];
  text = ''
    if [ "$#" -ne 3 ]; then
      echo "usage: strix-secure-boot-recovery SIGNED-UKI CERTIFICATE OUTPUT.img" >&2
      exit 2
    fi
    uki=$(realpath "$1")
    certificate=$(realpath "$2")
    output=$(realpath -m "$3")
    # Refuse devices and existing output files. This tool only creates a new
    # regular image; installing it on removable hardware is a separate step.
    test ! -e "$output"
    sbverify --cert "$certificate" "$uki"
    stage=$(mktemp -d "$(dirname "$output")/.recovery.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    # Leave room for FAT metadata without requiring a full runtime image.
    size=$(( ($(stat -c %s "$uki") + 1048575) / 1048576 + 32 ))
    truncate -s "$((size + 2))M" "$stage/disk.img"
    parted --script "$stage/disk.img" mklabel gpt mkpart ESP fat32 1MiB "$((size + 1))MiB" set 1 esp on
    truncate -s "''${size}M" "$stage/esp.img"
    mkfs.vfat -F 32 -n STRIXRESCUE "$stage/esp.img"
    mmd -i "$stage/esp.img" ::/EFI ::/EFI/BOOT
    mcopy -i "$stage/esp.img" "$uki" ::/EFI/BOOT/BOOTX64.EFI
    openssl x509 -in "$certificate" -outform DER -out "$stage/strix-db.cer"
    mcopy -i "$stage/esp.img" "$stage/strix-db.cer" ::/strix-db.cer
    dd if="$stage/esp.img" of="$stage/disk.img" bs=1M seek=1 conv=notrunc status=none
    chmod 0644 "$stage/disk.img"
    mv -T "$stage/disk.img" "$output"
  '';
}
