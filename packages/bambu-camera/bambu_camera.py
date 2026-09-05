#!/usr/bin/env python3
"""Stream the chamber camera of a LAN-mode Bambu Lab printer to stdout as MJPEG.

The X1 series serves plain RTSP on :322. The A1, A1 mini and P1 series do not:
they expose the chamber image over a bespoke framed protocol on TCP :6000,
guarded by TLS with the printer's own BBL-signed certificate. A client sends an
80-byte auth record and then reads a sequence of (16-byte header, JPEG) frames.

Writing those JPEGs back-to-back on stdout is exactly what go2rtc's `exec:`
pipe source wants: it peeks the first bytes, sees the SOI marker FF D8 and
opens the stream as MJPEG (pkg/magic/producer.go). So no ffmpeg is needed in
between, and go2rtc only spawns this - and so only touches the printer - once
something actually asks to watch.
"""

import argparse
import os
import socket
import ssl
import struct
import sys

# The printer holds the socket open with no traffic between frames, so a
# generous read timeout is normal operation rather than a stall: an A1 mini
# emits a frame roughly every two seconds. (Two concurrent clients were
# measured streaming at full rate simultaneously, so this need not serialise.)
READ_TIMEOUT = 30
CONNECT_TIMEOUT = 10

HEADER_LEN = 16
JPEG_SOI = b"\xff\xd8"
JPEG_EOI = b"\xff\xd9"

# Guards against a desynchronised stream turning a bogus length into a
# multi-gigabyte allocation. Chamber frames are 1280x720 JPEGs, tens of KB.
MAX_FRAME = 8 << 20


def auth_packet(username: str, access_code: str) -> bytes:
    """The 80-byte record the printer expects before it will send anything."""
    if len(username) > 32 or len(access_code) > 32:
        raise ValueError("username and access code must each be <= 32 bytes")
    return (
        struct.pack("<IIII", 0x40, 0x3000, 0, 0)
        + username.encode("ascii").ljust(32, b"\x00")
        + access_code.encode("ascii").ljust(32, b"\x00")
    )


def connect(host: str, port: int) -> ssl.SSLSocket:
    # The certificate is signed by BBL's own CA and carries the serial number
    # as its CN, so neither the chain nor the hostname can be verified against
    # anything we have. The access code is the actual authentication here.
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    sock = socket.create_connection((host, port), timeout=CONNECT_TIMEOUT)
    tls = ctx.wrap_socket(sock, server_hostname=host)
    tls.settimeout(READ_TIMEOUT)
    return tls


def read_exactly(sock: ssl.SSLSocket, count: int) -> bytes:
    buf = bytearray()
    while len(buf) < count:
        chunk = sock.recv(count - len(buf))
        if not chunk:
            raise EOFError("printer closed the connection")
        buf += chunk
    return bytes(buf)


def stream(sock: ssl.SSLSocket, out) -> None:
    while True:
        header = read_exactly(sock, HEADER_LEN)
        size = struct.unpack("<I", header[:4])[0]
        if not 0 < size <= MAX_FRAME:
            raise ValueError(f"implausible frame length {size}; stream desynced")

        frame = read_exactly(sock, size)
        if not (frame.startswith(JPEG_SOI) and frame.endswith(JPEG_EOI)):
            raise ValueError("frame is not a complete JPEG; stream desynced")

        out.write(frame)
        out.flush()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("host", help="printer hostname or IP")
    parser.add_argument("--port", type=int, default=6000)
    parser.add_argument("--username", default="bblp")
    parser.add_argument(
        "--access-code-file",
        help="file holding the LAN access code; overrides BAMBU_ACCESS_CODE",
    )
    args = parser.parse_args()

    if args.access_code_file:
        with open(args.access_code_file) as fh:
            access_code = fh.read().strip()
    else:
        access_code = os.environ.get("BAMBU_ACCESS_CODE", "").strip()

    if not access_code:
        parser.error("no access code: pass --access-code-file or set BAMBU_ACCESS_CODE")

    sock = connect(args.host, args.port)
    try:
        sock.sendall(auth_packet(args.username, access_code))
        stream(sock, sys.stdout.buffer)
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BrokenPipeError, KeyboardInterrupt):
        # go2rtc closes the pipe when the last consumer leaves. Not an error -
        # but Python flushes stdout again at interpreter exit, which would raise
        # a second BrokenPipeError straight into go2rtc's log. Redirect the fd
        # to devnull so that final flush lands somewhere harmless (the recipe
        # from the Python docs, signal.SIGPIPE notes).
        devnull = os.open(os.devnull, os.O_WRONLY)
        os.dup2(devnull, sys.stdout.fileno())
        sys.exit(0)
    except (OSError, EOFError, ValueError) as err:
        # Exit rather than reconnect in-process: go2rtc owns the lifecycle and
        # respawns this on the next viewer request.
        print(f"bambu-camera: {err}", file=sys.stderr)
        sys.exit(1)
