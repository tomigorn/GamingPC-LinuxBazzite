import importlib.util
from importlib.machinery import SourceFileLoader

loader = SourceFileLoader("pb", "/home/bazzite/.local/bin/peripheral-battery")
spec = importlib.util.spec_from_loader("pb", loader)
pb = importlib.util.module_from_spec(spec)
loader.exec_module(pb)

ENUM = ("/org/freedesktop/UPower/devices/keyboard_dev_AA_BB "
        "/org/freedesktop/UPower/devices/mouse_hidpp_battery_0 "
        "/org/freedesktop/UPower/devices/line_power_AC "
        "/org/freedesktop/UPower/devices/DisplayDevice")

KEYBOARD = """  native-path:          /sys/devices/virtual/misc/uhid/0005:05AC:024F.000B
  vendor:               DAREU
  model:                Cidoo ABM084
  serial:               aa:bb:cc:dd:ee:ff
  power supply:         no
  updated:              Di 04 Aug 2026 21:30:00 (5 seconds ago)
  has history:          yes
  has statistics:       no
  keyboard
    present:             yes
    rechargeable:        yes
    state:               discharging
    warning-level:       none
    percentage:          62%
    icon-name:          'battery-full-symbolic'
  History (charge):
    1754336000\t62.000\tdischarging
"""

MOUSE = """  native-path:          /sys/class/power_supply/hidpp_battery_0
  vendor:               Logitech
  model:                MX Master 3
  power supply:         no
  updated:              Di 04 Aug 2026 21:30:00 (5 seconds ago)
  has history:          yes
  has statistics:       no
  mouse
    present:             yes
    rechargeable:        yes
    state:               charging
    warning-level:       none
    percentage:          15%
    icon-name:          'battery-caution-charging-symbolic'
"""

LINE_POWER = """  native-path:          /sys/class/power_supply/AC
  power supply:         yes
  updated:              Di 04 Aug 2026 21:30:00 (5 seconds ago)
  has history:          no
  has statistics:       no
  line-power
    warning-level:       none
    online:              yes
    icon-name:          'ac-adapter-symbolic'
"""

DISPLAY = """  power supply:         no
  updated:              Di 04 Aug 2026 20:25:03 (3639 seconds ago)
  has history:          no
  has statistics:       no
  unknown
    warning-level:       none
    percentage:          0%
    icon-name:          'battery-missing-symbolic'
"""

def fake_run(cmd, timeout=8):
    if cmd[1] == "-e":
        return 0, ENUM, ""
    return 0, {"keyboard_dev_AA_BB": KEYBOARD,
               "mouse_hidpp_battery_0": MOUSE,
               "line_power_AC": LINE_POWER}.get(cmd[2].split("/")[-1], DISPLAY), ""

pb.run = fake_run
got = pb.from_upower()
for d in got:
    print(d)

names = {d["name"] for d in got}
assert names == {"Cidoo ABM084", "MX Master 3"}, "unexpected devices: %s" % names
kb = next(d for d in got if d["name"] == "Cidoo ABM084")
assert (kb["kind"], kb["percent"], kb["status"]) == ("keyboard", 62, "discharging"), kb
ms = next(d for d in got if d["name"] == "MX Master 3")
assert (ms["kind"], ms["percent"], ms["status"]) == ("mouse", 15, "charging"), ms
print("\nPASS: line-power and DisplayDevice filtered out; keyboard + mouse parsed")
