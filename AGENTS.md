# Repository Guidelines

## Project Structure & Module Organization
This repository contains two independent infrastructure automation stacks. `ansible/` is the primary path for provisioning, host bootstrap, and service rollout. `saltproject/` contains Salt states and pillar examples.

Ansible is organized as a standalone deployable tree:

- `ansible/ansible.cfg` assumes the tree is deployed under `~/ansible/`, uses `inventories/hosts.ini` by default, enables SSH pipelining, uses 50 forks, and caches facts under `~/ansible/cache`.
- `ansible/inventories/init.ini` is for bootstrap targets: `kvm` for self-hosted KVM/bare-metal hosts, `cloud_aws` and `cloud_gcp` for cloud VMs, aggregated under `cloud`. Current KVM bootstrap ranges are `10.0.0.[1:255]`, `10.0.1.[1:255]`, and `10.0.2.[1:255]`; cloud ranges are `10.64.0-2.[1:255]` for AWS and `10.128.0-2.[1:255]` for GCP.
- `ansible/inventories/hosts.ini` is the default service inventory and groups KVM service targets with a `_kvm` suffix: `kafka_kvm`, `nginx_kvm`, `redis_kvm`, and `rocketmq_kvm`.
- `ansible/inventories/group_vars/` defines steady-state connection settings and cloud/provider overrides. Default post-init access is `devops@2233` using `keys/devops.key`; cloud hosts override SSH to port `22` and provider NTP servers.
- `ansible/playbooks/` contains entry points: `kvm-init.yml`, `cloud-init.yml`, `kafka.yml`, `nginx.yml`, `redis.yml`, and `rocketmq.yml`.
- `ansible/roles/` contains standard roles: `audit`, `categraf`, `fact`, `hostname`, `kafka`, `nginx`, `ntp`, `promtail`, `redis`, `rocketmq`, `security`, `sshd`, `sysctl`, and `user`.
- `ansible/keys/` is for example key material only; do not commit private keys or real secrets.

Salt is organized under `saltproject/`:

- `saltproject/base/` contains states and formulas such as `core`, `packages`, `ssh`, `template`, `apache`, and `mysql`, with `map.jinja` patterns for OS-family abstraction.
- `saltproject/pillar/` contains pillar data: `default.sls`, `apache.sls`, `mysql.sls`, and `top.sls`.
- `saltproject/base/top.sls` is partly illustrative and references some states not currently present in the tree. Verify target states before applying Salt highstate.

Keep changes inside the matching role, playbook, inventory, state, or pillar tree. Avoid adding root-level scripts.

## Build, Test, and Development Commands
Project-local shell commands should be prefixed with `rtk`, per the local Codex instruction file.

Run Ansible commands from `ansible/` unless noted otherwise:

- `rtk ansible all -m ping` checks connectivity using the default inventory from `ansible.cfg`.
- `rtk ansible-galaxy collection install -r requirements.yml` installs required collections (`ansible.posix`, `community.general`).
- `rtk ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml --limit kvm --vault-id pwd.vault` bootstraps self-hosted KVM/bare-metal hosts.
- `rtk ansible-playbook -i inventories/init.ini playbooks/cloud-init.yml --limit cloud_aws` bootstraps AWS cloud hosts.
- `rtk ansible-playbook -i inventories/init.ini playbooks/cloud-init.yml --limit cloud_gcp` bootstraps GCP cloud hosts.
- `rtk ansible-playbook playbooks/nginx.yml --limit nginx_kvm` applies a service playbook to a KVM service group from the default inventory.
- `rtk ansible-playbook playbooks/nginx.yml -C --list-tasks` previews changes and task flow.
- `rtk ansible-lint playbooks/nginx.yml` validates playbooks and role usage.

Salt commands are normally run from `saltproject/` or on a configured Salt master:

- `rtk salt '*' test.ping` checks minion connectivity.
- `rtk salt '*' state.apply` applies highstate.
- `rtk salt '*' state.apply core` applies a specific state.

## Coding Style & Naming Conventions
Use YAML with two-space indentation. For Ansible, always use FQCN modules such as `ansible.builtin.template`, `ansible.builtin.file`, `ansible.posix.sysctl`, and `community.general.pam_limits`. Use dictionary-style arguments, quoted file modes like `'0644'`, and `loop:` instead of `with_items`.

Task names should be short, verb-first, and without artificial prefixes: `Deploy nginx configuration`, not `Configure | deploy nginx configuration`.

Prefix user-facing variables with the role name, such as `redis_version`, `sshd_port`, `security_allowed_tcp_ports`, or `promtail_loki_url`.

Role structure should follow the existing `ntp` pattern:

- `defaults/main.yml` for overridable user-facing variables.
- `vars/main.yml` for internal or computed values.
- `tasks/main.yml` as the entry point.
- Optional `tasks/install.yml` and `tasks/configure.yml` for service roles.
- `handlers/main.yml` for service restart/reload handlers.
- `templates/` for Jinja templates and `files/` for static assets.

Prefer flat task lists. Use `block:` only when `rescue:` or `always:` is actually needed.

## Architecture Notes
The Ansible inventory model has two active paths:

- `inventories/init.ini` targets bootstrap by infrastructure type. Use `--limit kvm`, `--limit cloud_aws`, or `--limit cloud_gcp`.
- `inventories/hosts.ini` is the default service inventory for KVM service rollout. Service groups use the `_kvm` suffix and map into the KVM bootstrap address space: Kafka and Nginx use `10.0.0.*`, Redis uses `10.0.1.*`, and RocketMQ uses `10.0.2.*`. The old `east` and `west` aggregate groups are no longer used.

Most playbooks use `hosts: all` and rely on inventory plus `--limit` to narrow execution.

Connection behavior is two-tiered:

- Steady state defaults come from `group_vars/all.yml`: `devops`, SSH port `2233`, and `keys/devops.key`.
- Cloud steady state comes from `group_vars/cloud.yml`: `devops`, SSH port `22`, `keys/devops.key`, and UTC timezone.
- KVM initialization overrides connection variables in `playbooks/kvm-init.yml` to use `root@22` with a vault-encrypted password.
- Cloud initialization overrides connection variables in `playbooks/cloud-init.yml` to use the image default user, currently `ubuntu`, with `keys/devops.key`.

Bootstrap role order matters:

- `playbooks/kvm-init.yml` runs `hostname`, `audit`, `ntp`, `security`, `sysctl`, `user`, then `sshd`. `sshd` is intentionally last because it changes SSH access: port `2233`, no password auth, and key-based `devops` login. Keep `sshd_port` and `security_allowed_tcp_ports` aligned.
- `playbooks/cloud-init.yml` runs `hostname`, `audit`, `ntp`, `security`, `sysctl`, and `user`. It does not run `sshd`; SSH remains on port `22`, and cloud firewall/security groups are expected to handle network policy.

Service playbooks install or configure `kafka`, `nginx`, `redis`, and `rocketmq`. Kafka, Redis, and RocketMQ run with `serial: 1`; Redis supports standalone and cluster mode through `redis_cluster_enabled`.

## Testing Guidelines
Prefer dry runs before live changes: `rtk ansible-playbook <playbook> -C`. Use `--list-tasks` and `--list-tags` when changing role inclusion, bootstrap ordering, or inventory targeting.

Role smoke tests live under `ansible/roles/*/tests/test.yml`; keep new tests in that path and start with localhost coverage where possible.

Validate templates, handlers, and inventory targeting before changing bootstrap roles such as `security` or `sshd`, because `playbooks/kvm-init.yml` changes SSH access and firewall behavior.

When working with Salt, inspect `saltproject/base/top.sls` before applying highstate because some match targets reference illustrative or currently absent states.

## Commit & Pull Request Guidelines
Recent history uses Conventional Commit prefixes: `feat:`, `fix:`, `refactor:`, and `chore:`. Follow that format and keep each commit scoped to one role, playbook, inventory change, Salt state family, or pillar family.

Pull requests should explain the operational impact, list affected inventories or groups, note vault or key handling changes, and include representative validation commands.

## Security & Configuration Tips
Do not commit plaintext secrets, private keys, real vault passwords, or production credentials. Use Ansible Vault for secrets. Existing placeholder vault values such as `REPLACE_WITH_VAULT_ENCRYPTED_VALUE` must be replaced with encrypted values before live use.

Avoid patterns already treated as anti-patterns in this repo:

- Inline `key=value` module syntax.
- Fake handler triggers with `command: echo`, `debug`, or forced changed status.
- Hardcoded passwords.
- `validate_certs: no` without a documented reason.
- `with_items`.

For templates, include `# {{ ansible_managed }}` and set `owner`, `group`, `mode`, `backup: true`, and a real `notify` handler.
