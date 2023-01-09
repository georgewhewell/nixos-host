{ config, pkgs, lib, ... }:
with lib;
{
  config = mkIf (config.sconfig.profile == "desktop") {
    services.pcscd.enable = true;

    sconfig = {
      alacritty.enable = true;
      # security-tools = true;
    };

    environment.variables.MOZ_ENABLE_WAYLAND = "1";
    environment.variables.MOZ_USE_XINPUT2 = "1";

    boot = rec {
      # extraModulePackages = with config.boot.kernelPackages; [ ddcci-driver ];
      kernel.sysctl = { "vm.swappiness" = 1; };
      kernelModules = [ "acpi_call" "i2c_dev" "ddcci-backlight" "tcp_bbr" ];
    };

    hardware = {
      brillo.enable = true;
      i2c.enable = true;
    };

    sound.mediaKeys.enable = true;

    services = {
      fstrim.enable = true;
      fwupd.enable = true;
      hardware.bolt.enable = true;
      thermald.enable = true;
    };

    #   sconfig.user-settings = ''
    #     ln -sf /etc/vscode-settings.json ~/.config/VSCodium/User/settings.json
    #     ln -sf /etc/vscode-keybindings.json ~/.config/VSCodium/User/keybindings.json
    #   '';

    #   environment.etc."vscode-settings.json".text = builtins.toJSON {
    #     "editor.renderFinalNewline" = false;
    #     "editor.scrollBeyondLastLine" = false;
    #     "extensions.autoCheckUpdates" = false;
    #     "extensions.autoUpdate" = false;
    #     "files.insertFinalNewline" = true;
    #     "files.trimFinalNewlines" = true;
    #     "files.watcherExclude"."**/result/**" = true;
    #     "git.confirmSync" = false;
    #     "python.formatting.autopep8Args" = [ "--max-line-length=999" ];
    #     "python.showStartPage" = false;
    #     "security.workspace.trust.banner" = "never";
    #     "security.workspace.trust.startupPrompt" = "never";
    #     "security.workspace.trust.untrustedFiles" = "newWindow";
    #     "terminal.external.linuxExec" = "x-terminal-emulator";
    #     "terminal.integrated.fontFamily" = "DejaVuSansMono Nerd Font";
    #     "terminal.integrated.fontSize" = 16;
    #     "terminal.integrated.showExitAlert" = false;
    #     "trailing-spaces.highlightCurrentLine" = false;
    #     "update.mode" = "none";
    #     "update.showReleaseNotes" = false;
    #     "window.menuBarVisibility" = "hidden";
    #     "workbench.startupEditor" = "none";
    #     "terminal.integrated.profiles.linux"."bash" = {
    #       "path" = "bash";
    #       "args" = [ "-c" "unset SHLVL; bash" ];
    #     };
    #   };

    #   environment.etc."vscode-keybindings.json".text = builtins.toJSON [
    #     { key = "ctrl+w"; command = "-workbench.action.terminal.killEditor"; }
    #     { key = "ctrl+e"; command = "-workbench.action.quickOpen"; }
    #     { key = "ctrl+e"; command = "workbench.action.quickOpen"; when = "!terminalFocus"; }
    #   ];

    #   virtualisation.docker = { enable = true; enableOnBoot = false; };

    #   boot.kernelPackages = pkgs.linuxPackages_5_15;

    #   boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    #   boot.loader.timeout =
    #     if config.boot.loader.systemd-boot.enable
    #     then null else lib.mkOverride 9999 99;
    # };
  };
}

