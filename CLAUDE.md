# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure automation repository containing **Ansible** roles/playbooks and **Salt Project** states for server provisioning and configuration management. Two independent toolsets targeting Linux server fleets across self-hosted KVM/bare-metal and cloud (AWS/GCP) infrastructure.

## Repository Structure

- `ansible/` — Ansible automation (primary tool), deployed standalone to `~/ansible/` on management machines
  - `inventories/` — Host inventories (`hosts.ini` for services, `init.ini` for bootstrap targets — self-hosted `kvm` group and cloud `cloud_aws`/`cloud_gcp` groups) with `group_vars/` for per-group variables (all, kvm, cloud)
  - `playbooks/` — Playbook entry points (`kvm-init.yml` for self-hosted bootstrap, `cloud-init.yml` for cloud VM bootstrap; `kafka.yml`, `nginx.yml`, `redis.yml`, `rocketmq.yml` for services)
  - `roles/` — Standard Ansible role layout (`tasks/`, `handlers/`, `defaults/`, `vars/`, `templates/`, `files/`)
  - `keys/` — Single `devops.key/devops.pub` key pair authorized for the `devops` user on all managed hosts
  - `ansible.cfg` — Config using `~/ansible/` as deployment root, `~/.ansible/tmp` for runtime temp
  - `.gitignore` — Per-directory gitignore (vault files, retry files, runtime dirs, logs, SSH keys)
- `saltproject/` — Salt states and pillars
  - `base/` — State tree with `top.sls` routing; states use `map.jinja` pattern for OS-family abstraction
  - `pillar/` — Pillar data (`top.sls` routes pillar to minions)
  - `.gitignore` — Per-directory gitignore (pyc files, __pycache__)

## Common Commands

### Ansible

```bash
# Ping hosts using default inventory (hosts per ansible.cfg)
ansible all -m ping

# Run a playbook (default inventory, all hosts)
ansible-playbook playbooks/nginx.yml

# Run a playbook with --limit to target specific groups
ansible-playbook -i inventories/init.ini playbooks/kafka.yml --limit kvm
ansible-playbook -i inventories/init.ini playbooks/redis.yml --limit cloud_aws -e "redis_cluster_enabled=yes"

# Initial server bootstrap (requires vault password)
ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml --limit kvm --vault-id pwd.vault

# Dry run (check mode)
ansible-playbook playbooks/nginx.yml -C

# Vault operations
ansible-vault encrypt_string 'secret' --name 'var_name' --vault-id pwd.vault

# Lint
ansible-lint playbooks/nginx.yml
```

### Salt

```bash
salt '*' test.ping
salt '*' state.apply
salt '*' state.apply <state_name>
```

## Ansible Role Conventions

All roles follow the `ntp` role as the reference standard. When creating or modifying roles, adhere to these conventions:

### File Structure

```
roles/<name>/
├── defaults/main.yml   # User-configurable variables (can be overridden by playbooks)
├── vars/main.yml       # Internal/computed variables only (not user-facing)
├── tasks/
│   ├── main.yml        # Entry point: flat tasks or include_tasks to sub-files
│   ├── install.yml     # (optional) Installation tasks for service roles
│   └── configure.yml   # (optional) Configuration tasks for service roles
├── handlers/main.yml   # Service restart handlers
├── templates/          # Jinja2 templates (.j2)
└── files/              # Static files
```

### Task Naming

- **Short, verb-first, no prefixes**. Do NOT use "Install | xxx" or "Configure | xxx" patterns.
- Good: `"Install dependency packages"`, `"Deploy kafka configuration"`, `"Set directory permissions"`
- Bad: `"Install | ensure dependency packages are installed"`, `"Configure | copy configuration file"`

### Task Structure

- **Flat task lists** — no `block:` wrappers unless error handling (`rescue:`) is needed.
- For service roles, split into `install.yml` + `configure.yml`, included from `main.yml`.
- Service role `main.yml` pattern:
  ```yaml
  - name: Check if <service> is installed
    ansible.builtin.stat:
      path: "{{ <service>_root_path }}"
    register: <service>_installed

  - name: Install <service>
    ansible.builtin.include_tasks: install.yml
    when: not <service>_installed.stat.exists

  - name: Configure <service>
    ansible.builtin.include_tasks: configure.yml
  ```

### Module Usage

- **FQCN required** for all modules: `ansible.builtin.file`, `ansible.builtin.template`, `ansible.builtin.package`, `ansible.builtin.systemd`, `ansible.posix.sysctl`, `community.general.pam_limits`, etc.
- **YAML dict style only** — never inline `key=value` syntax.
- **Mode values** always quoted strings: `'0644'`, `'0755'`, `'0600'`.

### Variables

- `defaults/main.yml`: All user-facing configuration. Prefix with role name (`ntp_servers`, `redis_version`, `sshd_port`). Include descriptive comments.
- `vars/main.yml`: Only internal/computed values that derive from defaults or facts (package names, URLs, paths). These cannot be overridden by playbooks.

### Templates

- Start with `# {{ ansible_managed }}` header.
- Template deploy tasks must include: `owner`, `group`, `mode`, `backup: true`, and `notify` handler.
  ```yaml
  - name: Deploy NTP configuration
    ansible.builtin.template:
      src: chrony.conf.j2
      dest: "{{ ntp_config_file }}"
      owner: root
      group: root
      mode: '0644'
      backup: true
    notify: restart ntp
  ```

### Handlers

- **Lowercase verb-noun** naming: `restart ntp`, `restart kafka`, `restart sshd`.
- Port verification uses `listen:` to chain on the restart handler:
  ```yaml
  - name: restart kafka
    ansible.builtin.systemd:
      name: kafka
      daemon_reload: true
      state: restarted
      enabled: true

  - name: Verify kafka is listening
    ansible.builtin.wait_for:
      host: "{{ host_ip }}"
      port: 9092
      delay: 15
      timeout: 60
      state: started
    listen: restart kafka
  ```

### Anti-patterns to Avoid

- `command: echo` or `debug: + changed_when: true` to trigger handlers — use `notify:` on template/config tasks.
- `always:` blocks solely to fire notifications.
- `with_items:` — use `loop:` instead.
- Inline parameter syntax: `file: path=/etc/foo state=directory`.
- Hardcoded passwords — use Ansible Vault.
- `validate_certs: no` — keep certificate validation enabled.

## Architecture Notes

- **Inventory model**: Hosts grouped by infrastructure type in `inventories/init.ini`: `kvm` for self-hosted, `cloud_aws`/`cloud_gcp` for cloud VMs (aggregated under `cloud`). Playbooks use `hosts: all` and target groups via `--limit kvm | cloud_aws | cloud_gcp`. `inventories/hosts.ini` (ansible.cfg default) retains region-based service groups (`kafka_east`, etc.) as a legacy alternative.
- **Connection model**: Two-tier — `group_vars/all.yml` defines the steady-state default (`devops@2233` + `keys/devops.key`); `group_vars/kvm.yml` and `group_vars/cloud.yml` confirm/override per-group (cloud overrides port to 22). Init playbooks override connection params in their own `vars:` block to bootstrap from the pre-init account.
- **KVM bootstrap** (`playbooks/kvm-init.yml`): Bootstrap as `root@22` with vault-encrypted password. Runs roles in order: hostname → audit → ntp → security → sysctl → user → sshd. Sets `sshd_port: 2233` and `security_allowed_tcp_ports: [2233]` at playbook level to keep firewall and SSH port in sync. The `sshd` role runs last as the point of no return (changes port, disables password auth). After init, the host is reachable as `devops@2233` via key.
- **Cloud bootstrap** (`playbooks/cloud-init.yml`): Bootstrap as the cloud image default user (`ubuntu`) authenticated via `keys/devops.key` — requires `devops.pub` pre-injected at VM creation time. Runs hostname (in `fqdn_short` mode, preserves cloud-assigned FQDN) → audit → ntp → security (firewall disabled, cloud security groups handle it) → sysctl → user. No `sshd` role: SSH stays on 22. After init, the host is reachable as `devops@22` via key.
- **Credentials**: All passwords/secrets use Ansible Vault (`!vault |` encrypted strings). Never store plaintext credentials. Only the KVM bootstrap path needs a password (the initial root password); everything else is key-based.
- **Existing roles**: audit, categraf, fact, hostname, kafka, nginx, ntp, promtail, redis, rocketmq, security, sshd, sysctl, user.
- **Salt states** use the `map.jinja` pattern for cross-platform support (Debian/RedHat).
- **Ansible config** (`ansible.cfg`): 50 forks, SSH pipelining enabled, fact caching to JSON files, `interpreter_python = auto`, paths relative to `~/ansible/`.
- **Gitignore strategy**: Per-directory `.gitignore` files (in `ansible/` and `saltproject/`) instead of root-level, ensuring rules work when directories are deployed standalone.
