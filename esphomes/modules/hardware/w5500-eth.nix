{...}: {
  imports = [
    ../ethernet-info.nix
  ];

  esphome.settings = {
    ethernet = {
      type = "W5500";
      clk_pin = "GPIO13";
      mosi_pin = "GPIO11";
      miso_pin = "GPIO12";
      cs_pin = "GPIO14";
      interrupt_pin = "GPIO10";
      reset_pin = "GPIO9";
      clock_speed = "40MHz";
    };
    esp32.framework.sdkconfig_options = {
      CONFIG_LWIP_MAX_SOCKETS = "32";
      CONFIG_LWIP_TCP_MSS = "1460";
      CONFIG_LWIP_TCP_WND = "131072";
      CONFIG_LWIP_TCPIP_RECVMBOX_SIZE = "64";
      CONFIG_LWIP_TCPIP_TASK_STACK_SIZE = "4096";
      CONFIG_LWIP_TCP_SND_BUF_DEFAULT = "65535";
      CONFIG_LWIP_TCP_RECVMBOX_SIZE = "64";
      CONFIG_SPI_MASTER_ISR_IN_IRAM = "y";
    };
  };
}
