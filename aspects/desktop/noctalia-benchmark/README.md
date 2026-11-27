# noctalia-benchmark

Collects idle desktop measurements for the two selectable sessions so they
can be compared with one script instead of ad-hoc `ps` output.

The `desktop-benchmark.service` user unit is `WantedBy` `mango-session.target`,
`umbriel-session.target`. After each login it
writes two JSON snapshots (90s and 300s) under
`${XDG_STATE_HOME:-~/.local/state}/noctalia-bench/`:

```
<session>-<timestamp>-early.json
<session>-<timestamp>-idle.json
```

Fields: session name, user-slice and `noctalia.service` memory, compositor /
Noctalia / fcitx5 / XWayland / clipboard-bridge / polkit-agent RSS, running
user-service count and the current `nvidia-smi` line. Every field is
best-effort; a missing tool yields 0 or an empty string rather than a failed
unit.

Removal: delete this feature and its include from the three session aspects;
the collected JSON under the state directory is user data and is not removed.
