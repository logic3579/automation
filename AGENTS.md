# Repository Guidelines

## Project Structure & Module Organization
This repository contains two independent automation stacks. `ansible/` is the primary path for provisioning and service rollout: `playbooks/` holds entry points such as `init.yml`, `nginx.yml`, and `redis.yml`; `roles/` uses the standard role layout; `inventories/` contains `hosts.ini` (services) and `init.ini` (bootstrap targets, both self-hosted and cloud), plus `group_vars/` split by region. `saltproject/` contains Salt states in `base/` and pillar data in `pillar/`. Keep changes inside the matching role or state tree instead of adding root-level scripts.

## Build, Test, and Development Commands
Run Ansible commands from `ansible/` unless noted otherwise.

- `ansible all -m ping` checks connectivity with the default inventory from `ansible.cfg`.
- `ansible-playbook -i inventories/init.ini playbooks/nginx.yml --limit kvm` applies a service playbook to one inventory group.
- `ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml --limit kvm --vault-id pwd.vault` bootstraps new self-hosted KVM/bare-metal hosts.
- `ansible-playbook playbooks/nginx.yml -C --list-tasks` previews changes and task flow.
- `ansible-lint playbooks/nginx.yml` validates playbooks and role usage.
- `ansible-galaxy collection install -r requirements.yml` installs required collections.
- `salt '*' state.apply` runs Salt states from `saltproject/` on connected minions.

## Coding Style & Naming Conventions
Use YAML with two-space indentation. For Ansible, always use FQCN modules such as `ansible.builtin.template`, dictionary-style arguments, quoted file modes like `'0644'`, and `loop:` instead of `with_items`. Task names should be short, verb-first, and without prefixes: `Deploy nginx configuration`, not `Configure | deploy nginx configuration`. Prefix user-facing variables with the role name, for example `redis_version` or `sshd_port`.

Role structure should follow the existing `ntp` pattern: `defaults/main.yml` for overridable variables, `vars/main.yml` for internal computed values, `tasks/main.yml` as the entry point, and optional `tasks/install.yml` plus `tasks/configure.yml` for service roles. Prefer flat task lists; use `block:` only when `rescue:` or `always:` is actually needed.

## Testing Guidelines
Prefer dry runs before live changes: `ansible-playbook <playbook> -C`. Role smoke tests live under `ansible/roles/*/tests/test.yml`; keep new tests in that path and start with localhost coverage. Validate templates, handlers, and inventory targeting before changing bootstrap roles such as `security` or `sshd`, because `playbooks/kvm-init.yml` changes SSH access and firewall behavior.

## Commit & Pull Request Guidelines
Recent history uses Conventional Commit prefixes: `feat:`, `fix:`, `refactor:`, `chore:`. Follow that format and keep each commit scoped to one role, playbook, or Salt state family. Pull requests should explain the operational impact, list affected inventories or groups, note any vault or key handling changes, and include representative commands used for validation.

## Architecture Notes
Inventory is organized by region, with service groups such as `nginx_east` or `redis_east`. Playbooks typically target `hosts: all` and narrow execution with `--limit`. In `playbooks/kvm-init.yml`, role order matters: bootstrap runs from `hostname` through `sshd`, and `sshd` is intentionally last because it changes the port and disables password login. Keep `sshd_port` and firewall settings aligned when editing bootstrap behavior.

## Security & Configuration Tips
Do not commit plaintext secrets or private keys. Store credentials with Ansible Vault, keep key files under `ansible/keys/` as examples only, and avoid patterns already treated as anti-patterns in this repo: inline `key=value` module syntax, fake handler triggers with `command: echo`, hardcoded passwords, or `validate_certs: no` without a documented reason. For templates, include `# {{ ansible_managed }}` and set `owner`, `group`, `mode`, `backup: true`, and a `notify` handler.
