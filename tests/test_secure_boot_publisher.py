"""Real PE signatures: payload matching, tamper rejection and atomic selection."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

publisher, stub = sys.argv[1:]
root = Path.cwd()


def run(*args, ok=True):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if (result.returncode == 0) != ok:
        raise AssertionError(result.stdout)
    return result


for name in ("owner", "other"):
    run("openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", f"{name}.key", "-out", f"{name}.pem", "-subj", f"/CN={name}", "-days", "1")

bundle = root / "bundle"
bundle.mkdir()
(root / "kernel").write_bytes(b"test kernel payload")
(root / "initrd").write_bytes(b"test initrd payload")
(root / "cmdline").write_bytes(b"init=/nix/store/test/init\0")
run("objcopy", "--add-section", ".linux=kernel", "--add-section", ".initrd=initrd",
    "--add-section", ".cmdline=cmdline", stub, str(bundle / "boot.efi"))


def manifest(cmdline="init=/nix/store/test/init"):
    (bundle / "manifest.json").write_text(json.dumps({
        "schema": 1, "host": "strix-1", "system": "/nix/store/test",
        "sha256": hashlib.sha256((bundle / "boot.efi").read_bytes()).hexdigest(),
        "cmdline": cmdline, "verifiedRuntime": False,
    }))


def publish(key="owner.key", ok=True):
    return run(sys.executable, publisher, "--bundle", str(bundle), "--state", str(root / "state"),
               "--key", str(root / key), "--certificate", str(root / "owner.pem"), ok=ok)


manifest()
publish()
current = root / "state/strix-1/current"
original = current.resolve()
signed = (current / "boot.efi").read_bytes()
# Reuse checks the retained bytes against the unsigned request; no signing key needed.
publish("absent.key")
assert (current / "boot.efi").read_bytes() == signed

# A corrupted retained generation must fail without replacing either bytes or selection.
with (current / "boot.efi").open("r+b") as stream:
    contents = stream.read()
    offset = contents.index(b"test kernel payload")
    stream.seek(offset)
    stream.write(b"X")
publish(ok=False)
assert current.resolve() == original
(current / "boot.efi").write_bytes(signed)

# A changed request signed with the wrong key fails without changing current.
(root / "kernel").write_bytes(b"a different kernel payload")
run("objcopy", "--update-section", ".linux=kernel", str(bundle / "boot.efi"))
manifest()
publish("other.key", ok=False)
assert current.resolve() == original

# A sidecar cannot substitute an unsigned command line.
manifest("init=/attacker")
publish(ok=False)
assert current.resolve() == original
manifest()
publish()
assert current.resolve() != original and original.is_dir()
print("Secure Boot publisher: signing, reuse, tamper rejection, command line and atomicity passed")
