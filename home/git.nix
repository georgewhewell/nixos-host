{...}: {
  programs.git = {
    enable = true;
    # package = pkgs.gitAndTools.gitFull;
    lfs.enable = true;

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

    settings = {
      user = {
        name = "georgewhewell";
        email = "georgerw@gmail.com";
      };
      core = {whitespace = "trailing-space,space-before-tab";};
      pull = {
        rebase = true;
        autostash = true;
      };
      diff = {algorithm = "patience";};
      push = {autoSetupRemote = true;};
      safe = {
        directory = "*";
      };
    };
  };
}
