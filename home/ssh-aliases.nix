{...}: {
  programs.ssh = {
    settings = {
      # Direct access to internal server via ProxyJump
      "internal internal.lsd-ag.ch 78.47.106.113" = {
        HostName = "78.47.106.113";
        User = "grw";
      };
    };
  };

  # Shell aliases for convenience
  programs.zsh.shellAliases = {
    "ssh-internal" = "ssh internal";
  };
}
