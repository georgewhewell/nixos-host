{ config, lib, pkgs, ... }:

let
  gpg-pubkey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDDTCU9cXFbzEIZxeUCa/p0BosJPIwBetn0DNgfAAU8DMXQhuqtCBNZtd8jHHQC4QT4B7YKJfjAp1LFhetNZ2e7Urx5oxJWqkCsGtaFmtDik8i+AQNdoeTDdUDkU00YnI2+b9n6wTt6g3iWn76S2VjCmvh9LIIfLywEecWw9/cx+kT8asilesmGP8CHOeFmO+KUPMY9Ed9oRocQFpZn/NqlAKAFmx5c1mQhjf1l3cEZXpK3sSC/VsgyJd/DUo6uBlohinsbvcJ3h6r6OnxGvx3dCcRoGcnRW4hNyzB7KOjx9GChqyz7W205mBsoIBQWgHZfDU4ZtYd3Wg1Lfa6Po/g7TPCHderX6JAld9i1NeWBgCqzRZM0hsmEADuQ11XzEATQFwLBQzEYLasNLFYJSrAIX526ccYIJZhTOG+Hv3hPDEvrVhcWG881R5qr9Z40qdIHX1d9ht7iD7IO/vpwYqIVQe87+3fA2NhYhbMxgNp61leS+6VQ4JKE3q8uV0fa92FlSpSxQReFigV9BPXDUflN8VTq989l91y4rvUGiMvuNroIRa3ILeduDB4S8YJUNl9sW4xCufx7b1x6m24JpJp1xaIknH2gbw3/+rvkdvN7b7LQzJzc22T125+Bqfn6nMj8xJv4gG98WRA6vPsT9fQcDOaVOae27+qlpuQFAwiRRQ== cardno:000605973189";
in {

  users.extraUsers.grw = {
    extraGroups = [
      "wheel"
      "libvirtd"
      "docker"
      "transmission"
      "audio"
      "dialout"
      "plugdev"
      "wireshark"
      "lp"
      "scanner"
      "networkmanager"
      "vboxsf"
    ];
    isNormalUser = true;
    shell = "${pkgs.zsh}/bin/zsh";
    openssh.authorizedKeys.keys = [
      gpg-pubkey
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBHCp/KhshTrp+p1TQOp3PZfwvj+pAGzm7Z4tbRYImpHNS9octfJ4sSmL4X4YQSu4PbpM/9Jo5UzVPpCRpD6OOiA= grw@nixhost"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBZ7a3vc5ex0sSTz8uitNrf96k5iURfRL8e9AoM93Yw1oKk5CD4mOZLOb7Av7SwFLtvgGMTnpLsxuusj2QoGTCk= grw@h9fp4whfi.local"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/yARn1J0K+z8kdhLGxZgCe0kIrCJg5o7DC0oITmbzE3YKrubFVNn7zHkwzRw0b8kjfZFIxFbo5toOFCO0VN5biujrWbutzlLjTnFP0YqoL47XD58gU+TWZb/9qoV1Yjj1OUXJ+93ZTGjXGyZ+0FDtp84lFoDgSvBXf8C742g4gm6KkXYFfGYMz8LRKSnXYpeuMu18UdZVo33m8aweTvZ+m7riD6YCJILNIPFIvVExg+UNzOh4t0Hrj+O5ir9NNCqQeu633yXKlOMShbQVmmPZfrxpg24Fv5orX/pZZM+fHB94yO5wunlzxVsF5GVjCKJL5Gj/SqCRePohDiePNdP/ grw@fuckup"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDezYhZFCQE3M73WZOeotwWqqzbZgBRlL11n8lwJt+t/3uoSHO3C4iY2FfIwzB/FkSDIL9cLYrCTghwQZ3QmdGM5wGv1NjizVL6+HWO82a3xmqV1Cv0fTlalEiQ7LazotLIk3pWOTmJ5ZIqNnGHFVME6R6Yz8NGaws/CyY1LxQuM9vRwO1H+3a2Y6vVaURQvY6sM5XtTgcvH/db84UU2uqIPsyTbBUyh5Quq7hcViWk8kvZHc2UIrpWBh48A+r8vkj3UvBlEIRSP8QjI3W+2bIMgk6quWs1IjiCXgLH0eT3my0iA04p/SI3hSLyigGkd/YuJxSm2v9sLfQWm5A9h3Z/"
    ];
  };

  users.extraUsers.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCoqpsUUtxaO0QzI9MxCs5tRjsbORDwpjFjuUFdGHJwZqm7A2MzrRV7EKfqfolgxnyaAFs7IM9AZ7o9Lus2MWX89c4OAW0upeoj2qsXMiFZH7z50Cdmg/YMw5DtVMZwPBTl0S1COWfhw959QntlTjhcYh3usIq9b3XeTELGtJSk5RmTjPIA2LJ4cemx3Ru11SySvk0LsI3uCv0Vhy9n17g1sg5eekRs5Nvg1AJtOQcH4Du/0rUwwEDd9Zjn0YiF/uPVMVh22JzWVE5dbe81g8dw+mR6GRnN3vlYbU+JgGvMKgs2DeGvPHSJWl9rwKUVO6wuruzZH+1q2HxAr58ndz81 root@nixhost"
  ];

  programs.zsh.enable = true;
  programs.mosh.enable = true;

  security.sudo.wheelNeedsPassword = false;

  home-manager.users.grw = { ... }: {
    imports = [
      ../home/common.nix
    ] ;
  };
}
