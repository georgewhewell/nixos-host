{ config, lib, pkgs, ... }:

{
  users.extraUsers.grw = {
    extraGroups = ["wheel" "libvirtd"];
    isNormalUser = true;
    uid = 1000;
     openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDW9YJVC34+IfBRAMhwtiENOJfUd00jsQhoFMBrGWPclniC1iyxxWpyAXSlvVrIKqxRxoK55Pz9bg3eId5H0iybFIukta+AcWrI6Ny2s0O1f/Q6tv93NPKvVEo+tPwarsEDuwxSGlernBuYa35G6popuRsn//seuQ/hIHneoOIAtG6wGJ38kqT+iKHCCJBfY1c6Hcw09rbm4NBpwbBONhSW9MAQa34mt41jBXmwmsZVEA0fQVuDZtb9PDgc8+ciks75b5Li3WWxo1BP3+A/vAQhat0JRicSa4JXCJs+cadIXoIHvlsYyJZKUXJXDciGkRaV/lYtQZlzvGgy5dtsnlFl grw@h9fp4whfi.local.tld" ];
  };
}
