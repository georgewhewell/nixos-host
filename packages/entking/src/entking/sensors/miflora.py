from miflora.miflora_poller import MiFloraPoller
from btlewrap.bluepy import BluepyBackend

MACS = [
  #  "C4:7C:8D:62:87:BA",  # A
    "C4:7C:8D:65:AC:8B",  # B
    "C4:7C:8D:65:AA:A3",  # C
    "C4:7C:8D:65:A9:92",  # D
]


pollers = [
    MiFloraPoller(mac, BluepyBackend)
    for mac in MACS
]


for poller in pollers:
    import pdb; pdb.set_trace()
    pass
