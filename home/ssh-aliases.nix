{...}: {
  programs.ssh = {
    matchBlocks = {
      # Direct access to internal server via ProxyJump
      "internal internal.lsd-ag.ch 78.47.106.113" = {
        hostname = "78.47.106.113";
        user = "grw";
      };
    };
  };

  # Shell aliases for convenience
  programs.zsh.shellAliases = {
    "ssh-internal" = "ssh internal";
  };
}
