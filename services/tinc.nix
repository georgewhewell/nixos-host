{ config, lib, pkgs, ... }:

{
  services.tinc.networks."darknet" = {
    interfaceType = "tap";
    hosts = {
      tsar_su = ''
Address = tsar.su
Ed25519PublicKey = Uv0u+p5xpxjqVDcFjFaS2wkmcjMkLiDo5fzIOlqs0XH
      '';
      nixhost = ''
Ed25519PublicKey = pFg5yd5fvc2ZkfyKhJj550qXNNMxYVVkF+Ig5y9Z8dC
      '';
      Georges-Mac-Pro = ''
Ed25519PublicKey = 8mnpkMJutf+tSnZFYGBB32YMnIwsdXzSQpoM1xB1wKN
'';
      h9fp4whfi_local = ''
Ed25519PublicKey = BPDO5MqPCAfVroAeGNO0QJ/EJigO0HXhl6eeJqwH4hC
'';
     iPhone = ''
Ed25519PublicKey = HgbMtGmOQB65ObsD0a2Q1S+Gm+UKzjL7ty6Dv4jlEqK
'';
	};
    extraConfig = ''
      ConnectTo tsar_su
    '';
  };
  networking.firewall.allowedUDPPorts = [ 655 ];
  networking.firewall.allowedTCPPorts = [ 655 ];
}
