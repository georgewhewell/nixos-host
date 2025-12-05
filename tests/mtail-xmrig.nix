{ pkgs, ... }:

{
  name = "mtail-xmrig";

  nodes.machine = { config, pkgs, ... }: {
    imports = [
      ../modules/mtail.nix
    ];

    services.mtail = {
      enable = true;
      port = 3903;
      logs = [ "/run/xmrig.fifo" ];

      programs.xmrig = ''
        # XMRig miner metrics parser
        gauge xmrig_hashrate_10s
        gauge xmrig_hashrate_60s
        gauge xmrig_hashrate_15m
        gauge xmrig_hashrate_max
        counter xmrig_shares_accepted_total
        counter xmrig_shares_rejected_total
        gauge xmrig_difficulty_current
        histogram xmrig_share_response_time_ms buckets 0, 1, 5, 10, 50, 100, 500, 1000

        # Parse miner speed line
        /\[.+\]\s+miner\s+speed\s+10s\/60s\/15m\s+(?P<speed_10s>[\d\.]+)\s+(?P<speed_60s>[\d\.]+)\s+(?P<speed_15m>[\d\.]+|n\/a)\s+H\/s\s+max\s+(?P<speed_max>[\d\.]+)\s+H\/s/ {
          xmrig_hashrate_10s = float($speed_10s)
          xmrig_hashrate_60s = float($speed_60s)
          $speed_15m != "n/a" {
            xmrig_hashrate_15m = float($speed_15m)
          }
          xmrig_hashrate_max = float($speed_max)
        }

        # Parse accepted shares
        /\[.+\]\s+cpu\s+accepted\s+\((?P<accepted>\d+)\/(?P<rejected>\d+)\)\s+diff\s+(?P<diff>[\d\.]+)K\s+\((?P<response_ms>\d+)\s+ms\)/ {
          xmrig_shares_accepted_total = int($accepted)
          xmrig_shares_rejected_total = int($rejected)
          xmrig_difficulty_current = float($diff)
          xmrig_share_response_time_ms = int($response_ms)
        }
      '';
    };

    # Create FIFO for test
    systemd.tmpfiles.rules = [
      "p /run/xmrig.fifo 0644 mtail mtail -"
    ];
  };

  testScript = ''
    machine.wait_for_unit("mtail.service")

    # Inject sample xmrig log lines into FIFO
    machine.succeed(
      "echo '[2025-11-12 23:27:26.500]  miner    speed 10s/60s/15m 44802.5 44656.9 44858.5 H/s max 45885.5 H/s' > /run/xmrig.fifo &"
    )
    machine.succeed(
      "echo '[2025-11-12 23:27:34.309]  cpu      accepted (50/0) diff 1552K (1 ms)' > /run/xmrig.fifo &"
    )

    # Give mtail a moment to process
    machine.sleep(2)

    # Check metrics endpoint is responding
    metrics = machine.succeed("curl -s http://127.0.0.1:3903/metrics")

    # Verify hashrate metrics exist
    assert "xmrig_hashrate_60s" in metrics, "Missing xmrig_hashrate_60s metric"
    assert "44656.9" in metrics, "Incorrect hashrate value"

    # Verify share metrics exist
    assert "xmrig_shares_accepted_total" in metrics, "Missing xmrig_shares_accepted_total metric"
    assert "50" in metrics, "Incorrect accepted shares count"

    print("✓ mtail successfully parsed xmrig metrics")
  '';
}
