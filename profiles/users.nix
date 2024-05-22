{ config, lib, pkgs, ... }:

let
  mac-pubkey = ''
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDLP7HdNP1K1zgEOiJvAJ/7UjnjbIZ77kfM0IP/M726Vw67AcpVZf7XIfwaz4/I4NeeXKHcAE1sZodbb9efZ6oOFHec0UmfDprmQYqcrTqLNSqdxfyeEV8VdxEM8N4Kp9+7zc38NeCd66B67FDPs/YzEOgWNtyR4UrJpCH60j1cSndeqPF90hDjHMmYVcUn1Pq+R6cRxppcCjOQiOPT7jST48s6pqyJm0x31GAt/bH4WERT5Wzah34tZLlNp3AEGjfZ/8CDLSEkvkkMdjyjQZJ0QJEdYH6u1VD2TOwtBuAHZCmW0yIkj+3m/1kU2AFdsz6r29Ix6azBnThMMTubYCsk6HoH+MBd7A/7tuUs4rphGTfPnMMI9IwhPkhJiWaWPJlrYW6JO/szu1LdWRORtuCyXFIFJJaOAKwkS5uaxGBdx4NXZLNtLMX+0qIkfQWBcwhkKb43TQ2+/bqEQme9U80ILGHMsYb/K8IVSbsgP0tnQPFoVv3HTyLCloIwtoL8Bf8= grw@MacBook-Air.lan'';
  gpg-pubkey = ''
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC33L+epirAZn22pRF0i/+618qWprG121KVZqPjLkpMRhsGrF1zmUnvTYEaJfg6ZD9Ndrnw5XfGw9iazkxs55JFnm+qzv9DIWjIVMTH9QLDEscz7bY0df5wKOtInByLAQ0g7KoZIZugMjywU5+N42PztUQ7fdt90tYZm4hvg7ZrjjbQBHAn3dwAsqmyQ3BtSiqfoudRABEwZx1pRqZrIE1Ms6xOHT4WN1cPCL0ROG1BWY148dj05nhJl9wGgqgFGkJoxb4bdfDsPqtcveGIFKQo5bb66OOsulSJdDA5MberYrrN8sD/yWcuwi/arRqwFAAU6MRMsM+7g5AAauNXoZVJnX0ltf2cyajUjCrLLcVSvebzH1m1ZvVqeqjUagXnc6wWpOv8NmVJMcfoboYWJ1dRfGaoUAX/T9joFr87fWkOvd/cuxRhUcy5IbL/o1ykhAfmaSUlFmdOkms8WEOwkJ+5tmRwkfSTWYwFMQcqJgf/PepatWYW/ruUTFwRDVLRx6+EdH1EiVpYCd+F2OgSUsaH7kvafciVZbwFwpg51BQ9uCTxavsGZK8TrIK1Mq0ByhOUM8Slk4QNNcIaCXivJpxd5VY2Ak44VgVze0mrxTfYffnDfAFNTmDe7W5E+X36TwqxJXpAiam3vbq8BmpQtSfUyGhWY/0acvfrdCuK9V/JCQ== cardno:000608755089
  '';
  fuckup-root = ''
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWMxfHgzc9U0+JxOiPwCvnNb9P62wMQrgP6Gzt05+rpt1qwFVUSZhXvcIqT77GErvWQqghRwRZgaVBYxIAHF2fuk/MiSg1p8vfBXXfHY3zP6fylCfXLI+6uUV7XP/DQy1sYEm4GtJ5lqUe1R6365Td8uRHw63lIwECCLLccNcJ4UGmaFyDuD7sHLdmWi+iWr7HvlblffOU551VwGPxeXYwDsc/Wzk279tBPNhlkpUW6tiu1aXWrAAttIJB3N+Xhtwc+hmxsoSSU0eckVQfUwuvdqXMW9nq5HdQfbWLxyWfS0rWkskLhrYPHf0GvWfCaygXD+bVlg+5OYvpd9mlNgaHXnXrcxyjI3hpa3pK5r4PucqqMNpiR1kySL/1LkbrTRY1ooRW2CFRh1QfsZuxhPTScu/FNOcdXwX2KOKLRlNKqipmauIoVDK8E+Dp90+/4b3yNmdkTDKEVP8zF+D6lSHAKDSzkKN7Z5sh5tOpTGIuk0BvKuJ8KLHBN3eCxSDPn00= root@fuckup
  '';
  air-grw = ''
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC87LO0rf0HxGpcFViyLH9hJiIHT6ptZgZ7W9d6PfBe8ADVMinvheiZgYHEOv/sQzEIP/3n6qCaLzcQ0vHzTnN+4VIET4APT+3g0yQizWB31qfTGl8qAVneJZVbudKEGTBeHZbfiahpJV1K+YXLg5+ig9ayT1QckBwvk1SW1HUc/tFriYO7Gbl9w2NxNOVMvujhGhUgRPeoY0xpgYdWz4AFS3D+WtzbnHGI7DPBPyxBZajm6zFrEhJBoZe/2NCBFkPckPs4X+su1fFoAab9IX/jI7EVpnVOA8gPVE8WlwvZXZqz8jn9pBwv/V+xGTCWLJgs1GLnrHS4aAgpAZVXIgGl3YXcUVO2VCFUTAM3msHSShLtbocqMDqqTIXLiIsfJQ0lSYr1+MBJ4QSbvxIVRk0/ZgCvlPrLEG7dDJaquJovfVNvQCk46Dr5aTP03EohYNOAstlmzoMyEfxE9ZF+kWWntjELnMNIT/TPdkMHJf7U91rITFy58xaxbL2DNMVmo88= grw@air
  '';
  yoga-root = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHa3IehyF09gwMwVLCW68xNvxNxNPeRP2DKUgbRv/mpP root@yoga
  '';
  trex-root = ''
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEtPi2T/lOR9s64SVS4ETOmJgj//nKJxuGD8A+PZxcLb root@trex
  '';
in
{

  users.extraUsers.grw = {
    shell = pkgs.zsh;
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
      "sway"
      "go-ethereum"
      "ipfs"
    ];
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      gpg-pubkey
      mac-pubkey
      air-grw
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    gpg-pubkey
    mac-pubkey
    fuckup-root
    air-grw
    yoga-root
    trex-root
  ];

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

}
