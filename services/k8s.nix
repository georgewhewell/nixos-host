{ config, lib, pkgs, ... }:

{
  services.kubernetes.roles = ["master" "node" "loadbalancer" ];
}
