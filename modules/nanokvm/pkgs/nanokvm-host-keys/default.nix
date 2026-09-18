{
  writeShellApplication,
  coreutils,
  gnugrep,
  gnused,
  gnutar,
  netcat-openbsd,
  openssh,
  ssh-to-age,
}:

writeShellApplication {
  name = "nanokvm-host-keys";

  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    gnutar
    netcat-openbsd
    openssh
    ssh-to-age
  ];

  text = builtins.readFile ./nanokvm-host-keys.sh;
}
