import importlib.util, json, os, tempfile, time
from importlib.machinery import SourceFileLoader

loader = SourceFileLoader("pb", "/home/bazzite/.local/bin/peripheral-battery")
spec = importlib.util.spec_from_loader("pb", loader)
pb = importlib.util.module_from_spec(spec)
loader.exec_module(pb)

tmp = tempfile.mkdtemp()
pb.CACHE_PATH = os.path.join(tmp, "cache.json")

def seed(entries):
    json.dump(entries, open(pb.CACHE_PATH, "w"))

now = time.time()
fails = []

def check(label, got, want):
    ok = got == want
    print("%-58s %s" % (label, "ok" if ok else "FAIL got=%r want=%r" % (got, want)))
    if not ok:
        fails.append(label)

# 1. asleep + fresh cache -> last known value, marked stale
seed({"Mouse": {"percent": 73, "ts": now - 60}})
d = [{"name": "Mouse", "kind": "mouse", "percent": None, "status": "asleep",
      "source": "openrazer", "cacheable": True}]
pb.apply_cache(d)
check("asleep + fresh cache -> percent", d[0]["percent"], 73)
check("asleep + fresh cache -> stale flag", d[0]["stale"], True)
check("asleep + fresh cache -> status untouched", d[0]["status"], "asleep")
check("asleep + fresh cache -> since populated", bool(d[0]["since"]), True)

# 2. asleep + expired cache -> must not resurrect a day-old number
seed({"Mouse": {"percent": 73, "ts": now - 20 * 3600}})
d = [{"name": "Mouse", "kind": "mouse", "percent": None, "status": "asleep",
      "source": "openrazer", "cacheable": True}]
pb.apply_cache(d)
check("asleep + 20h-old cache -> stays blank", d[0]["percent"], None)
check("asleep + 20h-old cache -> not stale", d[0]["stale"], False)

# 3. asleep + no cache at all
seed({})
d = [{"name": "Mouse", "kind": "mouse", "percent": None, "status": "asleep",
      "source": "openrazer", "cacheable": True}]
pb.apply_cache(d)
check("asleep + empty cache -> stays blank", d[0]["percent"], None)

# 4. permission error must NOT be masked by a cached value
seed({"Mouse": {"percent": 73, "ts": now - 60}})
d = [{"name": "Mouse", "kind": "mouse", "percent": None,
      "status": "no permission to read level", "source": "openrazer"}]
pb.apply_cache(d)
check("permission error -> not masked by cache", d[0]["percent"], None)

# 5. a live reading refreshes the cache
seed({"Mouse": {"percent": 10, "ts": now - 5000}})
d = [{"name": "Mouse", "kind": "mouse", "percent": 64, "status": "discharging",
      "source": "openrazer"}]
pb.apply_cache(d)
check("live reading -> cache updated", json.load(open(pb.CACHE_PATH))["Mouse"]["percent"], 64)

# 6. charging status survives so the widget's isCharging() still works
seed({"Headset": {"percent": 40, "ts": now - 60}})
d = [{"name": "Headset", "kind": "headset", "percent": None, "status": "charging",
      "source": "headsetcontrol", "cacheable": True}]
pb.apply_cache(d)
check("stale + charging -> status still 'charging'", d[0]["status"], "charging")

# 7. corrupt cache file must not crash the run
open(pb.CACHE_PATH, "w").write("{not json")
d = [{"name": "Mouse", "kind": "mouse", "percent": None, "status": "asleep",
      "source": "openrazer", "cacheable": True}]
pb.apply_cache(d)
check("corrupt cache -> handled, stays blank", d[0]["percent"], None)

# 8. 'cacheable' must never leak into the JSON the widget parses
check("internal 'cacheable' key stripped", "cacheable" in d[0], False)

print()
print("FAILURES: %d" % len(fails))
raise SystemExit(1 if fails else 0)
