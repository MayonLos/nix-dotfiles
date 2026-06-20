_:
{
  sops = {
    # Encrypted secrets live in the repo (safe to commit — they are age-encrypted).
    defaultSopsFile = ../../../secrets/secrets.yaml;
    validateSopsFiles = true;

    # Decryption on this machine uses the host SSH ed25519 key (already present
    # via the openssh service). No extra private key file needs to be deployed.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Each secret is decrypted to /run/secrets/<name>, owned by mayon so the
    # user's shell can read it. Add a line here per new key.
    secrets = {
      deepseek-api-key.owner = "mayon";
    };
  };
}
