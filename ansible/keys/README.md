# SSH Keys

This directory holds SSH key pairs used by Ansible to connect to managed hosts.
Keys are **not** tracked in version control (see `.gitignore`).

## Generate a key pair

```bash
# Ed25519 (recommended)
ssh-keygen -t ed25519 -C 'ansible@east' -f ansible/keys/east.key -N ""

# RSA 4096 (if Ed25519 is not supported)
ssh-keygen -t rsa -b 4096 -C 'ansible@east' -f ansible/keys/east.key -N ""
```

Repeat for each region, replacing `east` with the region name (e.g. `west`).

## Expected files

| File       | Purpose                      |
|------------|------------------------------|
| east.key   | East region private key      |
| east.pub   | East region public key       |
| west.key   | West region private key      |
| west.pub   | West region public key       |

## Security notes

- Private keys (`*.key`) must have mode `0600`.
- Never commit private keys to version control.
- Rotate keys periodically and after any suspected compromise.
