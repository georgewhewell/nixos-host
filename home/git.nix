{...}: {
  programs.git = {
    enable = true;
    # package = pkgs.gitAndTools.gitFull;
    lfs.enable = true;
    userName = "georgewhewell";
    userEmail = "georgerw@gmail.com";

    ignores = [
      ".vscode/settings.json"
      ".direnv"
      ".envrc"
      ".DS_Store"
    ];

    signing = {
      key = "2BA7BB19";
      signByDefault = true;
    };

    extraConfig = {
      core = {whitespace = "trailing-space,space-before-tab";};
      pull = {
        rebase = true;
        autostash = true;
      };
      diff = {algorithm = "patience";};
      push = {autoSetupRemote = true;};
    };
  };
}
