{ config, lib, pkgs, ... }:

{
  users.extraUsers.buildfarm = {
    shell = "${pkgs.bash}/bin/bash";
    isNormalUser = true;
    extraGroups = [ "nixbld" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCoqpsUUtxaO0QzI9MxCs5tRjsbORDwpjFjuUFdGHJwZqm7A2MzrRV7EKfqfolgxnyaAFs7IM9AZ7o9Lus2MWX89c4OAW0upeoj2qsXMiFZH7z50Cdmg/YMw5DtVMZwPBTl0S1COWfhw959QntlTjhcYh3usIq9b3XeTELGtJSk5RmTjPIA2LJ4cemx3Ru11SySvk0LsI3uCv0Vhy9n17g1sg5eekRs5Nvg1AJtOQcH4Du/0rUwwEDd9Zjn0YiF/uPVMVh22JzWVE5dbe81g8dw+mR6GRnN3vlYbU+JgGvMKgs2DeGvPHSJWl9rwKUVO6wuruzZH+1q2HxAr58ndz81 root@nixhost"
    ];
  };

  nix.trustedUsers = [ "buildfarm" ];

}
