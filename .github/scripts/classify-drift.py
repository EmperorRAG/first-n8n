#!/usr/bin/env python3
"""
Classify Azure `what-if` JSON output for the infra-drift workflow.

Reads `whatif.json` from CWD and prints four `name=value` lines suitable
for `>> $GITHUB_OUTPUT`:

    modify_total=<int>     # all Modify resources
    modify_real=<int>      # Modify resources that aren't known what-if noise
    delete=<int>           # all Delete resources (always real drift)
    create=<int>           # all Create resources (pending Bicep deploy)

Real-Modify resource IDs go to `real_modifies.txt` for the Job Summary.

Known-noise resource types (re-flagged by what-if even when Azure
matches Bicep) are excluded from `modify_real`:

* `Microsoft.App/containerApps` and `Microsoft.App/jobs` — `secrets[*]
  .keyVaultUrl` re-renders as an ARM `format(...)` expression in
  `after` vs the concrete URL in `before`; same for `value` props that
  call `reference(...)`.
* `Microsoft.Storage/.../fileServices/default/shares/*` — ARM
  normalises share metadata each pass.
* `Microsoft.Resources/deploymentScripts/*` — re-runs are gated by
  `forceUpdateTag`, but the resource itself always shows as Modify.
"""

from __future__ import annotations

import json
import os
import re
import sys

NOISE_PATTERNS = (
    re.compile(r"/Microsoft\.App/containerApps/[^/]+$", re.IGNORECASE),
    re.compile(r"/Microsoft\.App/jobs/[^/]+$", re.IGNORECASE),
    re.compile(
        r"/Microsoft\.Storage/storageAccounts/[^/]+/fileServices/default/shares/[^/]+$",
        re.IGNORECASE,
    ),
    re.compile(r"/Microsoft\.Resources/deploymentScripts/[^/]+$", re.IGNORECASE),
)


def is_noise(resource_id: str) -> bool:
    return any(p.search(resource_id) for p in NOISE_PATTERNS)


def main() -> int:
    try:
        with open("whatif.json", "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        # Empty / missing JSON => CLI errored. Emit zeros; the Fail-on-drift
        # step will still trigger via the absent JSON file.
        for line in (
            "modify_total=0",
            "modify_real=0",
            "delete=0",
            "create=0",
        ):
            print(line)
        open("real_modifies.txt", "w", encoding="utf-8").close()
        return 0

    changes = data.get("changes", []) or []
    modify_total = sum(1 for c in changes if c.get("changeType") == "Modify")
    delete = sum(1 for c in changes if c.get("changeType") == "Delete")
    create = sum(1 for c in changes if c.get("changeType") == "Create")

    real_modifies = [
        c["resourceId"]
        for c in changes
        if c.get("changeType") == "Modify" and not is_noise(c.get("resourceId", ""))
    ]
    with open("real_modifies.txt", "w", encoding="utf-8") as fh:
        for rid in real_modifies:
            fh.write(rid + "\n")

    print(f"modify_total={modify_total}")
    print(f"modify_real={len(real_modifies)}")
    print(f"delete={delete}")
    print(f"create={create}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
