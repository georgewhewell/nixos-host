{ inputs, pkgs, lib, ... }:
{
  imports = [ inputs.quota-exporter.nixosModules.default ];

  services.llm-quota-exporter = {
    user = lib.mkDefault "grw";
    package = pkgs.llm-quota-exporter;
  };
}
