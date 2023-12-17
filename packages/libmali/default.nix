{ curl
, dbus
, fetchFromGitHub
, glib
, json-glib
, lib
, nix-update-script
, openssl
, pkg-config
, stdenv
, meson
, ninja
, utillinux
, libnl
, systemd
}:

stdenv.mkDerivation rec {
  pname = "libmali";
  version = "?";

  src = fetchFromGitHub {
    owner = "JeffyCN";
    repo = "rockchip_mirrors";
    rev = "309268f7a34ca0bba0ab94a0b09feb0191c77fb8";
    sha256 = "sha256-VpHcJUTRZ3aJyfYypjVsYyRNrK0+9ci42mmlZQSkWAk=";
  };

  passthru = {
    updateScript = nix-update-script { };
  };

  enableParallelBuilding = true;

  nativeBuildInputs = [ pkg-config meson ninja ];

  buildInputs = [ curl dbus glib json-glib openssl utillinux libnl systemd ];

  mesonFlags = [
    "--buildtype=release"
    (lib.mesonOption "systemdunitdir" "${placeholder "out"}/lib/systemd/system")
    (lib.mesonOption "dbusinterfacesdir" "${placeholder "out"}/share/dbus-1/interfaces")
    (lib.mesonOption "dbuspolicydir" "${placeholder "out"}/share/dbus-1/system.d")
    (lib.mesonOption "dbussystemservicedir" "${placeholder "out"}/share/dbus-1/system-services")
  ];
}
