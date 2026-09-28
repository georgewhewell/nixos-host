#!/usr/bin/env python3
"""Sign a UKI and atomically publish it; private keys remain outside Nix."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def run(*args):
    subprocess.run(args, check=True)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_payload(signed, unsigned, certificate, directory):
    run("sbverify", "--cert", str(certificate), str(signed))
    signature = directory / "detached.pk7"
    run("sbattach", "--detach", str(signature), str(signed))
    try:
        run("sbverify", "--cert", str(certificate), "--detached", str(signature), str(unsigned))
    finally:
        signature.unlink(missing_ok=True)


def publish(args):
    bundle = args.bundle.resolve(strict=True)
    manifest = json.loads((bundle / "manifest.json").read_text())
    host = manifest["host"]
    if not re.fullmatch(r"strix-[1-4]", host):
        raise ValueError("invalid host identity")
    unsigned = bundle / "boot.efi"
    if digest(unsigned) != manifest["sha256"]:
        raise ValueError("UKI does not match its build manifest")
    certificate_der = subprocess.check_output([
        "openssl", "x509", "-in", str(args.certificate), "-outform", "DER"
    ])
    cert_hash = hashlib.sha256(certificate_der).hexdigest()
    generation = hashlib.sha256((manifest["sha256"] + cert_hash).encode()).hexdigest()
    host_dir = args.state / host
    generations = host_dir / "generations"
    generations.mkdir(parents=True, exist_ok=True, mode=0o755)
    destination = generations / generation
    with tempfile.TemporaryDirectory(prefix=".publish-", dir=host_dir) as temporary:
        staging = Path(temporary)
        # Check the signed payload contract, not just a sidecar's claims.
        inspected = staging / "inspected.efi"
        run("objcopy", "--dump-section", f".cmdline={staging / 'cmdline'}",
            "--dump-section", f".linux={staging / 'linux'}",
            "--dump-section", f".initrd={staging / 'initrd'}", str(unsigned), str(inspected))
        inspected.unlink()
        for section in ("cmdline", "linux", "initrd"):
            extracted = staging / section
            if not extracted.is_file() or extracted.stat().st_size == 0:
                raise ValueError(f"UKI is missing .{section}")
            if section == "cmdline" and extracted.read_bytes().rstrip(b"\0") != manifest["cmdline"].encode():
                raise ValueError("UKI command line does not match its build manifest")
            extracted.unlink()
        if destination.exists():
            verify_payload(destination / "boot.efi", unsigned, args.certificate, staging)
            if json.loads((destination / "manifest.json").read_text())["unsignedSha256"] != manifest["sha256"]:
                raise ValueError("existing generation identity does not match")
        else:
            signed = staging / "boot.efi"
            run("sbsign", "--key", str(args.key), "--cert", str(args.certificate),
                "--output", str(signed), str(unsigned))
            verify_payload(signed, unsigned, args.certificate, staging)
            manifest["unsignedSha256"] = manifest.pop("sha256")
            manifest["signedSha256"] = digest(signed)
            manifest["certificateSha256"] = cert_hash
            (staging / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
            (staging / "cmdline").write_text(manifest["cmdline"])
            for path in staging.iterdir():
                path.chmod(0o644)
            staging.chmod(0o755)
            os.rename(staging, destination)
            # TemporaryDirectory can clean up its now-empty original name.
            staging.mkdir()
        selection = host_dir / (".current-" + str(os.getpid()))
        try:
            selection.symlink_to(Path("generations") / generation)
            os.replace(selection, host_dir / "current")
        finally:
            selection.unlink(missing_ok=True)
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("bundle", "state", "key", "certificate"):
        parser.add_argument("--" + name, required=True, type=Path)
    publish(parser.parse_args())
