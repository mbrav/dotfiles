#!/usr/bin/env python3
"""Leaf-level update_dashboard patch ops between two v2 dashboard JSONs.
Usage: diff_ops.py old.json new.json out-prefix  -> out-prefix.el.ops.json, out-prefix.lay.ops.json"""

import json, sys


def diff(a, b, p, ops):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in b:
            if k in a:
                diff(a[k], b[k], f"{p}.{k}", ops)
            else:
                ops.append({"op": "add", "path": f"{p}.{k}", "value": b[k]})
        ops += [{"op": "remove", "path": f"{p}.{k}"} for k in a if k not in b]
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, f"{p}[{i}]", ops)
    elif a != b:
        ops.append({"op": "replace", "path": p, "value": b})


old, new, out = json.load(open(sys.argv[1])), json.load(open(sys.argv[2])), sys.argv[3]
ops = []
for k, v in new["elements"].items():
    if k in old["elements"]:
        diff(old["elements"][k], v, f"$.elements.{k}", ops)
    else:
        ops.append({"op": "add", "path": f"$.elements.{k}", "value": v})
ops += [
    {"op": "remove", "path": f"$.elements.{k}"}
    for k in old["elements"]
    if k not in new["elements"]
]
json.dump(ops, open(f"{out}.el.ops.json", "w"))
json.dump(
    [{"op": "replace", "path": "$.layout", "value": new["layout"]}],
    open(f"{out}.lay.ops.json", "w"),
)
print(f"{len(ops)} element ops; layout replace written")
