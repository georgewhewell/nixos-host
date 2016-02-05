{ config, lib, pkgs, ... }:

{
  services.tinc.networks."darknet" = {
    interfaceType = "tap";
    hosts = {
      tsar_su = ''
Address = tsar.su
Subnet 10.0.0.1
Ed25519PublicKey = Uv0u+p5xpxjqVDcFjFaS2wkmcjMkLiDo5fzIOlqs0XH
      '';
      nixhost = ''
Subnet 10.0.0.2
Ed25519PublicKey = pFg5yd5fvc2ZkfyKhJj550qXNNMxYVVkF+Ig5y9Z8dC
      '';
      Georges-Mac-Pro = ''
Subnet 10.0.0.3
Ed25519PublicKey = 8mnpkMJutf+tSnZFYGBB32YMnIwsdXzSQpoM1xB1wKN
'';
      h9fp4whfi_local = ''
Subnet 10.0.0.4
Ed25519PublicKey = BPDO5MqPCAfVroAeGNO0QJ/EJigO0HXhl6eeJqwH4hC
'';
    };
    extraConfig = ''
      ConnectTo tsar_su
    '';
  };
  networking.firewall.allowedUDPPorts = [ 655 ];
}
