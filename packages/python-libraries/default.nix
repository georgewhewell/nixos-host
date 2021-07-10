{ callPackage }:

rec {

  adafruit-gpio = callPackage ./adafruit-gpio { };
  adafruit-pureio = callPackage ./adafruit-pureio { };
  rpi-gpio = callPackage ./rpi-gpio { };
  opi-gpio = callPackage ./opi-gpio { };
  smbus-cffi = callPackage ./smbus-cffi { };
  smbus2 = callPackage ./smbus2 { };
  spidev = callPackage ./spidev { };
  luma-core = callPackage ./luma.core { inherit smbus2 spidev rpi-gpio opi-gpio; };
  luma-oled = callPackage ./luma.oled { inherit luma-core; };
  python-periphery = callPackage ./python-periphery { };
  btlewrap = callPackage ./btlewrap { };
  miflora = callPackage ./miflora { inherit btlewrap; };

  pydeconz = callPackage ./pydeconz { };
  spotify_token = callPackage ./spotify_token { };


  numpyro = callPackage ./numpyro { };
  jax = callPackage ./jax { };
  jaxlib = callPackage ./jaxlib { };
  jaxlib-bin = callPackage ./jaxlib-bin { };

}
