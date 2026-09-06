---
name: sops-secrets
description: The sops-nix secret workflow on this host — how API keys are encrypted, decrypted at rebuild, and exported into the shell. Use when adding, renaming, rotating or removing an API key or any other secret, when a secret is missing at runtime (empty env var, an agent or gptel failing to authenticate), when editing secrets/secrets.yaml or .sops.yaml, or when a program needs a credential and you are deciding how it should read it.
---

# Secrets (sops-nix)

Secrets live age-encrypted in `secrets/secrets.yaml`, which is **safe to
commit**. They are decrypted at rebuild to `/run/secrets/<name>`, owned by
`mayon`.

| File | Role |
|---|---|
| `secrets/secrets.yaml` | the encrypted store |
| `.sops.yaml` | recipients (which age keys can decrypt) |
| `modules/system/security/sops.nix` | per-secret `owner`, mode, target path |
| `modules/home/shell/zsh.nix` | the loop that exports them as env vars |

Two different keys are in play:

- **Decryption at rebuild** uses the host SSH ed25519 key.
- **Editing** uses your personal age key at `~/.config/sops/age/keys.txt`.

## Adding a key

1. `modules/system/security/sops.nix` — add a `secrets.<name>.owner` line.
2. `modules/home/shell/zsh.nix` — add a `<name>:ENV_VAR` entry to the export loop.
3. `sops secrets/secrets.yaml` — add the value.
4. Rebuild. Confirm with `ls -l /run/secrets/<name>`.

Removing a key is the same three edits in reverse. A leftover entry in the zsh
loop for a secret that no longer exists makes every new shell print an error.

## Reading a secret: env var vs. file

The zsh export loop only reaches processes started from an **interactive
shell**. Anything else — a systemd user unit, a `.desktop` entry, a program the
compositor spawns — inherits the systemd user environment and never sourced that
profile, so the variable is empty there.

For those, read `/run/secrets/<name>` directly. This is why Emacs' gptel config
(`modules/home/programs/dev/emacs/default.nix`) passes a lambda that reads
`/run/secrets/deepseek-api-key` rather than taking the key from the environment:
Emacs is normally started from a launcher, not from a zsh prompt.

Same trap applies to any new `systemd.user.services` entry that needs a
credential — use the file, or set the variable explicitly in the unit.

## Never

- Do not paste a plaintext secret into a `.nix` file. Everything in a module
  ends up world-readable in `/nix/store`.
- Do not add a secret to `modules/home/base/session-vars.nix` — same problem.
- Do not commit `~/.config/sops/age/keys.txt` or the host key.
