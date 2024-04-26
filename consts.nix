{ lib, ... }:

{
  wireguard =
    let
      port = 51820;
      subnet = "192.168.33.";
    in
    rec {
      hosts =
        {
          cloud = {
            endPoint = "cloud.satanic.link";
            pubKey = "6ndFmwbRoCQospT/7tiDW9vzGmPhnLwpLOBWG737V0M=";
            ipAddress = 1;
          };
          yoga = {
            ipAddress = 2;
            pubKey = "mNoifcPcs9157BUNj0A5IkJVFJflffyaV2LbgcNjMWA=";
          };
          router = {
            ipAddress = 3;
            endPoint = "satanic.link";
            pubKey = "9UPRg+xZYCs0hOgGBzMSr0v12eZCOVBSE+BvBASDIS0=";
          };
          fuckup = {
            ipAddress = 4;
            pubKey = "pOLMc3pVzGFe7A5KkCPTKfbov1HLX6R8L3gV/G/+2UA=";
          };
        };

      makePeerConfig = excludedKey: lib.filter (x: x != null) (lib.attrsets.mapAttrsToList
        (k: v:
          if k == excludedKey then
            null
          else
            let
              basicConfig = {
                PublicKey = v.pubKey;
                AllowedIPs = [ "${subnet}${toString v.ipAddress}/32" ];
                PersistentKeepalive = 25;
              };
              endpointConfig = if v ? endPoint then { Endpoint = "${v.endPoint}:${toString port}"; } else { };
            in
            {
              wireguardPeerConfig = lib.attrsets.recursiveUpdate basicConfig endpointConfig;
            }
        )
        hosts);

      getIpForHost = hostName:
        let
          hostEntry = hosts.${hostName} or null;
        in
        if hostEntry == null then
          null
        else
          "${subnet}${toString hostEntry.ipAddress}/24";
    };
}
