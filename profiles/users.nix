{ config, lib, pkgs, ... }:

let
  gpg-pubkey = ''
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC33L+epirAZn22pRF0i/+618qWprG121KVZqPjLkpMRhsGrF1zmUnvTYEaJfg6ZD9Ndrnw5XfGw9iazkxs55JFnm+qzv9DIWjIVMTH9QLDEscz7bY0df5wKOtInByLAQ0g7KoZIZugMjywU5+N42PztUQ7fdt90tYZm4hvg7ZrjjbQBHAn3dwAsqmyQ3BtSiqfoudRABEwZx1pRqZrIE1Ms6xOHT4WN1cPCL0ROG1BWY148dj05nhJl9wGgqgFGkJoxb4bdfDsPqtcveGIFKQo5bb66OOsulSJdDA5MberYrrN8sD/yWcuwi/arRqwFAAU6MRMsM+7g5AAauNXoZVJnX0ltf2cyajUjCrLLcVSvebzH1m1ZvVqeqjUagXnc6wWpOv8NmVJMcfoboYWJ1dRfGaoUAX/T9joFr87fWkOvd/cuxRhUcy5IbL/o1ykhAfmaSUlFmdOkms8WEOwkJ+5tmRwkfSTWYwFMQcqJgf/PepatWYW/ruUTFwRDVLRx6+EdH1EiVpYCd+F2OgSUsaH7kvafciVZbwFwpg51BQ9uCTxavsGZK8TrIK1Mq0ByhOUM8Slk4QNNcIaCXivJpxd5VY2Ak44VgVze0mrxTfYffnDfAFNTmDe7W5E+X36TwqxJXpAiam3vbq8BmpQtSfUyGhWY/0acvfrdCuK9V/JCQ== cardno:000608755089
  '';
  in {

  users.extraUsers.grw = {
    extraGroups = [
      "wheel"
      "libvirtd"
      "docker"
      "transmission"
      "audio"
      "video"
      "dialout"
      "plugdev"
      "wireshark"
      "lp"
      "scanner"
      "networkmanager"
      "vboxsf"
    ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      gpg-pubkey
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDQQct7I3QWRe1pXp/cQU8YeY2U8jJI3H6xDhDoc6nEnOH7ZqA9zr8HymTO+vEERXuvBEII/RRlzevvfB3/9Lq1e6CRe6yBdJqd4snt4Eja8nu3pMnPp+S8oyN6B+K8cZppo1O5im1PIM/XBhJaqEECPs2RbytMvA87gveOCj9XD4EDl2JXRHfdwKngDaeqnE7CGgPcCQaj3Q4w6AtOGU6d4bOtqM/3cDpm0vIRCvW1jHpyPkYwTAqafUXICHm9xdSatXoA8ft2XCqlpPTjBxDNYEiD/+jwhbTd1WfTBeOll9aTqFpvcjRor44kwIl+YnuxpjviZuz3Kswj9J2HT6Rj georgewhewell@SysAdmins-MacBook-Pro.local"
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

}
