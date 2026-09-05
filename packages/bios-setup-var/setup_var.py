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
import datetime
import hashlib
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import tempfile

EFIVARS = os.environ.get("BIOS_SETUP_VAR_EFIVARS",
                         "/sys/firmware/efi/efivars")

# ---- extraction ------------------------------------------------------------


def build_db(rom, uefiextract, ifrextractor, work_root, language="en-US"):
    """Extract every IFR question from a BIOS image into a flat list of dicts."""
    os.makedirs(work_root, exist_ok=True)
    workdir = tempfile.mkdtemp(prefix="bios-setup-var-", dir=work_root)
    try:
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
                _run_ifrextractor(path, ifrextractor, work_root, language,
                                  questions, varstores)

        return {
            "source": os.path.basename(rom),
            "varstores": varstores,
            "questions": sorted(questions.values(), key=lambda q: q["name"].lower()),
        }
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def _run_ifrextractor(path, ifrextractor, work_root, language, questions, varstores):
    tmp = tempfile.mkdtemp(prefix="ifr-", dir=work_root)
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
                # Key on both storage and the decoded name. Several FAEX9
                # modules reuse Setup offsets and some pair an IFR package
                # with the wrong HII string package, producing plausible but
                # unrelated English labels. Keeping distinct labels preserves
                # the correctly paired Setup form (and lets exact-name lookup
                # select it) while still merging true duplicate copies.
                key = (guid, vsname, q["offset"], q["width"], q["name"])
                existing = questions.get(key)
                if existing is None:
                    questions[key] = q
                    current = q
                else:
                    current = existing
                continue
            m = _OPT_RE.search(line)
            if m and current is not None:
                text, value = m.group(1), int(m.group(2))
                if not any(o["value"] == value for o in current["options"]):
                    current["options"].append({"text": text, "value": value})


# ---- live variable access --------------------------------------------------


def _efivar_of(q):
    return f"{q['varstore_name']}-{q['varstore_guid']}"


def _is_legal(q, value):
    if q["options"]:
        return any(option["value"] == value for option in q["options"])
    return q["min"] <= value <= q["max"]


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
            if _is_legal(q, _decode(q, payload)[0]):
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


def _resolve_efivar_name(name):
    exact = os.path.join(EFIVARS, name)
    if os.path.isfile(exact):
        return name
    matches = sorted(fn for fn in os.listdir(EFIVARS)
                     if fn.startswith(name + "-") and
                     os.path.isfile(os.path.join(EFIVARS, fn)))
    if not matches:
        sys.exit(f"no live EFI variable named {name!r}")
    if len(matches) > 1:
        sys.exit(f"{name!r} matches {', '.join(matches)}; use the full name")
    return matches[0]


def _read_raw_value(efivar, payload, offset, width):
    end = offset + width
    if offset < 0 or width < 1 or end > len(payload):
        sys.exit(f"{efivar} payload is {len(payload)} bytes; "
                 f"+{hex(offset)} width {width} is out of bounds")
    return int.from_bytes(payload[offset:end], "little")


def _backup(efivar, raw, backup_dir):
    os.makedirs(backup_dir, mode=0o700, exist_ok=True)
    digest = hashlib.sha256(raw).hexdigest()[:16]
    backup = os.path.join(backup_dir, f"{efivar}.{digest}.bak")
    if os.path.exists(backup):
        with open(backup, "rb") as fh:
            if fh.read() != raw:
                sys.exit(f"refusing to use mismatched backup {backup}")
        print(f"  using existing matching backup {backup}")
    else:
        with open(backup, "xb") as fh:
            fh.write(raw)
        print(f"  backed up to {backup}")


def _write_payload(efivar, attrs, payload, new_payload):
    path = os.path.join(EFIVARS, efivar)
    subprocess.run(["chattr", "-i", path], check=True)
    # efivarfs requires the 4-byte attribute header and payload in one write.
    # Do not use open(..., "wb"): its O_TRUNC flag is rejected by efivarfs
    # before the write reaches the firmware.
    new_raw = attrs + bytes(new_payload)
    fd = os.open(path, os.O_WRONLY)
    try:
        written = os.write(fd, new_raw)
    finally:
        os.close(fd)
    if written != len(new_raw):
        sys.exit(f"short efivarfs write: wrote {written} of {len(new_raw)} bytes")


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


def cmd_set(db, name, value, varstore, dry_run, backup_dir):
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
    if not _is_legal(q, cur):
        sys.exit(f"refusing: {efivar} @ +{hex(q['offset'])} currently holds "
                 f"{cur}, not a valid {name!r} value -- DB offset likely wrong "
                 f"for this firmware")

    print(f"{q['name']}: {cur}{f' ({cur_label})' if cur_label else ''} -> {target}")
    if dry_run:
        print("dry-run: no write")
        return

    old_raw = attrs + payload
    _backup(efivar, old_raw, backup_dir)

    new = bytearray(payload)
    new[q["offset"]:q["offset"] + q["width"]] = target.to_bytes(q["width"], "little")
    _write_payload(efivar, attrs, payload, new)

    _, verify = _read_var(efivar)
    got, got_label = _decode(q, verify)
    if got != target:
        sys.exit(f"write did not stick: read back {got}")
    print(f"  set to {got}{f' ({got_label})' if got_label else ''}; reboot to apply")


def cmd_raw_get(varstore, offset, width):
    efivar = _resolve_efivar_name(varstore)
    _, payload = _read_var(efivar)
    value = _read_raw_value(efivar, payload, offset, width)
    encoded = payload[offset:offset + width].hex(" ")
    print(f"{efivar} @ +{hex(offset)} width {width}: {value} ({hex(value)})")
    print(f"  little-endian bytes: {encoded}")


def cmd_raw_set(varstore, offset, value, width, expect, dry_run, backup_dir):
    efivar = _resolve_efivar_name(varstore)
    attrs, payload = _read_var(efivar)
    current = _read_raw_value(efivar, payload, offset, width)
    maximum = (1 << (width * 8)) - 1
    if not (0 <= value <= maximum):
        sys.exit(f"{value} does not fit in {width} byte(s)")
    if not (0 <= expect <= maximum):
        sys.exit(f"expected value {expect} does not fit in {width} byte(s)")
    if current != expect:
        sys.exit(f"refusing: {efivar} @ +{hex(offset)} currently holds "
                 f"{current} ({hex(current)}), expected {expect} ({hex(expect)})")

    print(f"{efivar} @ +{hex(offset)} width {width}: {current} -> {value}")
    if dry_run:
        print("dry-run: no write")
        return

    _backup(efivar, attrs + payload, backup_dir)
    new = bytearray(payload)
    new[offset:offset + width] = value.to_bytes(width, "little")
    _write_payload(efivar, attrs, payload, new)
    _, verify = _read_var(efivar)
    got = _read_raw_value(efivar, verify, offset, width)
    if got != value:
        sys.exit(f"write did not stick: read back {got}")
    print(f"  set to {got} ({hex(got)}); reboot to apply")


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


# ---- complete read-only snapshots -----------------------------------------


_GUID_SUFFIX_RE = re.compile(
    r"^(.*)-([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})$")


def _read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().strip()
    except OSError:
        return None


def _snapshot_metadata():
    dmi_root = "/sys/class/dmi/id"
    dmi_fields = [
        "bios_date",
        "bios_vendor",
        "bios_version",
        "board_name",
        "board_vendor",
        "board_version",
        "product_name",
        "product_version",
        "sys_vendor",
    ]
    return {
        "format_version": 1,
        "captured_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "hostname": socket.gethostname(),
        "boot_id": _read_text("/proc/sys/kernel/random/boot_id"),
        "kernel_release": platform.release(),
        "kernel_command_line": _read_text("/proc/cmdline"),
        "dmi": {
            field: value
            for field in dmi_fields
            if (value := _read_text(os.path.join(dmi_root, field))) is not None
        },
    }


def _decoded_snapshot(db, raw_by_name):
    decoded = []
    for q in db.get("questions", []):
        efivar = _efivar_of(q)
        raw = raw_by_name.get(efivar)
        if raw is None or len(raw) < 4:
            continue
        payload = raw[4:]
        start = q["offset"]
        end = start + q["width"]
        if start < 0 or end > len(payload):
            continue
        value, label = _decode(q, payload)
        decoded.append({
            "name": q["name"],
            "kind": q["kind"],
            "efivar": efivar,
            "offset": start,
            "width": q["width"],
            "value": value,
            "label": label,
            "legal": _is_legal(q, value),
        })
    return sorted(decoded, key=lambda item: (
        item["efivar"], item["offset"], item["width"], item["name"]))


def cmd_snapshot(out, db_path):
    """Copy every readable efivar and an index without changing efivarfs."""
    if not os.path.isdir(EFIVARS):
        sys.exit(f"efivarfs is not mounted at {EFIVARS}")

    out = os.path.abspath(out)
    parent = os.path.dirname(out)
    os.makedirs(parent, mode=0o700, exist_ok=True)
    if os.path.exists(out):
        sys.exit(f"refusing to replace existing snapshot {out}")

    partial = tempfile.mkdtemp(prefix=f".{os.path.basename(out)}.partial-",
                               dir=parent)
    os.chmod(partial, 0o700)
    raw_dir = os.path.join(partial, "efivars")
    os.mkdir(raw_dir, mode=0o700)

    manifest = _snapshot_metadata()
    manifest["efivarfs"] = EFIVARS
    manifest["variables"] = []
    manifest["read_errors"] = []
    raw_by_name = {}
    try:
        for filename in sorted(os.listdir(EFIVARS)):
            source = os.path.join(EFIVARS, filename)
            if not os.path.isfile(source):
                continue
            try:
                with open(source, "rb") as fh:
                    raw = fh.read()
            except OSError as exc:
                manifest["read_errors"].append({
                    "efivar": filename,
                    "error": f"{exc.__class__.__name__}: {exc}",
                })
                continue

            destination = os.path.join(raw_dir, filename)
            fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                         0o600)
            try:
                view = memoryview(raw)
                written = 0
                while written < len(raw):
                    count = os.write(fd, view[written:])
                    if count == 0:
                        raise OSError(f"zero-length snapshot write for {filename}")
                    written += count
            finally:
                os.close(fd)
            if written != len(raw):
                raise OSError(f"short snapshot write for {filename}: "
                              f"{written} of {len(raw)} bytes")

            match = _GUID_SUFFIX_RE.match(filename)
            attrs = int.from_bytes(raw[:4], "little") if len(raw) >= 4 else None
            entry = {
                "efivar": filename,
                "name": match.group(1) if match else None,
                "guid": match.group(2).lower() if match else None,
                "size": len(raw),
                "payload_size": max(0, len(raw) - 4),
                "attributes": attrs,
                "attributes_hex": f"0x{attrs:08x}" if attrs is not None else None,
                "sha256": hashlib.sha256(raw).hexdigest(),
                "payload_sha256": hashlib.sha256(raw[4:]).hexdigest()
                if len(raw) >= 4 else None,
            }
            manifest["variables"].append(entry)
            raw_by_name[filename] = raw

        manifest["variable_count"] = len(manifest["variables"])
        manifest["read_error_count"] = len(manifest["read_errors"])
        manifest["database"] = None

        if db_path and os.path.isfile(db_path):
            with open(db_path, encoding="utf-8") as fh:
                db = json.load(fh)
            decoded = _decoded_snapshot(db, raw_by_name)
            decoded_path = os.path.join(partial, "decoded.json")
            with open(decoded_path, "x", encoding="utf-8") as fh:
                json.dump(decoded, fh, indent=2, sort_keys=True)
                fh.write("\n")
            os.chmod(decoded_path, 0o600)
            manifest["database"] = os.path.abspath(db_path)
            manifest["decoded_question_count"] = len(decoded)

        manifest_path = os.path.join(partial, "manifest.json")
        with open(manifest_path, "x", encoding="utf-8") as fh:
            json.dump(manifest, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.chmod(manifest_path, 0o600)

        os.rename(partial, out)
        print(f"{manifest['variable_count']} EFI variables -> {out}")
        if manifest["read_error_count"]:
            print(f"warning: {manifest['read_error_count']} variables could not "
                  "be read; see manifest.json", file=sys.stderr)
    except BaseException:
        shutil.rmtree(partial, ignore_errors=True)
        raise


def _snapshot_raw(snapshot):
    raw_dir = os.path.join(snapshot, "efivars")
    if not os.path.isdir(raw_dir):
        # Compatibility with the original hand-copied Strix snapshots, whose
        # efivarfs files live directly in the named directory.
        raw_dir = snapshot
    if not os.path.isdir(raw_dir):
        sys.exit(f"snapshot directory does not exist: {snapshot}")
    result = {}
    for filename in sorted(os.listdir(raw_dir)):
        if not _GUID_SUFFIX_RE.match(filename):
            continue
        source = os.path.join(raw_dir, filename)
        if not os.path.isfile(source):
            continue
        with open(source, "rb") as fh:
            result[filename] = fh.read()
    if not result:
        sys.exit(f"no EFI variable files found in {snapshot}")
    return result


def _changed_ranges(before, after):
    changed = [
        offset
        for offset in range(max(len(before), len(after)))
        if (before[offset:offset + 1] if offset < len(before) else None)
        != (after[offset:offset + 1] if offset < len(after) else None)
    ]
    ranges = []
    if not changed:
        return ranges
    start = previous = changed[0]
    for offset in changed[1:] + [None]:
        if offset is not None and offset == previous + 1:
            previous = offset
            continue
        end = previous + 1
        ranges.append({
            "offset": start,
            "length": end - start,
            "before_hex": before[start:end].hex(),
            "after_hex": after[start:end].hex(),
        })
        if offset is not None:
            start = previous = offset
    return ranges


def cmd_snapshot_diff(before_dir, after_dir, json_output):
    before = _snapshot_raw(os.path.abspath(before_dir))
    after = _snapshot_raw(os.path.abspath(after_dir))
    before_names = set(before)
    after_names = set(after)
    report = {
        "before": os.path.abspath(before_dir),
        "after": os.path.abspath(after_dir),
        "added": sorted(after_names - before_names),
        "removed": sorted(before_names - after_names),
        "changed": [],
    }
    for filename in sorted(before_names & after_names):
        old_raw = before[filename]
        new_raw = after[filename]
        if old_raw == new_raw:
            continue
        old_attrs = old_raw[:4]
        new_attrs = new_raw[:4]
        report["changed"].append({
            "efivar": filename,
            "attributes_before": int.from_bytes(old_attrs, "little")
            if len(old_attrs) == 4 else None,
            "attributes_after": int.from_bytes(new_attrs, "little")
            if len(new_attrs) == 4 else None,
            "payload_size_before": max(0, len(old_raw) - 4),
            "payload_size_after": max(0, len(new_raw) - 4),
            # Offsets are relative to the EFI payload, deliberately excluding
            # efivarfs's four-byte attribute header like raw-get/raw-set.
            "payload_changes": _changed_ranges(old_raw[4:], new_raw[4:]),
        })

    if json_output:
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        print()
        return

    print(f"added {len(report['added'])}, removed {len(report['removed'])}, "
          f"changed {len(report['changed'])}")
    for filename in report["added"]:
        print(f"+ {filename}")
    for filename in report["removed"]:
        print(f"- {filename}")
    for variable in report["changed"]:
        print(f"~ {variable['efivar']} "
              f"({variable['payload_size_before']} -> "
              f"{variable['payload_size_after']} payload bytes)")
        if variable["attributes_before"] != variable["attributes_after"]:
            print(f"    attributes: {variable['attributes_before']} -> "
                  f"{variable['attributes_after']}")
        for change in variable["payload_changes"]:
            print(f"    +{hex(change['offset'])} [{change['length']}]: "
                  f"{change['before_hex'] or '<absent>'} -> "
                  f"{change['after_hex'] or '<absent>'}")


# ---- cli -------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default="/var/lib/bios-setup-var/db.json",
                    help="question map produced by build-db")
    ap.add_argument("--backup-dir", default="/var/lib/bios-setup-var/backups",
                    help="persistent directory for full-variable backups")
    sub = ap.add_subparsers(dest="cmd", required=True)

    b = sub.add_parser("build-db", help="extract the question map from a BIOS dump")
    b.add_argument("rom")
    b.add_argument("-o", "--out", required=True)
    b.add_argument("--uefiextract", default=os.environ.get("UEFIEXTRACT", "uefiextract"))
    b.add_argument("--ifrextractor",
                   default=os.environ.get("IFREXTRACTOR", "ifrextractor"))
    b.add_argument("--work-dir",
                   help="scratch parent (default: .work beside --out)")

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

    rg = sub.add_parser("raw-get", help="read exact bytes without an IFR map")
    rg.add_argument("varstore", help="variable name or full name-with-GUID")
    rg.add_argument("offset", type=lambda v: int(v, 0))
    rg.add_argument("--width", type=int, default=1)

    rs = sub.add_parser("raw-set", help="write exact bytes with a required precondition")
    rs.add_argument("varstore", help="variable name or full name-with-GUID")
    rs.add_argument("offset", type=lambda v: int(v, 0))
    rs.add_argument("value", type=lambda v: int(v, 0))
    rs.add_argument("--width", type=int, default=1)
    rs.add_argument("--expect", required=True, type=lambda v: int(v, 0),
                    help="required current value; mismatch refuses the write")
    rs.add_argument("--dry-run", action="store_true")

    snap = sub.add_parser(
        "snapshot",
        help="copy every readable EFI variable and a hash/metadata index")
    snap.add_argument("out", help="new output directory (never overwritten)")

    diff = sub.add_parser(
        "snapshot-diff",
        help="show variables and payload offsets changed between two snapshots")
    diff.add_argument("before")
    diff.add_argument("after")
    diff.add_argument("--json", action="store_true", help="emit machine-readable JSON")

    args = ap.parse_args()

    if args.cmd == "build-db":
        out_dir = os.path.dirname(os.path.abspath(args.out))
        work_root = args.work_dir or os.path.join(out_dir, ".work")
        db = build_db(args.rom, args.uefiextract, args.ifrextractor, work_root)
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "w") as fh:
            json.dump(db, fh, indent=2)
        print(f"{len(db['questions'])} questions, "
              f"{len(db['varstores'])} varstores -> {args.out}")
        return

    if args.cmd == "raw-get":
        cmd_raw_get(args.varstore, args.offset, args.width)
        return
    if args.cmd == "raw-set":
        cmd_raw_set(args.varstore, args.offset, args.value, args.width,
                    args.expect, args.dry_run, args.backup_dir)
        return
    if args.cmd == "snapshot":
        cmd_snapshot(args.out, args.db)
        return
    if args.cmd == "snapshot-diff":
        cmd_snapshot_diff(args.before, args.after, args.json)
        return

    with open(args.db) as fh:
        db = json.load(fh)
    if args.cmd == "list":
        cmd_list(db, args.pattern)
    elif args.cmd == "get":
        cmd_get(db, args.name, args.varstore)
    elif args.cmd == "set":
        cmd_set(db, args.name, args.value, args.varstore, args.dry_run,
                args.backup_dir)


if __name__ == "__main__":
    main()
