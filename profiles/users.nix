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
    ];
  };

  users.extraUsers.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCyo9ZxvNb/4GJ78r5vi+rWehxjdMUNY4yA/7ze7EXRi1AvUzfAJx04OGaq9oj1FDSnac3BeeIuYTqmE13ZS9amiVf2HasBWUqEQC1FHOBiqqzacijzheWC0E7CXa1xGaYETZzBhjxgVYWTKWRm6GSGQMzVvjt/LZ0dqXWyqArC3t7gbmsFVCT1q3O2oSaE7G61xrqZjxWZqtE3EOu8+nnEHhBomqav1Ap+RDoWXuooNBdX9KkKofqA2aM9+UF5TMKi8CrrmBzYjHTkTH+5yRhj5kq/xnegY1/qYd6FFuQuZ/TvtDqpB/CGNZtiVXXLGhw+WZQ8iUu8qA1uSKL8md1d root@fuckup"
    gpg-pubkey
  ];


  security.sudo.wheelNeedsPassword = false;

}
