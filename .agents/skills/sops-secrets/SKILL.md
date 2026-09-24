---
name: sops-secrets
description: 增删或轮换 sops 加密凭据；配置运行时秘密文件/模板，排查 shell、服务和桌面应用的凭据传递。
---

# Sops-nix secrets

| File | Purpose |
|---|---|
| `secrets/secrets.yaml` | Encrypted source file; inspect decrypted values only as needed for an authorized secret edit, never print them in logs |
| `.sops.yaml` | Age recipients and encryption rules |
| `modules/system/security/sops.nix` | Decryption key path, secret ownership, and rendered templates |
| `modules/home/shell/zsh.nix` | Interactive-shell secret export loop |
| `modules/system/core/nix.nix` | Runtime include for Nix access-token configuration |

Secrets decrypt at activation to runtime files under `/run/secrets/`. Check the current module for owner, mode, and paths rather than assuming every secret has identical metadata. Decryption on the host uses its SSH host key; editing requires the authorized age identity.

## Adding or changing a credential

1. Add or update the value through `sops secrets/secrets.yaml`; keep plaintext inside the authorized editing flow, not in an unencrypted repository file or tool output.
2. Declare the secret and its owner in `modules/system/security/sops.nix`.
3. Choose the delivery route below based on how the consumer starts and reads credentials.
4. Format and evaluate the configuration. After activation, check file metadata and consumer behavior without displaying the value.

When removing a credential, remove its declaration and delivery wiring. A stale entry in the zsh export loop may attempt to read a nonexistent runtime file.

## Choose a delivery route

- **Interactive CLI:** add a `secret-name:ENV_VAR` mapping to the loop in `zsh.nix`. This only reaches processes started from that interactive shell.
- **Service, desktop launcher, or compositor app:** have the consumer read its `/run/secrets/<name>` file, or explicitly configure the unit to read it. These processes do not source interactive zsh startup.
- **A configuration file must contain the value:** render it with a `sops.templates` entry and reference the template's runtime path. Set ownership and mode for the consuming service.

The GitHub token used by Nix is delivered through a rendered runtime fragment included with `!include` in `nix.extraOptions`. Keep it out of `nix.settings`: Nix module values are stored in world-readable paths. The optional include tolerates the template not existing before sops-nix activation during startup.

## Safety and verification

- Never put plaintext credentials in `.nix` files, Home Manager session variables, shell startup files, or derivation arguments; those can become visible in the Nix store or process metadata.
- Keep both the host decryption key and personal age key outside the repository.
- Confirm `/run/secrets/<name>` exists and has the intended owner/mode with metadata-only commands. Test that the actual consumer authenticates without printing its environment or secret contents.
- When an interactive command works but a launched app does not, first check how that app receives its environment. Prefer a runtime file for services and launcher-started processes.
