# SSH Keys

This directory holds SSH key pairs used by Ansible to connect to managed hosts.
Keys are **not** tracked in version control (see `.gitignore`).

## Generate a key pair

```bash
# Generate Ed25519 key pair
ssh-keygen -t ed25519 -C 'ansible@east' -f ansible/keys/east.key -N ""
# Then copy the public key to target hosts:
ssh-copy-id -i ansible/keys/east.pub user@host

# Generate Ed25519 key pair
ssh-keygen -t ed25519 -C 'ansible@west' -f ansible/keys/west.key -N ""
# Then copy the public key to target hosts:
ssh-copy-id -i ansible/keys/west.pub user@host
```

Repeat for each region, replacing `east` with the region name (e.g. `west`).

## Expected files

| File     | Purpose                 |
| -------- | ----------------------- |
| east.key | East region private key |
| east.pub | East region public key  |
| west.key | West region private key |
| west.pub | West region public key  |

## Security notes

- Private keys (`*.key`) must have mode `0600`.
- Never commit private keys to version control.
- Rotate keys periodically and after any suspected compromise.
