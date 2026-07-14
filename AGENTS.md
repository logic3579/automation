# Repository Guidelines

## Project Structure & Module Organization

This repository contains infrastructure automation for two independent stacks. `ansible/` is the primary Ansible workspace: `playbooks/` holds bootstrap and service entry points, `roles/` uses the standard role layout, and `inventories/` contains the explicit bootstrap source `init.ini`, steady-state provider files (`kvm.ini`, `aws.ini`, `gcp.ini`, `aliyun.ini`, `tencent.ini`, and `vultr.ini`), and explicit cloud dynamic sources such as `aws_proj_dev.aws_ec2.yml`. Matching provider or account `group_vars/` files own connection and privilege-escalation configuration; there is no shared `cloud` group. The Python control environment and AWS SDK dependencies are declared by `pyproject.toml`, `.python-version`, and `uv.lock`; Galaxy collections remain declared in `requirements.yml`. `saltproject/` contains Salt content: `base/` for states and formulas, `pillar/` for pillar data, plus `master.conf` and `minion.conf`.

## Build, Test, and Development Commands

Run Ansible commands from `ansible/` so `ansible.cfg` relative paths resolve correctly. macOS and Linux use the same uv-managed environment; do not install project Ansible tools globally.

```bash
cd ansible/
uv sync --frozen
uv run ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force
uv run ansible all -m ping
uv run ansible-playbook playbooks/nginx.yml -C
uv run ansible-playbook playbooks/debug.yml --ask-vault-pass
uv run ansible-lint --offline playbooks/ roles/
```

`uv run` is the default for documentation and automation. In an interactive shell, `source .venv/bin/activate` allows the same commands to run without the prefix until `deactivate`. Without `-p`, `ansible-galaxy` installs collections under `~/.ansible/collections` by default.

The default inventory is only `inventories/kvm.ini`. Every cloud provider source must be selected explicitly with `-i`, and `init.ini` must never be added to the default. `aws_proj_dev.aws_ec2.yml` is an explicit dynamic source for running EC2 instances; AWS host variables use the `aws_` prefix, and matching group vars connect as `ssm-user` through EC2 Instance Connect and SSH over Session Manager using `keys/aws_ssm_key`. Bootstrap commands pass `-i inventories/init.ini`. `kvm-init.yml` targets `kvm`, fixes its bootstrap connection at `root@22`, stores the password as an `ansible_ssh_pass: !vault` value, and requires `--vault-id pwd.vault`; provider bootstrap overrides the image's initial connection through extra vars, for example `-e "ansible_user=ubuntu ansible_port=22"`. Service playbooks set `become: true` when required but must not hardcode `remote_user` or `become_method`; inventory variables decide both.

Use check mode (`-C`) before changing remote hosts. For Salt, validate connectivity and state application with `salt '*' test.ping`, `salt '*' state.apply`, or `salt '*' state.apply <state_name>`.

## Coding Style & Naming Conventions

Ansible tasks must use fully qualified module names such as `ansible.builtin.template`. Use YAML dictionary style, not inline `key=value` syntax. Prefer double quotes only when needed; always quote file modes as strings, for example `"0644"`. Role directory names must match `^[a-z][a-z0-9_]*$`; use `sing_box`, not `sing-box`. Role variables in `defaults/main.yml` should be user-facing and prefixed with the role name, such as `redis_version`; `vars/main.yml` is for internal computed values. Task names should be short, verb-first, and unprefixed, for example `Install dependency packages`. Handlers use capitalized verb-noun names such as `Restart nginx`.

## Testing Guidelines

Role smoke tests live under `ansible/roles/<role>/tests/` with `inventory` and `test.yml`. Run targeted syntax and dry-run checks before deployment:

```bash
cd ansible/
uv run ansible-playbook roles/nginx/tests/test.yml --syntax-check
uv run ansible-playbook playbooks/redis.yml --limit redis_cluster_kvm -C
```

Keep tests and examples aligned with the role being changed. Run `uv run ansible-lint --offline playbooks/ roles/` before submitting changes.

## Commit & Pull Request Guidelines

Follow the existing Conventional Commit style seen in history: `fix(lint): ...`, `refactor(inventory): ...`, `chore: ...`, `docs: ...`. Keep commits focused on one role, playbook, or behavior change when possible.

Pull requests should include a short summary, affected hosts or groups, commands run, and deployment risk notes. Link related issues or tickets. Include screenshots only for rendered documentation or UI-adjacent output.

## Security & Configuration Tips

Never commit plaintext credentials, private keys, vault passwords, or generated runtime files. Use Ansible Vault for secrets and pass vault material at runtime with `--vault-id <path>` or `--ask-vault-pass`. Keep `ansible/keys/` limited to tracked documentation unless explicitly rotating approved public key material.
