{
  lib,
  network,
  ...
}: {
  imports = [
    ./default.nix
  ];

  deployment.targetHost = lib.mkForce network.routing.production.transition.controlPlane.targetIp;
}
