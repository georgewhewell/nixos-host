# Shared library for xmrig modules (Linux and Darwin).
# Not a NixOS module. Import as:
#   let common = import ./xmrig-common.nix { inherit lib network; };
{ lib, network }:
{
  # ── MQTT switch option definitions ───────────────────────────────────────
  mqttSwitchOptions = {
    enable = lib.mkEnableOption "MQTT control and Home Assistant discovery for xmrig";

    host = lib.mkOption {
      type = lib.types.str;
      default = network.routerIp;
      description = "MQTT broker hostname/IP.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1883;
      description = "MQTT broker port.";
    };

    username = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "rw";
      description = "MQTT username.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a file containing the MQTT password.";
    };

    topicPrefix = lib.mkOption {
      type = lib.types.str;
      default = "home/xmrig";
      description = "Base topic prefix for xmrig control/state topics.";
    };

    discoveryPrefix = lib.mkOption {
      type = lib.types.str;
      default = "homeassistant";
      description = "Home Assistant MQTT discovery prefix.";
    };

    qos = lib.mkOption {
      type = lib.types.ints.between 0 2;
      default = 1;
      description = "MQTT QoS for publish/subscribe operations.";
    };
  };

  # ── MQTT topic computation ───────────────────────────────────────────────
  # { mqttCfg, hostName } -> attrset of topic strings
  mkMqttTopics = { mqttCfg, hostName }:
    let
      hostObjectId = lib.replaceStrings ["-"] ["_"] hostName;
    in {
      stateTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/state";
      commandTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/set";
      globalCommandTopic = "${mqttCfg.topicPrefix}/all/set";
      availabilityTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/availability";
      effectiveTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/effective";
      inhibitedTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/inhibited";
      inhibitReasonTopic = "${mqttCfg.topicPrefix}/hosts/${hostName}/inhibit_reason";
      discoveryTopic = "${mqttCfg.discoveryPrefix}/switch/xmrig_${hostObjectId}/config";
      effectiveDiscoveryTopic = "${mqttCfg.discoveryPrefix}/binary_sensor/xmrig_${hostObjectId}_effective/config";
      inhibitedDiscoveryTopic = "${mqttCfg.discoveryPrefix}/binary_sensor/xmrig_${hostObjectId}_inhibited/config";
      inhibitReasonDiscoveryTopic = "${mqttCfg.discoveryPrefix}/sensor/xmrig_${hostObjectId}_inhibit_reason/config";
    };

  # ── Discovery payload generation ─────────────────────────────────────────
  # { hostName, topics, platformModel } -> { switch, effective, inhibited, inhibitReason }
  mkDiscoveryPayloads = { hostName, topics, platformModel ? "Linux Host" }:
    let
      hostObjectId = lib.replaceStrings ["-"] ["_"] hostName;
      device = {
        identifiers = ["host-${hostName}"];
        name = hostName;
        manufacturer = "NixOS";
        model = platformModel;
      };
      avail = {
        payload_available = "online";
        payload_not_available = "offline";
        availability_topic = topics.availabilityTopic;
      };
      onoff = {
        payload_on = "ON";
        payload_off = "OFF";
        state_on = "ON";
        state_off = "OFF";
      };
    in {
      switch = builtins.toJSON (avail // onoff // {
        name = "${hostName} XMRig";
        object_id = "${hostObjectId}_xmrig";
        unique_id = "xmrig-switch-${hostName}";
        icon = "mdi:pickaxe";
        command_topic = topics.commandTopic;
        state_topic = topics.stateTopic;
        inherit device;
      });
      effective = builtins.toJSON (avail // onoff // {
        name = "${hostName} XMRig Mining Active";
        object_id = "${hostObjectId}_xmrig_effective";
        unique_id = "xmrig-effective-${hostName}";
        icon = "mdi:pickaxe";
        state_topic = topics.effectiveTopic;
        inherit device;
      });
      inhibited = builtins.toJSON (avail // onoff // {
        name = "${hostName} XMRig Inhibited";
        object_id = "${hostObjectId}_xmrig_inhibited";
        unique_id = "xmrig-inhibited-${hostName}";
        icon = "mdi:pause-circle";
        state_topic = topics.inhibitedTopic;
        entity_category = "diagnostic";
        inherit device;
      });
      inhibitReason = builtins.toJSON (avail // {
        name = "${hostName} XMRig Inhibit Reason";
        object_id = "${hostObjectId}_xmrig_inhibit_reason";
        unique_id = "xmrig-inhibit-reason-${hostName}";
        icon = "mdi:text-box-outline";
        state_topic = topics.inhibitReasonTopic;
        entity_category = "diagnostic";
        inherit device;
      });
    };

  # ── MQTT portion of agent config ─────────────────────────────────────────
  # { mqttCfg, topics, payloads } -> attrset for the "mqtt" key in agent config JSON
  mkMqttAgentConfig = { mqttCfg, topics, payloads }: {
    enabled = mqttCfg.enable;
    host = mqttCfg.host;
    port = mqttCfg.port;
    username = mqttCfg.username;
    passwordFile = if mqttCfg.passwordFile != null then toString mqttCfg.passwordFile else null;
    qos = mqttCfg.qos;
    commandTopic = topics.commandTopic;
    globalCommandTopic = topics.globalCommandTopic;
    availabilityTopic = topics.availabilityTopic;
    desiredStateTopic = topics.stateTopic;
    effectiveStateTopic = topics.effectiveTopic;
    inhibitedStateTopic = topics.inhibitedTopic;
    inhibitReasonTopic = topics.inhibitReasonTopic;
    discovery = [
      { topic = topics.discoveryTopic; payload = payloads.switch; }
      { topic = topics.effectiveDiscoveryTopic; payload = payloads.effective; }
      { topic = topics.inhibitedDiscoveryTopic; payload = payloads.inhibited; }
      { topic = topics.inhibitReasonDiscoveryTopic; payload = payloads.inhibitReason; }
    ];
  };

  # ── Unified Python MQTT+inhibit agent ────────────────────────────────────
  # { pkgs, agentConfigJson } -> derivation with /bin/xmrig-mqtt-agent
  #
  # agentConfigJson should be the result of builtins.toJSON on:
  # {
  #   platform = "linux" | "darwin";
  #   mqtt = <mkMqttAgentConfig result>;
  #   xmrigApi = { baseUrl, token };
  #   inhibitor = { nixBuilds = { enable, quietSeconds? }; dota2? = { enable, quietSeconds, patterns }; };
  #   system = { stateDir?, systemctl?, journalctl?, launchdLabel? };
  # }
  mkMqttAgentPython = { pkgs, agentConfigJson }:
    let
      python = pkgs.python3.withPackages (ps: [ps.paho-mqtt]);
    in
      pkgs.writeTextFile {
        name = "xmrig-mqtt-agent";
        destination = "/bin/xmrig-mqtt-agent";
        executable = true;
        text = ''
          #!${python}/bin/python3
          import errno
          import json
          import os
          import re
          import select
          import signal
          import subprocess
          import sys
          import threading
          import time
          import urllib.error
          import urllib.request

          import paho.mqtt.client as mqtt


          CONFIG = json.loads(${builtins.toJSON agentConfigJson})


          def log(msg):
              print(f"xmrig-mqtt: {msg}", file=sys.stderr, flush=True)


          class Agent:
              def __init__(self):
                  self.platform = CONFIG["platform"]
                  self.mqtt_cfg = CONFIG["mqtt"]
                  self.mqtt_enabled = self.mqtt_cfg.get("enabled", False)
                  self.api_cfg = CONFIG["xmrigApi"]
                  self.inhibit_cfg = CONFIG.get("inhibitor", {}).get("nixBuilds", {"enable": False})
                  self.dota2_cfg = CONFIG.get("inhibitor", {}).get("dota2", {"enable": False})
                  self.system_cfg = CONFIG.get("system", {})

                  self.stop_event = threading.Event()
                  self.reconcile_event = threading.Event()
                  self.lock = threading.RLock()

                  self.desired_on = None if self.mqtt_enabled else True
                  self.client = None
                  self.nix_build_deadline = 0.0
                  self.dota2_deadline = 0.0
                  self.nix_client_pids = {}
                  self.linux_clk_tck = None
                  if self.platform == "linux":
                      try:
                          self.linux_clk_tck = int(os.sysconf("SC_CLK_TCK"))
                      except (AttributeError, OSError, ValueError):
                          self.linux_clk_tck = 100

                  self.last_logged_control_state = None
                  self.last_logged_effective = None

                  state_dir_cfg = self.system_cfg.get("stateDir")
                  if state_dir_cfg:
                      self.state_dir = state_dir_cfg
                  else:
                      self.state_dir = os.path.join(
                          os.path.expanduser("~"), ".local", "state", "xmrig-mqtt"
                      )
                  self.desired_state_file = os.path.join(self.state_dir, "desired_state")
                  self.has_persisted_state = False

                  # Platform-specific regex patterns for nix log watching
                  if self.platform == "linux":
                      self.build_re = re.compile(r"\bbuilding '/nix/store/", re.IGNORECASE)
                      self.nix_accept_re = re.compile(
                          r"accepted connection from pid (\d+), user .*\(trusted\)",
                          re.IGNORECASE,
                      )
                  else:
                      self.nix_line_re = re.compile(r"\bnix\[(\d+):")
                      self.nix_accept_re = re.compile(
                          r"accepted connection from pid (\d+)", re.IGNORECASE
                      )

                  self.dota2_res = [
                      re.compile(p, re.IGNORECASE)
                      for p in self.dota2_cfg.get("patterns", [])
                  ]

              # ── State persistence ────────────────────────────────────────

              def ensure_state_dir(self):
                  os.makedirs(self.state_dir, exist_ok=True)

              def load_desired_state(self):
                  try:
                      with open(self.desired_state_file, "r", encoding="utf-8") as f:
                          raw = f.read().strip().upper()
                      if raw == "ON":
                          return True
                      if raw == "OFF":
                          return False
                  except FileNotFoundError:
                      return None
                  except Exception as exc:
                      log(f"failed to load desired state: {exc}")
                  return None

              def save_desired_state(self):
                  if self.desired_on is None:
                      return
                  tmp = f"{self.desired_state_file}.tmp"
                  payload = "ON" if self.desired_on else "OFF"
                  try:
                      with open(tmp, "w", encoding="utf-8") as f:
                          f.write(payload)
                      os.replace(tmp, self.desired_state_file)
                  except Exception as exc:
                      log(f"failed to save desired state: {exc}")

              # ── MQTT ─────────────────────────────────────────────────────

              def mqtt_publish(self, topic, payload, retain=True):
                  if self.client is None:
                      return
                  self.client.publish(
                      topic,
                      payload=payload,
                      qos=int(self.mqtt_cfg["qos"]),
                      retain=retain,
                  )

              def publish_discovery(self):
                  for item in self.mqtt_cfg["discovery"]:
                      self.mqtt_publish(item["topic"], item["payload"], retain=True)

              def publish_availability(self, payload):
                  self.mqtt_publish(
                      self.mqtt_cfg["availabilityTopic"], payload, retain=True
                  )

              def publish_states(self):
                  if not self.mqtt_enabled:
                      return
                  with self.lock:
                      desired = bool(self.desired_on) if self.desired_on is not None else False
                      inhibited, reason = self._inhibit_state_locked()
                  effective = self.effective_mining_active()
                  with self.lock:
                      if self.last_logged_effective is None or self.last_logged_effective != effective:
                          log(f"effective={self._onoff(effective)}")
                          self.last_logged_effective = effective
                  self.mqtt_publish(self.mqtt_cfg["desiredStateTopic"], "ON" if desired else "OFF", retain=True)
                  self.mqtt_publish(self.mqtt_cfg["effectiveStateTopic"], "ON" if effective else "OFF", retain=True)
                  self.mqtt_publish(self.mqtt_cfg["inhibitedStateTopic"], "ON" if inhibited else "OFF", retain=True)
                  self.mqtt_publish(self.mqtt_cfg["inhibitReasonTopic"], reason, retain=True)

              # ── XMRig API ────────────────────────────────────────────────

              def api_request(self, method, path, body=None):
                  data = None
                  headers = {"Authorization": f"Bearer {self.api_cfg['token']}"}
                  if body is not None:
                      data = json.dumps(body).encode("utf-8")
                      headers["Content-Type"] = "application/json"
                  req = urllib.request.Request(
                      url=f"{self.api_cfg['baseUrl']}{path}",
                      method=method,
                      headers=headers,
                      data=data,
                  )
                  with urllib.request.urlopen(req, timeout=4) as resp:
                      payload = resp.read()
                  if not payload:
                      return {}
                  return json.loads(payload.decode("utf-8"))

              def xmrig_summary(self):
                  return self.api_request("GET", "/2/summary")

              def xmrig_jsonrpc(self, method_name):
                  return self.api_request(
                      "POST",
                      "/json_rpc",
                      {"id": 1, "jsonrpc": "2.0", "method": method_name},
                  )

              def wait_for_api(self):
                  for _ in range(20):
                      if self.stop_event.is_set():
                          return False
                      try:
                          self.xmrig_summary()
                          return True
                      except Exception:
                          time.sleep(0.5)
                  return False

              # ── Platform service management ──────────────────────────────

              def xmrig_service_active(self):
                  if self.platform == "linux":
                      result = subprocess.run(
                          [self.system_cfg["systemctl"], "is-active", "--quiet", "xmrig.service"],
                          stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE,
                          check=False,
                      )
                      return result.returncode == 0
                  else:
                      # Darwin: launchd KeepAlive keeps xmrig running; check API
                      try:
                          self.xmrig_summary()
                          return True
                      except Exception:
                          return False

              def effective_mining_active(self):
                  if self.platform == "linux" and not self.xmrig_service_active():
                      return False
                  try:
                      summary = self.xmrig_summary()
                      return not bool(summary.get("paused", False))
                  except Exception as exc:
                      log(f"xmrig API unavailable: {exc}")
                      return False

              def set_mining_active(self, active):
                  if active:
                      if self.platform == "linux":
                          if not self.xmrig_service_active():
                              log("action start xmrig.service")
                              start = subprocess.run(
                                  [self.system_cfg["systemctl"], "start", "xmrig.service"],
                                  stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE,
                                  text=True,
                                  check=False,
                              )
                              if start.returncode != 0:
                                  raise RuntimeError(
                                      f"failed to start xmrig.service: {start.stderr.strip()}"
                                  )
                      else:
                          # Darwin: kickstart xmrig via launchd
                          label = self.system_cfg.get("launchdLabel", "org.nixos.xmrig")
                          uid = str(os.getuid())
                          subprocess.run(
                              ["/bin/launchctl", "kickstart", "-k", f"gui/{uid}/{label}"],
                              check=False,
                              stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL,
                          )
                      if not self.wait_for_api():
                          raise RuntimeError("xmrig API did not become ready")
                      log("action resume mining")
                      self.xmrig_jsonrpc("resume")
                  else:
                      log("action pause mining")
                      self.xmrig_jsonrpc("pause")

              # ── Helpers ──────────────────────────────────────────────────

              def _onoff(self, value):
                  return "ON" if value else "OFF"

              # ── Inhibitor state ──────────────────────────────────────────

              def _inhibit_state_locked(self, now=None):
                  now = time.time() if now is None else now
                  if self.nix_build_deadline > 0 and now >= self.nix_build_deadline:
                      self.nix_build_deadline = 0.0
                  if self.dota2_deadline > 0 and now >= self.dota2_deadline:
                      self.dota2_deadline = 0.0

                  reasons = []
                  if self.nix_client_pids:
                      reasons.append("nix active")
                  if self.nix_build_deadline > now:
                      reasons.append("nix build")
                  if self.dota2_deadline > now:
                      reasons.append("dota2 activity")

                  return (len(reasons) > 0, ", ".join(reasons))

              def set_nix_build_activity(self):
                  quiet = float(self.inhibit_cfg.get("quietSeconds", 120))
                  with self.lock:
                      self.nix_build_deadline = time.time() + quiet
                  self.schedule_reconcile()

              def set_dota2_activity(self):
                  if not self.dota2_cfg.get("enable", False):
                      return
                  quiet = float(self.dota2_cfg.get("quietSeconds", 600))
                  with self.lock:
                      self.dota2_deadline = time.time() + quiet
                  self.schedule_reconcile()

              # ── PID tracking ─────────────────────────────────────────────

              def _is_pid_alive(self, pid):
                  try:
                      os.kill(pid, 0)
                      return True
                  except OSError as exc:
                      if exc.errno == errno.ESRCH:
                          return False
                      if exc.errno == errno.EPERM:
                          return True
                      return False

              def _linux_pid_start_ticks(self, pid):
                  if self.platform != "linux":
                      return None
                  try:
                      with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as f:
                          stat_line = f.read().strip()
                  except (FileNotFoundError, PermissionError, ProcessLookupError, OSError):
                      return None

                  close_paren = stat_line.rfind(")")
                  if close_paren < 0:
                      return None

                  fields = stat_line[close_paren + 2 :].split()
                  if len(fields) <= 19:
                      return None

                  try:
                      return int(fields[19])
                  except ValueError:
                      return None

              def _wait_for_pid_exit(self, pid, expected_start_ticks=0, pidfd=None):
                  try:
                      if pidfd is not None:
                          poller = select.poll()
                          poller.register(
                              pidfd,
                              select.POLLIN | select.POLLHUP | select.POLLERR,
                          )
                          while not self.stop_event.is_set():
                              events = poller.poll(1000)
                              if events:
                                  break
                      elif self.platform == "linux":
                          while not self.stop_event.is_set():
                              current_start_ticks = self._linux_pid_start_ticks(pid)
                              if (
                                  current_start_ticks is None
                                  or current_start_ticks != expected_start_ticks
                              ):
                                  break
                              time.sleep(1)
                      else:
                          # Darwin: poll with os.kill
                          while not self.stop_event.is_set() and self._is_pid_alive(pid):
                              time.sleep(1)
                  except ProcessLookupError:
                      pass
                  except Exception as exc:
                      log(f"pid watcher failed for {pid}: {exc}")
                  finally:
                      if pidfd is not None:
                          try:
                              os.close(pidfd)
                          except Exception:
                              pass
                      removed = False
                      with self.lock:
                          current_start_ticks = self.nix_client_pids.get(pid)
                          if (
                              current_start_ticks is not None
                              and current_start_ticks == expected_start_ticks
                          ):
                              del self.nix_client_pids[pid]
                              removed = True
                      if removed:
                          log(f"nix client exited pid={pid}")
                      self.schedule_reconcile()

              def track_nix_client_pid(self, pid, accepted_mono_usecs=None):
                  if not self.inhibit_cfg.get("enable", False):
                      return
                  if pid == os.getpid():
                      return
                  expected_start_ticks = 0
                  pidfd = None
                  if self.platform == "linux":
                      if hasattr(os, "pidfd_open"):
                          try:
                              pidfd = os.pidfd_open(pid, 0)
                          except ProcessLookupError:
                              return
                          except OSError as exc:
                              if exc.errno != errno.ESRCH:
                                  log(f"pidfd_open failed for {pid}: {exc}")
                              pidfd = None

                      expected_start_ticks = self._linux_pid_start_ticks(pid)
                      if expected_start_ticks is None:
                          if pidfd is not None:
                              try:
                                  os.close(pidfd)
                              except Exception:
                                  pass
                          return

                      accepted_start_ticks = None
                      if accepted_mono_usecs is not None and self.linux_clk_tck:
                          accepted_start_ticks = (
                              accepted_mono_usecs * self.linux_clk_tck
                          ) // 1000000
                      if (
                          accepted_start_ticks is not None
                          and expected_start_ticks > accepted_start_ticks
                      ):
                          log(
                              f"ignoring reused nix client pid={pid} "
                              f"start_ticks={expected_start_ticks} "
                              f"accept_ticks={accepted_start_ticks}"
                          )
                          if pidfd is not None:
                              try:
                                  os.close(pidfd)
                              except Exception:
                                  pass
                          return
                  with self.lock:
                      if self.nix_client_pids.get(pid) == expected_start_ticks:
                          if pidfd is not None:
                              try:
                                  os.close(pidfd)
                              except Exception:
                                  pass
                          return
                      self.nix_client_pids[pid] = expected_start_ticks
                  log(f"nix client connected pid={pid}")
                  self.schedule_reconcile()
                  threading.Thread(
                      target=self._wait_for_pid_exit,
                      args=(pid, expected_start_ticks, pidfd),
                      daemon=True,
                      name=f"nix-pid-{pid}",
                  ).start()

              # ── Reconcile ────────────────────────────────────────────────

              def reconcile(self):
                  with self.lock:
                      desired = bool(self.desired_on) if self.desired_on is not None else False
                      inhibited, reason = self._inhibit_state_locked()
                      target_active = desired and (not inhibited)
                      control_state = (desired, inhibited, reason, target_active)
                      if self.last_logged_control_state != control_state:
                          log(
                              f"control desired={self._onoff(desired)} "
                              f"inhibited={self._onoff(inhibited)} "
                              f"reason={reason or '-'} "
                              f"target={self._onoff(target_active)}"
                          )
                          self.last_logged_control_state = control_state
                  effective_before = self.effective_mining_active()
                  if effective_before != target_active:
                      try:
                          self.set_mining_active(target_active)
                      except Exception as exc:
                          log(f"reconcile failed: {exc}")
                  self.publish_states()

              def schedule_reconcile(self):
                  self.reconcile_event.set()

              def reconcile_worker(self):
                  while not self.stop_event.is_set():
                      timeout = None
                      with self.lock:
                          deadlines = [
                              d
                              for d in (self.nix_build_deadline, self.dota2_deadline)
                              if d > 0
                          ]
                          if deadlines:
                              timeout = max(0.0, min(deadlines) - time.time())
                      triggered = self.reconcile_event.wait(timeout)
                      self.reconcile_event.clear()
                      if self.stop_event.is_set():
                          return
                      if not triggered:
                          with self.lock:
                              self._inhibit_state_locked()
                      self.reconcile()

              # ── MQTT callbacks ───────────────────────────────────────────

              def on_connect(self, client, _userdata, _flags, rc):
                  if rc != 0:
                      log(f"MQTT connect failed rc={rc}")
                      return
                  client.subscribe(
                      [
                          (self.mqtt_cfg["globalCommandTopic"], int(self.mqtt_cfg["qos"])),
                          (self.mqtt_cfg["commandTopic"], int(self.mqtt_cfg["qos"])),
                      ]
                  )
                  self.publish_discovery()
                  self.publish_availability("online")
                  self.publish_states()

              def on_message(self, _client, _userdata, msg):
                  payload = (
                      msg.payload.decode("utf-8", "replace") if msg.payload else ""
                  ).strip()
                  normalized = payload.upper()
                  if msg.retain and self.has_persisted_state:
                      log(
                          f"ignoring retained message topic={msg.topic} "
                          f"payload={payload} (have persisted state)"
                      )
                      self.publish_states()
                      return
                  changed = False
                  with self.lock:
                      if normalized in ("ON", "1", "TRUE"):
                          self.desired_on = True
                          changed = True
                      elif normalized in ("OFF", "0", "FALSE"):
                          self.desired_on = False
                          changed = True
                      elif normalized == "TOGGLE":
                          current = (
                              bool(self.desired_on)
                              if self.desired_on is not None
                              else self.effective_mining_active()
                          )
                          self.desired_on = not current
                          changed = True
                      elif normalized == "STATUS":
                          pass
                      elif normalized == "":
                          return
                      else:
                          log(f"ignoring payload '{payload}'")
                          return

                      if changed:
                          log(
                              f"command topic={msg.topic} "
                              f"desired={self._onoff(self.desired_on)}"
                          )
                          self.save_desired_state()
                  self.schedule_reconcile()

              def mqtt_loop_start(self):
                  pw_file = self.mqtt_cfg.get("passwordFile")
                  if not pw_file:
                      raise RuntimeError("MQTT passwordFile not configured")
                  try:
                      with open(pw_file, "r", encoding="utf-8") as f:
                          pw = f.read().strip()
                  except Exception as exc:
                      raise RuntimeError(
                          f"password file not readable: {pw_file}: {exc}"
                      ) from exc

                  client = mqtt.Client(
                      client_id=f"xmrig-agent-{os.uname().nodename}",
                      clean_session=True,
                  )
                  client.username_pw_set(self.mqtt_cfg["username"], pw)
                  client.will_set(
                      self.mqtt_cfg["availabilityTopic"],
                      payload="offline",
                      qos=int(self.mqtt_cfg["qos"]),
                      retain=True,
                  )
                  client.on_connect = self.on_connect
                  client.on_message = self.on_message
                  client.reconnect_delay_set(min_delay=1, max_delay=5)
                  client.connect(
                      self.mqtt_cfg["host"],
                      int(self.mqtt_cfg["port"]),
                      keepalive=30,
                  )
                  client.loop_start()
                  self.client = client

              # ── Log watchers (platform-specific) ─────────────────────────

              def _run_log_watcher(self, cmd, line_handler):
                  while not self.stop_event.is_set():
                      try:
                          proc = subprocess.Popen(
                              cmd,
                              stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE,
                              text=True,
                          )
                      except Exception as exc:
                          log(f"failed to start log watcher: {exc}")
                          if self.stop_event.wait(2):
                              return
                          continue
                      try:
                          assert proc.stdout is not None
                          for line in proc.stdout:
                              if self.stop_event.is_set():
                                  break
                              try:
                                  line_handler(line)
                              except Exception as exc:
                                  log(f"log handler error: {exc}")
                      finally:
                          try:
                              proc.terminate()
                          except Exception:
                              pass
                          try:
                              proc.wait(timeout=1)
                          except Exception:
                              try:
                                  proc.kill()
                              except Exception:
                                  pass
                      if self.stop_event.wait(1):
                          return

              def nix_log_watcher_worker(self):
                  if not self.inhibit_cfg.get("enable", False):
                      return

                  if self.platform == "linux":
                      cmd = [
                          self.system_cfg["journalctl"],
                          "-f", "-n", "0", "-o", "json",
                          "-u", "nix-daemon.service",
                      ]

                      def handler(line):
                          message = line
                          accepted_mono_usecs = None
                          try:
                              entry = json.loads(line)
                              raw_message = entry.get("MESSAGE", "")
                              # journald JSON encodes non-UTF-8 MESSAGE as a
                              # list of byte integers — coerce back to a string.
                              if isinstance(raw_message, list):
                                  message = bytes(raw_message).decode(
                                      "utf-8", errors="replace"
                                  )
                              else:
                                  message = raw_message
                              monotonic = entry.get("__MONOTONIC_TIMESTAMP")
                              if monotonic is not None:
                                  accepted_mono_usecs = int(monotonic)
                          except (TypeError, ValueError, json.JSONDecodeError):
                              pass

                          match = self.nix_accept_re.search(message)
                          if match:
                              try:
                                  self.track_nix_client_pid(
                                      int(match.group(1)),
                                      accepted_mono_usecs=accepted_mono_usecs,
                                  )
                              except Exception:
                                  pass
                          if self.build_re.search(message):
                              self.set_nix_build_activity()
                  else:
                      cmd = [
                          "/usr/bin/log", "stream",
                          "--style", "compact",
                          "--level", "debug",
                          "--predicate",
                          'process == "nix" || process == "nix-daemon"',
                      ]

                      def handler(line):
                          m = self.nix_line_re.search(line)
                          if m:
                              try:
                                  self.track_nix_client_pid(int(m.group(1)))
                              except Exception:
                                  pass
                          m = self.nix_accept_re.search(line)
                          if m:
                              try:
                                  self.track_nix_client_pid(int(m.group(1)))
                              except Exception:
                                  pass

                  self._run_log_watcher(cmd, handler)

              def dota2_journal_worker(self):
                  if self.platform != "linux":
                      return
                  if not self.dota2_cfg.get("enable", False):
                      return
                  if not self.dota2_res:
                      log("dota2 inhibitor enabled but no patterns configured")
                      return
                  cmd = [
                      self.system_cfg["journalctl"],
                      "-f", "-n", "0", "-o", "cat",
                  ]

                  def handler(line):
                      if any(pattern.search(line) for pattern in self.dota2_res):
                          self.set_dota2_activity()

                  self._run_log_watcher(cmd, handler)

              # ── Lifecycle ────────────────────────────────────────────────

              def start(self):
                  self.ensure_state_dir()
                  if self.mqtt_enabled:
                      self.desired_on = self.load_desired_state()
                      if self.desired_on is not None:
                          self.has_persisted_state = True
                      else:
                          self.desired_on = self.effective_mining_active()
                      self.mqtt_loop_start()

                  self.reconcile_thread = threading.Thread(
                      target=self.reconcile_worker, daemon=True, name="reconcile"
                  )
                  self.reconcile_thread.start()

                  self.nix_thread = threading.Thread(
                      target=self.nix_log_watcher_worker, daemon=True, name="nix-watcher"
                  )
                  self.nix_thread.start()

                  if self.platform == "linux":
                      self.dota2_thread = threading.Thread(
                          target=self.dota2_journal_worker,
                          daemon=True,
                          name="dota2-watcher",
                      )
                      self.dota2_thread.start()

                  self.schedule_reconcile()

              def stop(self):
                  self.stop_event.set()
                  self.reconcile_event.set()
                  try:
                      if self.client is not None:
                          self.publish_availability("offline")
                          self.client.loop_stop()
                          self.client.disconnect()
                  except Exception:
                      pass


          def main():
              agent = Agent()

              def _handler(_signum, _frame):
                  agent.stop()
                  sys.exit(0)

              signal.signal(signal.SIGTERM, _handler)
              signal.signal(signal.SIGINT, _handler)

              agent.start()
              while True:
                  time.sleep(3600)


          if __name__ == "__main__":
              main()
        '';
      };
}
