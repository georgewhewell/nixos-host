{ lib, ... }: {
  power = {
    restartAfterFreeze = false;
    restartAfterPowerFailure = false;
    sleep = {
      computer = "never";
      display = "never";
      harddisk = "never";
      allowSleepByPowerButton = false;
    };
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "disabling power management..." >&2

    pmset_try() {
      /usr/bin/pmset "$1" "$2" "$3" >/dev/null 2>&1 || true
    }

    for scope in -b -c; do
      pmset_try "$scope" sleep 0
      pmset_try "$scope" displaysleep 0
      pmset_try "$scope" disksleep 0
      pmset_try "$scope" standby 0
      pmset_try "$scope" hibernatemode 0
      pmset_try "$scope" powernap 0
      pmset_try "$scope" tcpkeepalive 0
      pmset_try "$scope" networkoversleep 0
      pmset_try "$scope" lowpowermode 0
      pmset_try "$scope" ttyskeepawake 1
    done

    pmset_try -a disablesleep 1
    pmset_try -a autopoweroff 0
    pmset_try -a lessbright 0
    pmset_try -c womp 0

    /usr/bin/pmset repeat cancel >/dev/null 2>&1 || true
    /usr/bin/pmset schedule cancelall >/dev/null 2>&1 || true
  '';
}
