#!/usr/bin/env python3
"""
Backfill Withings historical data into VictoriaMetrics.

Pulls all body measurement data from the Withings API and imports it into
VictoriaMetrics using the same metric names/labels that Home Assistant uses,
so the data seamlessly extends existing graphs.

Usage:
    python3 withings-backfill.py [--dry-run]

Requires: requests (pip install requests)
"""

import argparse
import json
import sys
import time
from datetime import datetime

import requests

# --- Configuration ---
WITHINGS_API = "https://wbsapi.withings.net/measure"
VM_IMPORT_URL = "https://grafana.satanic.link/victoria/api/v1/import/prometheus"

# Grab token from HA config on the same machine
HA_CONFIG_ENTRIES = "/var/lib/hass/.storage/core.config_entries"

# Withings measure type -> (HA metric name, HA entity_id, HA friendly_name, unit_suffix)
MEASURE_MAP = {
    1: (
        "homeassistant_sensor_weight_kg",
        "sensor.withings_weight_kg_george",
        "George Weight",
    ),
    5: (
        "homeassistant_sensor_weight_kg",
        "sensor.withings_fat_free_mass_kg_george",
        "George Fat free mass",
    ),
    6: (
        "homeassistant_sensor_unit_percent",
        "sensor.withings_fat_ratio_pct_george",
        "George Fat ratio",
    ),
    8: (
        "homeassistant_sensor_weight_kg",
        "sensor.withings_fat_mass_kg_george",
        "George Fat mass",
    ),
    11: (
        "homeassistant_sensor_unit_bpm",
        "sensor.withings_heart_pulse_bpm_george",
        "George Heart pulse",
    ),
    76: (
        "homeassistant_sensor_weight_kg",
        "sensor.withings_muscle_mass_kg_george",
        "George Muscle mass",
    ),
    88: (
        "homeassistant_sensor_weight_kg",
        "sensor.withings_bone_mass_kg_george",
        "George Bone mass",
    ),
    91: (
        "homeassistant_sensor_speed_m_per_s",
        "sensor.withings_pulse_wave_velocity_george",
        "George Pulse wave velocity",
    ),
}

COMMON_LABELS = {
    "domain": "sensor",
    "instance": "router:8123",
    "job": "home-assistant",
}


def get_access_token():
    """Read current Withings access token from HA config."""
    with open(HA_CONFIG_ENTRIES) as f:
        data = json.load(f)

    for entry in data["data"]["entries"]:
        if entry.get("domain") == "withings":
            token_data = entry["data"]["token"]
            expires_at = token_data["expires_at"]
            if time.time() > expires_at:
                print(
                    f"WARNING: Token expired at {datetime.fromtimestamp(expires_at)}",
                    file=sys.stderr,
                )
                print(
                    "Restart Home Assistant or re-auth to refresh the token.",
                    file=sys.stderr,
                )
                sys.exit(1)
            return token_data["access_token"]

    print("No Withings config entry found in HA", file=sys.stderr)
    sys.exit(1)


def fetch_all_measurements(access_token):
    """Fetch all measurement groups from Withings API, handling pagination."""
    all_groups = []
    offset = 0

    while True:
        print(f"Fetching page (offset={offset})...")
        resp = requests.post(
            WITHINGS_API,
            data={
                "action": "getmeas",
                "access_token": access_token,
                "category": 1,  # real measurements only
                "startdate": 1,
                "enddate": int(time.time()),
                "offset": offset,
            },
        )
        data = resp.json()

        if data.get("status") != 0:
            print(f"API error: {data}", file=sys.stderr)
            sys.exit(1)

        groups = data["body"]["measuregrps"]
        all_groups.extend(groups)
        print(f"  Got {len(groups)} groups (total: {len(all_groups)})")

        if not data["body"].get("more", 0):
            break
        offset = data["body"].get("offset", offset + 1000)

    return all_groups


def groups_to_prometheus_lines(groups):
    """Convert Withings measurement groups to Prometheus exposition format lines."""
    lines = []

    for group in groups:
        timestamp_ms = group["date"] * 1000

        for measure in group["measures"]:
            mtype = measure["type"]
            if mtype not in MEASURE_MAP:
                continue

            metric_name, entity_id, friendly_name = MEASURE_MAP[mtype]
            value = measure["value"] * (10 ** measure["unit"])

            labels = {
                **COMMON_LABELS,
                "entity": entity_id,
                "friendly_name": friendly_name,
            }
            label_str = ",".join(f'{k}="{v}"' for k, v in sorted(labels.items()))
            line = f"{metric_name}{{{label_str}}} {value} {timestamp_ms}"
            lines.append(line)

    return lines


def import_to_vm(lines, dry_run=False):
    """Import Prometheus-format lines into VictoriaMetrics."""
    if dry_run:
        print(f"\n[DRY RUN] Would import {len(lines)} data points to {VM_IMPORT_URL}")
        print("Sample lines:")
        for line in lines[:5]:
            print(f"  {line}")
        print(f"  ...")
        for line in lines[-3:]:
            print(f"  {line}")
        return

    # VM accepts batches of prometheus lines
    batch_size = 1000
    for i in range(0, len(lines), batch_size):
        batch = lines[i : i + batch_size]
        payload = "\n".join(batch) + "\n"

        resp = requests.post(
            VM_IMPORT_URL,
            data=payload,
            headers={"Content-Type": "text/plain"},
        )

        if resp.status_code != 204:
            print(
                f"VM import error (batch {i//batch_size}): {resp.status_code} {resp.text}",
                file=sys.stderr,
            )
            sys.exit(1)

        print(f"  Imported batch {i//batch_size + 1} ({len(batch)} points)")


def main():
    parser = argparse.ArgumentParser(description="Backfill Withings data to VictoriaMetrics")
    parser.add_argument("--dry-run", action="store_true", help="Don't actually import, just show what would be done")
    args = parser.parse_args()

    print("Reading Withings token from HA config...")
    access_token = get_access_token()
    print(f"Got access token: {access_token[:8]}...")

    print("\nFetching all measurements from Withings API...")
    groups = fetch_all_measurements(access_token)

    dates = [g["date"] for g in groups]
    print(f"\nTotal: {len(groups)} measurement groups")
    print(f"Range: {datetime.fromtimestamp(min(dates))} to {datetime.fromtimestamp(max(dates))}")

    print("\nConverting to Prometheus format...")
    lines = groups_to_prometheus_lines(groups)
    print(f"Generated {len(lines)} data points")

    # Summary by metric
    metric_counts = {}
    for line in lines:
        metric = line.split("{")[0]
        metric_counts[metric] = metric_counts.get(metric, 0) + 1
    print("\nBreakdown:")
    for metric, count in sorted(metric_counts.items()):
        print(f"  {metric}: {count}")

    print(f"\nImporting to VictoriaMetrics at {VM_IMPORT_URL}...")
    import_to_vm(lines, dry_run=args.dry_run)

    print("\nDone!")


if __name__ == "__main__":
    main()
