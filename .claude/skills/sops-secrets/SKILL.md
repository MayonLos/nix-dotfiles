---
name: sops-secrets
description: The sops-nix secret workflow on this host — how secrets are encrypted, decrypted at rebuild, and reach a program as an env var, a file, or a rendered config fragment. Use when adding, renaming, rotating or removing an API key or token, when a secret is missing at runtime (empty env var, an agent or gptel failing to authenticate, nix hitting a GitHub rate limit), when editing secrets/secrets.yaml, .sops.yaml or modules/system/security/sops.nix, or when a program needs a credential and you are deciding how it should read it.
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
| `modules/home/shell/zsh.nix` | the loop that exports them as env vars in interactive shells |

Currently stored: `deepseek-api-key` (gptel, the AI agents) and `github-token`
(nix's `access-tokens`, so flake input fetches are not rate-limited).

Two different keys are in play:

- **Decryption at rebuild** uses the host SSH ed25519 key.
- **Editing** uses your personal age key at `~/.config/sops/age/keys.txt`.

## Adding a key

1. `modules/system/security/sops.nix` — add a `secrets.<name>.owner = "mayon";`
   line.
2. `sops secrets/secrets.yaml` — add the value.
3. Wire up **one** of the three delivery routes below.
4. Rebuild. Confirm with `ls -l /run/secrets/<name>`.

Removing a key is the same edits in reverse. A leftover entry in the zsh loop for
a secret that no longer exists makes every new shell print an error.

## The three delivery routes

| Route | Wire it up in | Use when |
|---|---|---|
| env var | the export loop in `modules/home/shell/zsh.nix` (`<name>:ENV_VAR`) | a CLI you run from a terminal reads it from the environment |
| read the file | the consuming module | a daemon, launcher-started app or systemd user unit needs it |
| rendered fragment | `sops.templates` in `sops.nix` | a config file must literally contain the secret |

### The template route

`nix.settings` cannot hold the GitHub token — every module ends up
world-readable in `/nix/store`. So `sops.templates."nix-access-tokens.conf"`
renders `access-tokens = github.com=<token>` at activation time (mode 0400), and
`modules/system/core/nix.nix` pulls it in with:

```nix
nix.extraOptions = ''!include ${config.sops.templates."nix-access-tokens.conf".path}'';
```

`!include` rather than `include` on purpose: it tolerates the file being absent,
so nix still works on a fresh boot before sops-nix activation has run. Use the
same shape for any other config file that must embed a secret literally —
`config.sops.placeholder.<name>` inside the template content is what gets
substituted.

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
