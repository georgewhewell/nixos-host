{ config, pkgs, lib, ... }:
let
  cfg = config.sconfig.status-on-console;

  ncfg = pkgs.writeText "neofetch.conf" ''
    print_info() {
        info title
        info underline

        info "OS" distro
        info "Host" model
        info "Kernel" kernel
        info "Uptime" uptime
        info "CPU" cpu
        info "Memory" memory
        info "Disk" disk
        info "Local IP" local_ip

        info cols
    }
  '';

  nscript = pkgs.writeShellScript "neofetch-wrapped" ''
    export PATH="$PATH:/run/current-system/sw/bin"
    (
      ${pkgs.neofetch}/bin/neofetch --config "${ncfg}"
      echo '\l'
    ) >/run/issue
  '';

in
{
  options.sconfig.status-on-console = lib.mkEnableOption "Display Neofetch on system console";

  config = lib.mkIf cfg {
    environment.etc.issue.source = pkgs.lib.mkForce "/run/issue";
    systemd.services."getty@".serviceConfig.ExecStartPre = "-${nscript}";
  };
}
