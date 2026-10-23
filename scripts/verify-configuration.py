#!/usr/bin/env python3
"""Execute only the package's non-UI diagnostic; verify actual signed bundle flags."""
import json, pathlib, subprocess, sys
bundle, edition, name, identifier, version = sys.argv[1:6]
replica = len(sys.argv) == 7 and sys.argv[6] == "replica"
value = json.loads(subprocess.check_output([str(pathlib.Path(bundle) / "Contents/MacOS/PipCapture"), "--print-configuration"], text=True, timeout=10))
expected = {"edition": edition, "name": name, "bundleID": identifier, "version": version,
            "storageName": name, "hasExtras": edition.endswith("plus"), "isPip": edition.startswith("pip"), "isReplica": replica}
for key, wanted in expected.items():
    if value.get(key) != wanted:
        raise SystemExit(f"Bundle configuration mismatch for {key}: {value.get(key)!r} != {wanted!r}")
print(json.dumps(value, sort_keys=True))
