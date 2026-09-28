{ pkgs }:
pkgs.runCommand "strix-secure-boot-publisher-test" {
  nativeBuildInputs = [ pkgs.python3 pkgs.openssl pkgs.sbsigntool pkgs.binutils ];
} ''
  python3 ${./test_secure_boot_publisher.py} \
    ${../profiles/secure-boot-publish.py} \
    ${pkgs.systemd}/lib/systemd/boot/efi/linuxx64.efi.stub
  touch "$out"
''
