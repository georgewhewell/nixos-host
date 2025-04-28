# /etc/nixos/gcp-ddns.nix
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.gcp-ddns;

  dnsRecordType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        description = "DNS record name (with trailing dot)";
        example = "example.com.";
      };
      type = mkOption {
        type = types.enum ["A" "AAAA"];
        description = "DNS record type";
      };
      ttl = mkOption {
        type = types.int;
        default = 300;
        description = "TTL for DNS record";
      };
    };
  };
in {
  options.services.gcp-ddns = {
    enable = mkEnableOption "Google Cloud DNS Update Service";

    projectId = mkOption {
      type = types.str;
      description = "Google Cloud project ID";
    };

    zoneName = mkOption {
      type = types.str;
      description = "DNS zone name";
    };

    records = mkOption {
      type = types.listOf dnsRecordType;
      description = "List of DNS records to update";
      example = literalExpression ''
        [
          { name = "example.com."; type = "A"; ttl = 300; }
          { name = "*.example.com."; type = "A"; ttl = 300; }
          { name = "example.com."; type = "AAAA"; ttl = 300; }
          { name = "*.example.com."; type = "AAAA"; ttl = 300; }
        ]
      '';
    };

    interval = mkOption {
      type = types.str;
      default = "5m";
      description = "Update check interval";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.gcp-ddns = {
      description = "Google Cloud DNS Update Service";

      # Proper ordering with VPP and network
      after = [
        # "vpp-main.service"
        "network-online.target"
      ];
      # requires = ["vpp-main.service"];
      # bindsTo = ["vpp-main.service"];
      # depends = ["network-online.target"];

      path = with pkgs; [
        curl
        google-cloud-sdk
        jq
      ];

      script = ''
        # Wait for actual connectivity
        echo "Waiting 30s for network to stabilize..."
        sleep 1

        # Function to check connectivity
        check_connectivity() {
          for i in {1..10}; do
            if curl -s --connect-timeout 5 https://api.ipify.org >/dev/null; then
              return 0
            fi
            echo "Connection attempt $i failed, waiting..."
            sleep 5
          done
          echo "Failed to establish connectivity after 10 attempts"
          return 1
        }

        # Ensure we have connectivity before proceeding
        if ! check_connectivity; then
          exit 1
        fi

        # Function to get current external IPv4
        get_external_ipv4() {
            curl -s https://api.ipify.org
        }

        # Function to get current external IPv6
        get_external_ipv6() {
            curl -s https://api6.ipify.org
        }

        # Function to get current DNS record IP
        get_dns_ip() {
            local record_name="$1"
            local record_type="$2"
            gcloud dns record-sets list \
                --project="${cfg.projectId}" \
                --zone="${cfg.zoneName}" \
                --name="$record_name" \
                --type="$record_type" \
                --format="get(rrdatas[0])" 2>/dev/null
        }

        # Function to update DNS record
        update_dns_record() {
            local record_name="$1"
            local record_type="$2"
            local ttl="$3"
            local old_ip="$4"
            local new_ip="$5"

            echo "Updating $record_type record for $record_name: $old_ip -> $new_ip"

            # Clean up any stale transaction files
            rm -f transaction.yaml

            # Create transaction
            if ! gcloud dns record-sets transaction start \
                --project="${cfg.projectId}" \
                --zone="${cfg.zoneName}"; then
                echo "Failed to start transaction"
                return 1
            fi

            # Function to clean up on error
            cleanup_and_exit() {
                echo "Error occurred, cleaning up transaction"
                gcloud dns record-sets transaction abort \
                    --project="${cfg.projectId}" \
                    --zone="${cfg.zoneName}" || true
                rm -f transaction.yaml
                return 1
            }

            # Remove old record if it exists
            if [ ! -z "$old_ip" ]; then
                echo "Checking for existing record: $record_name ($record_type) with IP $old_ip"

                # Debug: show what records exist
                echo "Current records in zone:"
                gcloud dns record-sets list \
                    --project="${cfg.projectId}" \
                    --zone="${cfg.zoneName}" \
                    --name="$record_name" \
                    --type="$record_type" \
                    --format="table(name,type,rrdatas)"

                current_record=$(gcloud dns record-sets list \
                    --project="${cfg.projectId}" \
                    --zone="${cfg.zoneName}" \
                    --name="$record_name" \
                    --type="$record_type" \
                    --format="csv[no-heading](rrdatas)")

                echo "Found record data: '$current_record'"

                if [ "$current_record" = "$old_ip" ]; then
                    echo "Found existing record with matching IP $old_ip, removing..."
                    if ! gcloud dns record-sets transaction remove \
                        --project="${cfg.projectId}" \
                        --zone="${cfg.zoneName}" \
                        --name="$record_name" \
                        --type="$record_type" \
                        --ttl="$ttl" \
                        "$old_ip"; then
                        cleanup_and_exit
                        return 1
                    fi
                else
                    echo "Record exists but with different IP ($current_record), skipping remove step"
                fi
            fi

            # Add new record
            if ! gcloud dns record-sets transaction add \
                --project="${cfg.projectId}" \
                --zone="${cfg.zoneName}" \
                --name="$record_name" \
                --type="$record_type" \
                --ttl="$ttl" \
                "$new_ip"; then
                cleanup_and_exit
                return 1
            fi

            # Execute transaction
            if ! gcloud dns record-sets transaction execute \
                --project="${cfg.projectId}" \
                --zone="${cfg.zoneName}"; then
                cleanup_and_exit
                return 1
            fi

            # Clean up successful transaction
            rm -f transaction.yaml
            return 0
        }

        # Clean up any existing transactions
        if [ -f transaction.yaml ]; then
            echo "Found stale transaction file, cleaning up..."
            gcloud dns record-sets transaction abort \
                --project="${cfg.projectId}" \
                --zone="${cfg.zoneName}" || true
            rm -f transaction.yaml
        fi

        # Get current IPs
        CURRENT_IPV4=$(get_external_ipv4)
        CURRENT_IPV6=$(get_external_ipv6)

        # Update each configured record
        ${concatMapStrings (record: ''
            DNS_IP=$(get_dns_ip "${record.name}" "${record.type}")
            CURRENT_IP=$([ "${record.type}" = "A" ] && echo "$CURRENT_IPV4" || echo "$CURRENT_IPV6")

            if [ "$CURRENT_IP" != "$DNS_IP" ]; then
              update_dns_record "${record.name}" "${record.type}" "${toString record.ttl}" "$DNS_IP" "$CURRENT_IP"
            else
              echo "No IP change detected for ${record.name} (${record.type})"
            fi
          '')
          cfg.records}
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Restart = "on-failure";
        RestartSec = "30s";
      };
    };

    systemd.timers.gcp-ddns = {
      description = "Timer for Google Cloud DNS Update Service";
      wantedBy = ["timers.target"];

      # Start timer when vpp-main starts
      # after = ["vpp-main.service"];
      # bindsTo = ["vpp-main.service"];

      timerConfig = {
        OnActiveSec = "30s"; # First run 30s after timer starts
        OnUnitActiveSec = cfg.interval; # Then every interval
        AccuracySec = "1s";
      };
    };
  };
}
