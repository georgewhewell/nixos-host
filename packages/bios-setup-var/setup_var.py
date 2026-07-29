#!/usr/bin/env python3
"""bios-setup-var: map human-readable BIOS Setup questions to the exact EFI
variable + offset + value, then read or write them on a running machine.

Opaque AMI/AMD "Setup" EFI variables encode every BIOS-menu toggle as raw
bytes at fixed offsets. The offset<->meaning map lives only in the firmware's
IFR (Internal Forms Representation). This tool extracts that map from a BIOS
dump once, then uses it to get/set the live values via efivarfs -- so a
setting that is otherwise BIOS-menu-only (PCIe bifurcation, above-4G decode,
SR-IOV, ...) becomes scriptable.

Pipeline:
  build-db  ROM  -> uefiextract + ifrextractor over every module, parsed into
                    a JSON map of {question -> varstore guid/name, offset,
                    width, options}.
  list/get/set    operate on that map against /sys/firmware/efi/efivars.

get/set never guess: they read the live variable, confirm its current byte is
a value the question actually allows (the firmware-agnostic check that the
offset maps correctly on THIS machine), back the variable up, then write only
the target bytes. A mismatch aborts rather than writing blind.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

EFIVARS = "/sys/firmware/efi/efivars"

# ---- extraction ------------------------------------------------------------


def build_db(rom, uefiextract, ifrextractor, language="en-US"):
    """Extract every IFR question from a BIOS image into a flat list of dicts."""
    workdir = tempfile.mkdtemp(prefix="bios-setup-var-")
    rom_copy = os.path.join(workdir, "image.rom")
    shutil.copy(rom, rom_copy)
    # uefiextract decompresses all nested volumes into <image>.rom.dump/.
    subprocess.run([uefiextract, rom_copy, "all"],
                   cwd=workdir, check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    dump = rom_copy + ".dump"

    questions = {}
    varstores = {}
    for root, _, files in os.walk(dump):
        for fn in files:
            if fn not in ("body.bin", "unc_data.bin"):
                continue
            path = os.path.join(root, fn)
            if os.path.getsize(path) > 8 * 1024 * 1024:
                continue  # container blobs, not leaf modules
            _run_ifrextractor(path, ifrextractor, language, questions, varstores)

    return {
        "source": os.path.basename(rom),
        "varstores": varstores,
        "questions": sorted(questions.values(), key=lambda q: q["name"].lower()),
    }


def _run_ifrextractor(path, ifrextractor, language, questions, varstores):
    tmp = tempfile.mkdtemp(prefix="ifr-")
    probe = os.path.join(tmp, "m.bin")
    shutil.copy(path, probe)
    subprocess.run([ifrextractor, probe, "verbose"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for out in os.listdir(tmp):
        if out.endswith(".ifr.txt") and language in out:
            _parse_ifr(os.path.join(tmp, out), questions, varstores)
    shutil.rmtree(tmp, ignore_errors=True)


_VARSTORE_RE = re.compile(
    r'VarStore Guid: ([0-9A-Fa-f-]+), VarStoreId: (0x[0-9A-Fa-f]+), '
    r'Size: (0x[0-9A-Fa-f]+), Name: "([^"]*)"')
_Q_RE = re.compile(
    r'(OneOf|Numeric|CheckBox) Prompt: "([^"]*)",.*?'
    r'QuestionId: (0x[0-9A-Fa-f]+), VarStoreId: (0x[0-9A-Fa-f]+), '
    r'VarOffset: (0x[0-9A-Fa-f]+),.*?Size: (\d+)'
    r'(?:, Min: (0x[0-9A-Fa-f]+), Max: (0x[0-9A-Fa-f]+))?')
_OPT_RE = re.compile(r'OneOfOption Option: "([^"]*)" Value: (\d+)')


def _parse_ifr(txt, questions, varstores):
    # varstore id -> (guid, name) is scoped to one form-set (one ifr.txt).
    # The SAME id (e.g. 0x5000) names different variables in different
    # form-sets -- AmdSetupSHP vs AmdSetupSTP for different AGESA platforms --
    # so resolve each question to its variable name here, not globally by id.
    local = {}
    current = None  # the OneOf we are collecting options for
    with open(txt, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = _VARSTORE_RE.search(line)
            if m:
                guid, vid, size, name = m.groups()
                local[vid.lower()] = (guid.lower(), name)
                varstores.setdefault(f"{name}-{guid.lower()}", {
                    "guid": guid.lower(), "name": name, "size": int(size, 16)})
                continue
            m = _Q_RE.search(line)
            if m:
                kind, name, qid, vsid, off, sizebits, mn, mx = m.groups()
                vs = local.get(vsid.lower())
                if vs is None:
                    current = None
                    continue
                guid, vsname = vs
                width = max(1, int(sizebits) // 8)
                q = {
                    "name": name.strip(),
                    "kind": kind,
                    "varstore_guid": guid,
                    "varstore_name": vsname,
                    "offset": int(off, 16),
                    "width": width,
                    "min": int(mn, 16) if mn else 0,
                    "max": int(mx, 16) if mx else (1 << (8 * width)) - 1,
                    "options": [],
                }
                # Key on the storage location within a specific variable, so
                # SHP and STP stay distinct while duplicate copies of one
                # form-set merge.
                key = (guid, vsname, q["offset"], q["width"])
                current = questions.setdefault(key, q)
                continue
            m = _OPT_RE.search(line)
            if m and current is not None:
                text, value = m.group(1), int(m.group(2))
                if not any(o["value"] == value for o in current["options"]):
                    current["options"].append({"text": text, "value": value})


# ---- live variable access --------------------------------------------------


def _efivar_of(q):
    return f"{q['varstore_name']}-{q['varstore_guid']}"


def _legal(q):
    return ({o["value"] for o in q["options"]}
            if q["options"] else set(range(q["min"], q["max"] + 1)))


def _resolve(db, name, varstore=None):
    matches = [q for q in db["questions"] if q["name"] == name]
    if varstore:
        matches = [q for q in matches if q["varstore_name"] == varstore]
    if not matches:
        near = [q["name"] for q in db["questions"]
                if name.lower() in q["name"].lower()]
        hint = ("\nDid you mean: " + ", ".join(sorted(set(near))[:8])) if near else ""
        sys.exit(f"no question named {name!r}{hint}")
    if len(matches) > 1:
        # Same question defined against several platform variables (SHP/STP).
        # Pick the one whose variable exists AND currently holds a legal value
        # -- i.e. the variable the running firmware actually uses.
        live = []
        for q in matches:
            try:
                _, payload = _read_var(_efivar_of(q))
            except OSError:
                continue
            if _decode(q, payload)[0] in _legal(q):
                live.append(q)
        if len(live) == 1:
            return live[0]
        names = sorted({q["varstore_name"] for q in matches})
        sys.exit(f"{name!r} exists in {', '.join(names)}; "
                 f"disambiguate with --varstore")
    return matches[0]


def _read_var(efivar):
    with open(os.path.join(EFIVARS, efivar), "rb") as fh:
        raw = fh.read()
    return raw[:4], raw[4:]  # attributes, payload


def _decode(q, payload):
    val = int.from_bytes(payload[q["offset"]:q["offset"] + q["width"]], "little")
    label = next((o["text"] for o in q["options"] if o["value"] == val), None)
    return val, label


def cmd_get(db, name, varstore):
    q = _resolve(db, name, varstore)
    efivar = _efivar_of(q)
    _, payload = _read_var(efivar)
    val, label = _decode(q, payload)
    shown = f"{val}" + (f" ({label})" if label else "")
    print(f"{q['name']}: {shown}")
    print(f"  {efivar} @ +{hex(q['offset'])} width {q['width']}")
    if q["options"]:
        opts = ", ".join(f"{o['value']}={o['text']}" for o in q["options"])
        print(f"  options: {opts}")
    else:
        print(f"  range: {q['min']}..{q['max']}")


def cmd_set(db, name, value, varstore, dry_run):
    q = _resolve(db, name, varstore)
    efivar = _efivar_of(q)
    # Accept an option name or a number.
    target = None
    for o in q["options"]:
        if o["text"].lower() == value.lower():
            target = o["value"]
    if target is None:
        target = int(value, 0)
    if not (q["min"] <= target <= q["max"]):
        sys.exit(f"{target} out of range {q['min']}..{q['max']} for {name!r}")

    attrs, payload = _read_var(efivar)
    cur, cur_label = _decode(q, payload)

    # Confirm the offset maps correctly on THIS firmware: the current byte must
    # itself be a legal value for this question. If it is not, the DB offset is
    # wrong for this image -- refuse rather than corrupt an unrelated setting.
    if cur not in _legal(q):
        sys.exit(f"refusing: {efivar} @ +{hex(q['offset'])} currently holds "
                 f"{cur}, not a valid {name!r} value -- DB offset likely wrong "
                 f"for this firmware")

    print(f"{q['name']}: {cur}{f' ({cur_label})' if cur_label else ''} -> {target}")
    if dry_run:
        print("dry-run: no write")
        return

    backup = f"/var/tmp/{efivar}.{cur}.bak"
    old_raw = attrs + payload
    if os.path.exists(backup):
        with open(backup, "rb") as fh:
            if fh.read() != old_raw:
                sys.exit(f"refusing to overwrite mismatched backup {backup}")
        print(f"  using existing matching backup {backup}")
    else:
        with open(backup, "xb") as fh:
            fh.write(old_raw)
        print(f"  backed up to {backup}")

    new = bytearray(payload)
    new[q["offset"]:q["offset"] + q["width"]] = target.to_bytes(q["width"], "little")
    path = os.path.join(EFIVARS, efivar)
    subprocess.run(["chattr", "-i", path], check=True)
    # efivarfs requires the 4-byte attribute header and payload in one write.
    # Do not use open(..., "wb"): its O_TRUNC flag is rejected by efivarfs
    # before the write reaches the firmware.
    new_raw = attrs + bytes(new)
    fd = os.open(path, os.O_WRONLY)
    try:
        written = os.write(fd, new_raw)
    finally:
        os.close(fd)
    if written != len(new_raw):
        sys.exit(f"short efivarfs write: wrote {written} of {len(new_raw)} bytes")

    _, verify = _read_var(efivar)
    got, got_label = _decode(q, verify)
    if got != target:
        sys.exit(f"write did not stick: read back {got}")
    print(f"  set to {got}{f' ({got_label})' if got_label else ''}; reboot to apply")


def cmd_list(db, pattern):
    for q in db["questions"]:
        if pattern and pattern.lower() not in q["name"].lower():
            continue
        loc = f"{q['varstore_name']}+{hex(q['offset'])}"
        opts = ""
        if q["options"]:
            opts = "  [" + ", ".join(f"{o['value']}={o['text']}"
                                     for o in q["options"]) + "]"
        print(f"{q['name']:<40} {loc}{opts}")


# ---- cli -------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default="/var/lib/bios-setup-var/db.json",
                    help="question map produced by build-db")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build-db", help="extract the question map from a BIOS dump")
    b.add_argument("rom")
    b.add_argument("-o", "--out", required=True)
    b.add_argument("--uefiextract", default=os.environ.get("UEFIEXTRACT", "uefiextract"))
    b.add_argument("--ifrextractor",
                   default=os.environ.get("IFREXTRACTOR", "ifrextractor"))

    l = sub.add_parser("list", help="list questions (optionally filtered)")
    l.add_argument("pattern", nargs="?")

    g = sub.add_parser("get", help="read a question's live value")
    g.add_argument("name")
    g.add_argument("--varstore", help="disambiguate when the name exists in several")

    s = sub.add_parser("set", help="write a question's value in efivarfs")
    s.add_argument("name")
    s.add_argument("value", help="an option name or a number")
    s.add_argument("--varstore", help="disambiguate when the name exists in several")
    s.add_argument("--dry-run", action="store_true")

    args = ap.parse_args()

    if args.cmd == "build-db":
        db = build_db(args.rom, args.uefiextract, args.ifrextractor)
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w") as fh:
            json.dump(db, fh, indent=2)
        print(f"{len(db['questions'])} questions, "
              f"{len(db['varstores'])} varstores -> {args.out}")
        return

    with open(args.db) as fh:
        db = json.load(fh)
    if args.cmd == "list":
        cmd_list(db, args.pattern)
    elif args.cmd == "get":
        cmd_get(db, args.name, args.varstore)
    elif args.cmd == "set":
        cmd_set(db, args.name, args.value, args.varstore, args.dry_run)


if __name__ == "__main__":
    main()
