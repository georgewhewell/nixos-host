{ pkgs, ... }:

{

  programs.git = {
    enable = true;
    package = pkgs.gitAndTools.gitFull;

    userName = "georgewhewell";
    userEmail = "georgerw@gmail.com";

    signing = {
      key = "0x0C414B6F2BA7BB19";
      signByDefault = true;
    };

    extraConfig = {
      core = { whitespace = "trailing-space,space-before-tab"; };
      pull = { rebase = true; };
      diff = { algorithm = "patience"; };
    };
  };

}
