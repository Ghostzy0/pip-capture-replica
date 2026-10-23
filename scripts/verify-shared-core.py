#!/usr/bin/env python3
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parent.parent
manifest=json.loads((root/'SHARED-CORE.json').read_text())
for name,wanted in manifest['sha256'].items():
    path=(root/name).resolve()
    if root not in path.parents or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=wanted:
        raise SystemExit('Shared source mismatch: '+name)
print('Shared Swift source matches '+manifest['commit'])
