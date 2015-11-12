{ config, lib, pkgs, ... }:

{
  users.extraUsers.grw = {
    extraGroups = ["wheel" "libvirtd" "docker"];
    isNormalUser = true;
    uid = 1000;
     openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDW9YJVC34+IfBRAMhwtiENOJfUd00jsQhoFMBrGWPclniC1iyxxWpyAXSlvVrIKqxRxoK55Pz9bg3eId5H0iybFIukta+AcWrI6Ny2s0O1f/Q6tv93NPKvVEo+tPwarsEDuwxSGlernBuYa35G6popuRsn//seuQ/hIHneoOIAtG6wGJ38kqT+iKHCCJBfY1c6Hcw09rbm4NBpwbBONhSW9MAQa34mt41jBXmwmsZVEA0fQVuDZtb9PDgc8+ciks75b5Li3WWxo1BP3+A/vAQhat0JRicSa4JXCJs+cadIXoIHvlsYyJZKUXJXDciGkRaV/lYtQZlzvGgy5dtsnlFl grw@h9fp4whfi.local.tld" ];
  };
  users.extraUsers.munin = {

    extraGroups = [];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC5bUrPJz6vHugl5FqI8B4J0josCaujleg7EKUn6ZPJF0BbX5/v0nTpQE3bQ4iPr6wtpqxSLpNaGwshq/Zq2Wnq8kXbHlje5VBaTVGs/6HlgJNSNzE1/TutvNd1bk36Of+IPvPbIEmejvnYZ9gDxEPRS2PZ0C6aOSOhjaZTgqwrY8Dp0q0DMMo5FyQcQ7GhUHeW76CQ/GOdMeJjXNUei6pYem9m61VOfm6E/uXBZ4KmjecqFqbW7Q9jMWnWsCixF1PrKS8aXQhIKKrdoiiXHD7iTP0WgYx/ftvC5io/Osf1vok8rvl4KeYr37PoZCvMGTy0uvPBQcyOtoT0g0t1w7B5 munin@tsar.su" ] ;
   };
}
