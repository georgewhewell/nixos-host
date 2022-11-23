{ config, pkgs, lib, ... }: {

  boot.kernelPackages = pkgs.linuxPackages_latest_lto_zen3;

  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    authentication = ''
      local all all peer
      host all all 192.168.23.0/24 trust  # trust all from vpn
    '';
    ensureDatabases = [ "uniswap" "cryptoball" ];
    ensureUsers = [
      {
        name = "uniswap";
        ensurePermissions = {
          "DATABASE uniswap" = "ALL PRIVILEGES";
          "DATABASE cryptoball" = "ALL PRIVILEGES";
        };
      }
      {
        name = "grw";
        ensurePermissions = {
          "DATABASE postgres" = "ALL PRIVILEGES";
          "DATABASE uniswap" = "ALL PRIVILEGES";
          "DATABASE cryptoball" = "ALL PRIVILEGES";
        };
      }
      {
        name = "sf";
        ensurePermissions = {
          "DATABASE postgres" = "ALL PRIVILEGES";
          "DATABASE uniswap" = "ALL PRIVILEGES";
          "ALL TABLES IN SCHEMA public" = "ALL";
        };
      }
      {
        name = "jupyter";
        ensurePermissions = {
          "DATABASE uniswap" = "ALL PRIVILEGES";
          "ALL TABLES IN SCHEMA public" = "ALL";
        };
      }
    ];
  };

  systemd.services.postgresql.postStart = pkgs.lib.mkAfter ''
    $PSQL -tAc 'ALTER USER grw CREATEDB;'
    $PSQL -tAc 'ALTER USER sf CREATEDB;'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL TABLES IN SCHEMA public TO "uniswap"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO "uniswap"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL TABLES IN SCHEMA public TO "sf"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO "sf"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL TABLES IN SCHEMA public TO "jupyter"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO "jupyter"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL TABLES IN SCHEMA public TO "grw"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO "grw"'

    $PSQL uniswap -tAc 'GRANT ALL ON ALL TABLES IN SCHEMA cryptoball TO "sf"'
    $PSQL uniswap -tAc 'GRANT ALL ON ALL SEQUENCES IN SCHEMA cryptoball TO "sf"'
  '';

  virtualisation.docker.enable = true;

  nix.settings.trusted-users = [ "grw" "sf" ];
  users.extraUsers.sf = {
    isNormalUser = true;
    extraGroups = [
      "docker"
    ];
    openssh.authorizedKeys.keys = [
      # sf key
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDsEs4RIxouNDuknNbiCyGet2xQ/v74eqUmtYILlsDc3XToJqo3S/0bjiwSFUViyns1jecn943tjVEKmsMA0aKjp2KM4lu1fwBD6z3c81H+oPFCmOyFCAierxjNsgSmr9VbZechVF8a5Tk24/kvbkbNysS5k+PpabepJxvE0Zx1Idp95Yw/8jLhYqzIU28MasYdSmGCBXyEJG4LRQmfR0GAsOOsmGTWQ8MT7WIkK0UatOVOG2TKdRvfuHKlKp/ioyByk0DYFeAKbJKI1hdl3Kn2ESArC2duOznrdvIPRgC32U9F9jOWDrl47kgkwJ9Eog3j3VG5vSLdxmLVi9lYs9HTro16K8z+9E85fG30aIYCtd5JgsWUBBI1M6sqNgCfHSECFJeVv/R+fdVWNmxMzb7PbL8GHIJwHuH1LT2LSoU+VycF4DkqNO6MzRuoeQfXmCdfRW+HjWVZQCs0D4YYQCvB6HfTuErRHrBYnvHDS39HWuuYvPDga3X+QlfZYFYUyCW7zZGf0soquSmo0BN2cQOW0Zj3Kq5+CrIisWQhJGwkN+mTkqF5u692ZSyAgo1Ae7npCc0ATf/42ZQrmgCw+BLIDNMwX/X5FN5gxugRNolgcLIgP8dDjesqmQIBka8R2IJx/lSNCuMjP+JNahDVsNW/9o9Mw+wL2UnSv3axQAkN1Q== sf@chaminade"
    ];
  };

}
