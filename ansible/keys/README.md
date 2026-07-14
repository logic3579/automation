# SSH Keys

This directory holds SSH key pairs used by Ansible to connect to managed hosts.
Keys are **not** tracked in version control (see `.gitignore`).

## Generate a key pair

Run these commands from the `ansible/` directory.

```bash
# Steady-state devops key
ssh-keygen -t ed25519 -C 'devops@ansible' -f ./keys/devops_key -N ""

# AWS SSH-over-SSM key
ssh-keygen -t ed25519 -C 'aws-ssm@ansible' -f ./keys/aws_ssm_key -N ""

chmod 600 ./keys/devops_key ./keys/aws_ssm_key
chmod 644 ./keys/devops_key.pub ./keys/aws_ssm_key.pub
```

## Distribution

The `devops_key.pub` is the persistent public key authorized for the `devops`
user. The AWS-specific key is injected temporarily for each connection.

- **KVM / bare-metal**: `playbooks/kvm-init.yml` reads `keys/devops_key.pub` and
  deploys it to `~devops/.ssh/authorized_keys` via the `user` role.
- **Cloud (AWS/GCP)**: `devops_key.pub` must be pre-injected to the cloud image's
  default user (e.g. `ubuntu`) at VM creation time, so that
  `playbooks/cloud-init.yml` can authenticate with `devops_key` to provision
  the `devops` user.
- **AWS EC2 Instance Connect + SSM**: `aws_ssm_key.pub` is sent to the target
  OS user by EC2 Instance Connect for each SSH connection. The matching
  `aws_ssm_key` authenticates SSH, while Session Manager carries the SSH
  connection without requiring an inbound SSH port.

## Expected files

| File            | Purpose                                      |
| --------------- | -------------------------------------------- |
| devops_key      | Steady-state devops SSH private key          |
| devops_key.pub  | Steady-state devops SSH public key           |
| aws_ssm_key     | AWS EC2 Instance Connect SSH private key     |
| aws_ssm_key.pub | AWS EC2 Instance Connect SSH public key      |

## Security notes

- Private keys (for example, `devops_key` and `aws_ssm_key`) must have mode
  `0600`.
- Never commit private keys to version control.
- Rotate keys periodically and after any suspected compromise.
