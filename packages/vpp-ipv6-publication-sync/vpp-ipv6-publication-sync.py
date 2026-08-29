import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


PREFIX_RE = re.compile(
    r"prefix:\s*([0-9A-Fa-f:]+/\d+),\s*prefix group:\s*([^,\s]+)"
)


def vppctl(binary: str, command: str) -> str:
    result = subprocess.run(
        [binary, *shlex.split(command)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"vppctl command failed ({result.returncode}): {command}\n{result.stdout}"
        )
    return result.stdout


def delegated_prefix(output: str, group: str) -> ipaddress.IPv6Network:
    for prefix, candidate_group in PREFIX_RE.findall(output):
        if candidate_group == group:
            network = ipaddress.IPv6Network(prefix, strict=False)
            if network.prefixlen > 64:
                raise RuntimeError(
                    f"delegated prefix {network} is too small to form a /64"
                )
            if not network.network_address.is_global:
                raise RuntimeError(f"refusing non-global delegated prefix {network}")
            return network
    raise RuntimeError(f"VPP has no delegated prefix in group {group!r}")


def eui64_address(
    prefix: ipaddress.IPv6Network, subnet_id: str, interface_mac: str
) -> ipaddress.IPv6Address:
    octets = bytes(int(part, 16) for part in interface_mac.split(":"))
    if len(octets) != 6:
        raise RuntimeError(f"invalid Ethernet MAC {interface_mac!r}")

    subnet = int(subnet_id, 16)
    available_subnet_bits = 64 - prefix.prefixlen
    if subnet >= (1 << available_subnet_bits):
        raise RuntimeError(
            f"subnet ID {subnet_id!r} does not fit delegated prefix {prefix}"
        )

    iid = bytes(
        [octets[0] ^ 0x02, octets[1], octets[2], 0xFF, 0xFE, *octets[3:]]
    )
    network_value = int(prefix.network_address) | (subnet << 64)
    return ipaddress.IPv6Address(network_value | int.from_bytes(iid, "big"))


def render_rule(rule: dict[str, object]) -> str:
    rendered = f"{rule['action']} src {rule['src']} dst {rule['dst']}"
    for field in ("proto", "sport", "dport"):
        if field in rule:
            rendered += f" {field} {rule[field]}"
    if "tcpflags" in rule:
        rendered += f" tcpflags {rule['tcpflags']} mask {rule['tcpflagsMask']}"
    return rendered


def resolved_policy(policy: dict[str, object], prefix: ipaddress.IPv6Network):
    token_addresses: dict[str, str] = {}
    for publication in policy["publications"]:
        if publication["externalPort"] != publication["localPort"]:
            raise RuntimeError(
                "native IPv6 publication cannot translate ports: "
                f"{publication['group']} {publication['externalPort']} -> "
                f"{publication['localPort']}"
            )
        address = str(
            eui64_address(
                prefix,
                publication["subnetId"],
                publication["interfaceMac"],
            )
        )
        previous = token_addresses.setdefault(publication["token"], address)
        if previous != address:
            raise RuntimeError(
                f"publication token {publication['token']!r} maps to two hosts"
            )

    resolved_acls = []
    for acl in policy["acls"]:
        resolved_rules = []
        for rule in acl["rules"]:
            resolved_rule = dict(rule)
            for field in ("src", "dst"):
                value = resolved_rule[field]
                for token, address in token_addresses.items():
                    value = value.replace(token, address)
                if "@ipv6-" in value:
                    raise RuntimeError(f"unresolved IPv6 publication token in {value!r}")
                resolved_rule[field] = value
            resolved_rules.append(resolved_rule)
        resolved_acls.append({**acl, "rules": resolved_rules})
    return token_addresses, resolved_acls


def vpp_identity(socket: Path) -> str:
    stat = socket.stat()
    return f"{stat.st_dev}:{stat.st_ino}:{stat.st_ctime_ns}"


def read_state(path: Path) -> dict[str, object] | None:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def write_state(path: Path, state: dict[str, object]) -> None:
    temporary = path.with_name(f".{path.name}.{os.getpid()}.new")
    temporary.write_text(json.dumps(state, sort_keys=True) + "\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", required=True, type=Path)
    parser.add_argument("--vppctl", required=True)
    parser.add_argument("--socket", default="/run/vpp/cli.sock", type=Path)
    parser.add_argument(
        "--state", default="/run/vpp-ipv6-publication-sync.json", type=Path
    )
    args = parser.parse_args()

    policy_bytes = args.policy.read_bytes()
    policy = json.loads(policy_bytes)
    if not policy["publications"]:
        raise RuntimeError("IPv6 publication policy is empty")

    prefix = delegated_prefix(
        vppctl(args.vppctl, "show ip6 prefixes"), policy["prefixGroup"]
    )
    token_addresses, acls = resolved_policy(policy, prefix)
    desired_state = {
        "policySha256": hashlib.sha256(policy_bytes).hexdigest(),
        "vppIdentity": vpp_identity(args.socket),
        "delegatedPrefix": str(prefix),
        "addresses": token_addresses,
    }
    if read_state(args.state) == desired_state:
        print(
            "VPP IPv6 publication ACLs already match "
            + ", ".join(sorted(token_addresses.values()))
        )
        return 0

    for acl in acls:
        command = (
            f"set acl-plugin acl index {acl['index']} "
            + ", ".join(render_rule(rule) for rule in acl["rules"])
            + f" tag {acl['tag']}"
        )
        vppctl(args.vppctl, command)

    live_acls = vppctl(args.vppctl, "show acl-plugin acl")
    for acl in acls:
        if f"acl-index {acl['index']} " not in live_acls:
            raise RuntimeError(f"VPP did not retain ACL index {acl['index']}")
        if f"tag {{{acl['tag']}}}" not in live_acls:
            raise RuntimeError(f"VPP did not retain ACL tag {acl['tag']!r}")
    for address in token_addresses.values():
        if f"dst {address}/128" not in live_acls:
            raise RuntimeError(f"VPP ACL verification did not find {address}/128")

    write_state(args.state, desired_state)
    print(
        f"published {', '.join(sorted(token_addresses.values()))} from {prefix}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"vpp-ipv6-publication-sync: {error}", file=sys.stderr)
        sys.exit(1)
