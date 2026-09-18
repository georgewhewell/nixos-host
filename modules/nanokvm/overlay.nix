final: _prev: {
  # Throughput benchmark for the USB transport. Wrapped as a
  # writeShellApplication so its closure carries jq+iperf3+fio+ssh
  # by reference; `nix run .#nanokvm-bench-usb-transport` works
  # without nested `nix shell` calls that add eval noise to the
  # measurement.
  nanokvm-bench-usb-transport = final.writeShellApplication {
    name = "nanokvm-bench-usb-transport";
    runtimeInputs = with final; [
      coreutils
      fio
      gnugrep
      gnused
      iperf3
      iputils # ping
      jq
      openssh
    ];
    text = builtins.readFile ./scripts/bench-usb-transport.sh;
  };
  nbd-client-minimal = final.callPackage ./pkgs/nbd-client-minimal { };
  nanokvm-host-keys = final.callPackage ./pkgs/nanokvm-host-keys { };
  nanokvm-erofs-rootfs-for = toplevel:
    final.callPackage ./pkgs/erofs-rootfs { inherit toplevel; };
  nanokvm-kexec-payload-erofs = args:
    final.callPackage ./pkgs/kexec-payload-erofs args;
}
