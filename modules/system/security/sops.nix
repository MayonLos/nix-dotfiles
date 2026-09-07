{ config, ... }:
{
  sops = {
    defaultSopsFile = ../../../secrets/secrets.yaml;
    validateSopsFiles = true;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      deepseek-api-key.owner = "mayon";
      github-token.owner = "mayon";
    };

    # access-tokens cannot live in nix.settings: every module ends up
    # world-readable in /nix/store. Render it into a fragment that
    # /etc/nix/nix.conf !includes instead (see modules/system/core/nix.nix).
    templates."nix-access-tokens.conf" = {
      content = "access-tokens = github.com=${config.sops.placeholder.github-token}\n";
      owner = "mayon";
      mode = "0400";
    };
  };
}
