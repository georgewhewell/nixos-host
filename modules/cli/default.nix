{ config, pkgs, lib, ... }:
{
  imports = [ ./powerline.nix ];

  sconfig.powerline.enable = lib.mkDefault true;

  environment.systemPackages = with pkgs; [
    darkhttpd
    dnsutils
    dstat
    du-dust
    entr
    file
    gcc
    iftop
    inetutils
    iotop
    jq
    lm_sensors
    ncdu
    nix-index
    nix-prefetch-github
    nix-top
    nixpkgs-fmt
    openssl
    psmisc
    pv
    pwgen
    python3
    rsync
    sqlite
    tcpdump
    tree
    unzip
    usbutils
    wget
    whois
    zip

    (writeShellScriptBin "dirt" "while sleep 1; do grep '^Dirty:' /proc/meminfo ; done")

    (writeShellScriptBin "nix-roots" "nix-store --gc --print-roots | grep -v ^/proc/")

    (writeShellScriptBin "pip-install" "exec python -m ensurepip --user")

    (writeScriptBin "zram-ratio" ''
      #!${pkgs.python3}/bin/python
      (orig_data_size, compr_data_size, mem_used_total)=list(
        map(int,filter(None,open('/sys/block/zram0/mm_stat').read().split(' ')))
      )[:3]
      print("compression ratio:", orig_data_size/mem_used_total)
    '')

    (writeScriptBin "zfsram" ''
      #!${pkgs.python3}/bin/python
      for ln in open('/proc/spl/kstat/zfs/arcstats').readlines():
          if ln.startswith('size '):
              print(str(int(ln.split(' ')[-1])/(1024*1024*1024))[:5],'GB')
    '')

  ];

  environment.variables.HTOPRC = "/dev/null";
  programs.htop = {
    enable = true;
    settings = {
      hide_userland_threads = 1;
      highlight_base_name = 1;
      show_program_path = 0;
      tree_sort_direction = -1;
      tree_view = 1;
    };
  };

  programs.git = {
    enable = true;
    config = {
      alias.glog = "log --all --decorate --oneline --graph";
      alias.logl = "log --oneline -n10";
      alias.logo = "log --oneline";
      pull.ff = "only";
      init.defaultBranch = "main";
    };
  };

  programs.tmux = {
    enable = true;
    terminal = "screen-256color";
  };

  programs.bash.interactiveShellInit = ''
    stty -ixon
    alias p=python3
    alias hd='hexdump -C'
    alias catc='${pkgs.vimpager-latest}/bin/vimpager --force-passthrough'
    alias nix-env="echo nix-env is disabled #"
    alias nix-what-depends-on='nix-store --query --referrers'
    alias day='date "+%Y-%m-%d"'
  '';

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    configure = {
      packages.sconfig.start = with pkgs.vimPlugins; [
        vim-gitgutter
        vim-nix
      ];
      customRC = ''
        set encoding=utf-8
        scriptencoding utf-8
        set list nowrap scrolloff=9 updatetime=300 number
        highlight GitGutterAdd    ctermfg=10
        highlight GitGutterChange ctermfg=11
        highlight GitGutterDelete ctermfg=9
        let g:gitgutter_sign_removed = '◣'
        let g:gitgutter_sign_removed_first_line = '◤'
        let g:gitgutter_sign_modified_removed = '~~'
      '';
    };
  };
}
