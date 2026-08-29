{pkgs}:
pkgs.writeTextFile {
  name = "vpp-prometheus-exporter";
  executable = true;
  destination = "/bin/vpp-prometheus-exporter";
  text = ''
    #!${pkgs.python3}/bin/python3
    """Small, bounded VPP statseg exporter.

    vpp_prometheus_export from the 26.06 package was tested against the live
    BlueField statseg and faults in stat_segment_connect_r before it binds.
    This process uses the supported vpp_get_stats client instead, reconnecting
    on every scrape so a VPP restart does not require an exporter restart.
    """
    import http.server
    import os
    import re
    import socket
    import subprocess

    SOCKET = os.environ.get("VPP_STATS_SOCKET", "/run/vpp/stats.sock")
    VPP_GET_STATS = os.environ.get("VPP_GET_STATS", "vpp_get_stats")
    ETHTOOL = os.environ.get("ETHTOOL", "ethtool")
    PORT = int(os.environ.get("VPP_EXPORTER_PORT", "9482"))
    # These are regular expressions consumed by VPP's stat_segment_ls().
    SUMMARY_PATTERNS = [
        r"^/if/rx$", r"^/if/tx$", r"^/if/drops$", r"^/if/rx-no-buf$",
        r"^/if/rx-miss$", r"^/if/rx-error$", r"^/if/tx-error$", r"^/if/names$",
        r"^/buffer-pools/[^/][^/]*/cached$", r"^/buffer-pools/[^/][^/]*/used$",
        r"^/buffer-pools/[^/][^/]*/available$", r"^/mem/stat segment/used$",
        r"^/mem/stat segment/total$", r"^/mem/stat segment/free$",
        r"^/mem/main heap/used$", r"^/mem/main heap/total$", r"^/mem/main heap/free$",
        r"^/sys/num_worker_threads$", r"^/sys/vector_rate$", r"^/sys/input_rate$",
        r"^/nat44-ed/total-sessions$", r"^/nat44-ed/max-cfg-sessions$",
        r"^/nat44-ed/hairpinning$", r"^/nat44-ed/in2out/.*$", r"^/nat44-ed/out2in/.*$",
        r"^/err/ip4-rx-urpf-strict/.*$", r"^/err/ip4-rx-urpf-loose/.*$",
        r"^/err/ip4-tx-urpf-strict/.*$", r"^/err/ip4-tx-urpf-loose/.*$",
        r"^/err/ip6-rx-urpf-strict/.*$", r"^/err/ip6-rx-urpf-loose/.*$",
        r"^/err/ip6-tx-urpf-strict/.*$", r"^/err/ip6-tx-urpf-loose/.*$",
        r"^/err/nat44-ed-in2out.*$", r"^/err/nat44-ed-out2in.*$",
        r"^/err/acl-plugin-in-ip4-fa/ACL deny packets$",
        r"^/err/acl-plugin-out-ip4-fa/ACL deny packets$",
        r"^/err/acl-plugin-in-ip6-fa/ACL deny packets$",
        r"^/err/acl-plugin-out-ip6-fa/ACL deny packets$",
        r"^/err/acl-plugin-in-ip4-fa/too many sessions to add new$",
        r"^/err/acl-plugin-out-ip4-fa/too many sessions to add new$",
        r"^/err/acl-plugin-in-ip6-fa/too many sessions to add new$",
        r"^/err/acl-plugin-out-ip6-fa/too many sessions to add new$",
    ]
    WORKER_PATTERNS = [r"^/sys/vector_rate_per_worker$", r"^/sys/loops_per_worker$"]
    IFACE = {}
    EMITTED_TYPES = set()

    def run_stats(patterns, summary=True):
        args = [VPP_GET_STATS, "socket-name", SOCKET, "dump", "machine"]
        if summary:
            args.append("summary")
        args += patterns
        return subprocess.run(args, check=True, capture_output=True,
                              text=True, timeout=8).stdout.splitlines()

    def esc(value):
        return str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

    def metric_name(path):
        return "vpp_" + re.sub(r"[^a-zA-Z0-9_]", "_", path.strip("/")).lower()

    def emit(name, value, labels=None, kind="counter"):
        type_line = ""
        if name not in EMITTED_TYPES:
            EMITTED_TYPES.add(name)
            type_line = "# TYPE %s %s\n" % (name, kind)
        labels = labels or {}
        label_text = "" if not labels else "{" + ",".join(
            '%s="%s"' % (k, esc(v)) for k, v in sorted(labels.items())) + "}"
        return type_line + "%s%s %s\n" % (name, label_text, value)

    def scrape():
        global IFACE, EMITTED_TYPES
        EMITTED_TYPES = set()
        lines = run_stats(SUMMARY_PATTERNS)
        workers = run_stats(WORKER_PATTERNS, summary=False)
        out = ["# HELP vpp_exporter_up Whether the VPP statseg scrape succeeded.\n",
               "# TYPE vpp_exporter_up gauge\n", "vpp_exporter_up 1\n"]
        names = {}
        for line in lines:
            fields = line.split(":", 3)
            if len(fields) == 4 and fields[0] == "4":
                names[fields[1]] = fields[2]
        IFACE = names
        nat_sessions = 0.0
        nat_capacity_per_worker = 0.0
        nat_worker_count = 0.0
        nat_counters = {}
        error_counters = {}
        # vpp_get_stats machine format: type:index:value:name (simple),
        # type:index:packets:bytes:name (combined), or type:value:name (scalar).
        for line in lines:
            fields = line.split(":")
            if not fields:
                continue
            typ = fields[0]
            if typ == "9" and len(fields) >= 3:
                path, value = ":".join(fields[2:]), fields[1]
                if path.startswith("/buffer-pools/"):
                    out.append(emit(metric_name(path), value, {"pool": path.split("/")[2]}, "gauge"))
                elif path.startswith("/sys/"):
                    out.append(emit(metric_name(path), value, kind="gauge"))
                    if path == "/sys/num_worker_threads":
                        nat_worker_count = float(value)
                elif path == "/nat44-ed/max-cfg-sessions":
                    nat_capacity_per_worker = float(value)
            elif typ == "2" and len(fields) >= 4:
                index, value, path = fields[1], fields[2], ":".join(fields[3:])
                if path == "/nat44-ed/total-sessions":
                    nat_sessions += float(value)
                elif path.startswith("/if/") and path.rsplit("/", 1)[-1] in ("drops", "rx-no-buf", "rx-miss", "rx-error", "tx-error"):
                    suffix = re.sub(r"[^a-zA-Z0-9_]", "_", path.rsplit("/", 1)[-1])
                    out.append(emit("vpp_interface_" + suffix + "_packets_total", value,
                                    {"interface": names.get(index, "index-" + index)}))
                elif path.startswith("/err/"):
                    node, error = path[5:].split("/", 1)
                    key = (node, error, index)
                    error_counters[key] = error_counters.get(key, 0.0) + float(value)
                elif path.startswith("/nat44-ed/") and path != "/nat44-ed/total-sessions":
                    bits = path.split("/")
                    if len(bits) >= 5:
                        labels = (bits[2], bits[3], bits[4], names.get(index, "index-" + index))
                        nat_counters[labels] = nat_counters.get(labels, 0.0) + float(value)
                elif path.startswith("/mem/") and path.endswith(("/used", "/total", "/free")):
                    heap = path.split("/")[2].replace(" ", "_")
                    suffix = path.rsplit("/", 1)[-1]
                    out.append(emit("vpp_memory_%s_%s_bytes" % (heap, suffix), value, kind="gauge"))
            elif typ == "3" and len(fields) >= 5 and fields[-1] in ("/if/rx", "/if/tx"):
                path, packets, bytes_value = fields[-1], fields[2], fields[3]
                direction = path.rsplit("/", 1)[-1]
                labels = {"interface": names.get(fields[1], "index-" + fields[1])}
                out.append(emit("vpp_interface_%s_packets_total" % direction, packets, labels))
                out.append(emit("vpp_interface_%s_bytes_total" % direction, bytes_value, labels))
        out.append(emit("vpp_nat44_ed_sessions", nat_sessions, kind="gauge"))
        out.append(emit("vpp_nat44_ed_max_configured_sessions", nat_capacity_per_worker * nat_worker_count, kind="gauge"))
        for (direction, path, protocol, interface), value in nat_counters.items():
            out.append(emit("vpp_nat44_ed_packets_total", value,
                            {"direction": direction, "path": path, "protocol": protocol, "interface": interface}))
        for (node, error, worker), value in error_counters.items():
            out.append(emit("vpp_error_packets_total", value,
                            {"node": node, "error": error, "worker": worker}))
        for line in workers:
            fields = line.split(":")
            if len(fields) >= 4 and fields[0] == "2":
                worker_metric = re.sub(r"[^a-zA-Z0-9_]", "_", fields[-1].rsplit("/", 1)[-1])
                out.append(emit("vpp_worker_" + worker_metric, fields[3], {"worker": fields[1]}, "gauge"))
        # Hardware counters are read-only ethtool statistics from the Linux PF.
        try:
            ethtool = subprocess.run([ETHTOOL, "-S", "enp3s0np0"], check=True,
                                     capture_output=True, text=True, timeout=4).stdout
            wanted = {"rx_steer_missed_packets", "rx_crc_errors_phy", "rx_out_of_buffer",
                      "tx_errors_phy", "rx_xdp_drop", "tx_queue_dropped"}
            for row in ethtool.splitlines():
                if ":" not in row:
                    continue
                key, value = (part.strip() for part in row.split(":", 1))
                if key in wanted and value.isdigit():
                    out.append(emit("vpp_mlx5_%s_total" % key, value))
        except (OSError, subprocess.SubprocessError):
            pass
        return "".join(out)

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/metrics":
                self.send_error(404)
                return
            try:
                body = scrape().encode()
            except (OSError, subprocess.SubprocessError) as exc:
                body = ("# TYPE vpp_exporter_up gauge\nvpp_exporter_up 0\n"
                        "# vpp scrape failed: %s\n" % exc).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *_args):
            pass

    class Server(http.server.ThreadingHTTPServer):
        allow_reuse_address = True
        daemon_threads = True

    Server.address_family = socket.AF_INET6
    Server(("::", PORT), Handler).serve_forever()
  '';
}
