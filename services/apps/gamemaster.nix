{ config, lib, pkgs, ... }:

{
  services.postgresql.enable = true;
  services.postgresql.authentication = "local all all trust";
}
