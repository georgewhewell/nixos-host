{ config, lib, pkgs, ... }:

{
 networking.firewall.allowedTCPPorts = [ 10080 2222];
}
