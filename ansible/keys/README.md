# SSH Keys

This directory holds SSH key pairs used by Ansible to connect to managed hosts.
Keys are **not** tracked in version control (see `.gitignore`).

## Generate a key pair

```bash
# Generate Ed25519 key pair
ssh-keygen -t ed25519 -C 'devops@ansible' -f ansible/keys/devops.key -N ""
```

## Distribution

The `devops.pub` is the only public key authorized for the `devops` user.

- **KVM / bare-metal**: `playbooks/kvm-init.yml` reads `keys/devops.pub` and
  deploys it to `~devops/.ssh/authorized_keys` via the `user` role.
- **Cloud (AWS/GCP)**: `devops.pub` must be pre-injected to the cloud image's
  default user (e.g. `ubuntu`) at VM creation time, so that
  `playbooks/cloud-init.yml` can authenticate with `devops.key` to provision
  the `devops` user.

## Expected files

| File       | Purpose            |
| ---------- | ------------------ |
| devops.key | devops private key |
| devops.pub | devops public key  |

## Security notes

- Private keys (`*.key`) must have mode `0600`.
- Never commit private keys to version control.
- Rotate keys periodically and after any suspected compromise.
