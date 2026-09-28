{ pkgs, lib, configurations }:
let
  names = [ "strix-1" "strix-2" "strix-3" "strix-4" ];
  hosts = map (name: configurations.${name}.config) names;
  router = configurations.router.config;
  trex = configurations.trex.config;
  rock = configurations.rock-5b.config;
  offers = router.services.dnsmasq.settings.dhcp-boot;
  routerLocations = router.services.nginx.virtualHosts.strix-netboot-router.locations;
  originLocations = trex.services.nginx.virtualHosts.strix-netboot.locations;
  unsignedClient = (configurations.strix-2.extendModules {
    modules = [ { strix.secureBoot.enable = lib.mkForce false; } ];
  }).config;
in
assert lib.assertMsg (lib.all (host:
  host.strix.secureBoot.enable && !(host.system.build ? strixNetboot)
) hosts) "The enrolled fleet must expose only signed boot bundles.";
assert lib.assertMsg (builtins.length offers == 2 && lib.all
  (offer: lib.hasInfix "snponly-secure.efi" offer) offers
) "Both HTTP and TFTP DHCP offers must select signed iPXE.";
assert lib.assertMsg (builtins.attrNames routerLocations == [
  "/strix-netboot/secure/" "/strix-netboot/secure/by-mac/"
]) "The router must not serve raw boot endpoints.";
assert lib.assertMsg (builtins.attrNames originLocations == [ "/hosts/secure/" ])
  "The origin must not expose raw host images or unsigned iPXE.";
assert lib.assertMsg (lib.any (a:
  a.message == "strix-2: Strix netboot requires a signed UKI; raw kernel/initrd boot is retired."
  && !a.assertion
) unsignedClient.assertions) "Disabling Secure Boot must reject a Strix netboot configuration.";
assert lib.assertMsg (rock.services.kvmBootstrap.imageFile ==
  "/var/lib/kvm-bootstrap/${rock.services.kvmBootstrap.targetHost}-secure.img"
) "Rock must default to the selected host's signed recovery image.";
pkgs.runCommand "strix-secure-boot-config-test" {} ''
  touch "$out"
''
