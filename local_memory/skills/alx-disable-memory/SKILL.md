---
name: alx-disable-memory
description: Temporarily turn Local Memory off. Moves the hooks and the instructions file aside and makes the memory skills user-only. Only when the user runs "/alx-disable-memory".
disable-model-invocation: true
---

# Disable Local Memory

Run this once, then tell the user the result and that the change applies from the next session:

```bash
__CMD__ disable
```

Saved memory is not touched. `/alx-enable-memory` turns everything back on.
