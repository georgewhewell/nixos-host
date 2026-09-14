{...}: {
  imports = [
    ../modules/common.nix
    ../modules/hardware/esp32-p4-evboard.nix
    ../modules/hardware/ip101-eth.nix
  ];

  # The GPS receiver this board used to bridge — UART on GPIO47/48 at 9600,
  # re-served as raw NMEA over TCP:8888 by oxan/esphome-stream-server, with a
  # template select to retune the baud rate at runtime — now hangs off k3's
  # on-board UART (/dev/ttyS0, the only probed port on that board), so the
  # bridge is gone. Checked before removing: the stream server still accepted
  # connections but produced no bytes, i.e. nothing was on the UART any more.
  esphome.settings = {
    esphome = {
      name = "esp32-p4-eth-01";
      friendly_name = "esp32-p4-eth-01";
    };

    # Serial logging stays off: it was disabled to keep the logger off the GPS
    # UART. Drop this line if you now want console output from the board.
    logger.baud_rate = 0;
  };
}
