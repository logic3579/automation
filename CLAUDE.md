# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure automation repository containing **Ansible** roles/playbooks and **Salt Project** states for server provisioning and configuration management. Two independent toolsets targeting Linux server fleets organized by geographic region (east/west).

## Repository Structure

- `ansible/` — Ansible automation (primary tool), deployed standalone to `~/ansible/` on management machines
  - `inventories/` — Host inventories (`init.hosts`, `test.hosts`, `prod.hosts`) with `group_vars/` for per-group variables (all, east, west, init)
  - `playbooks/` — Playbook entry points (`init.yml` for new server bootstrap; `kafka.yml`, `nginx.yml`, `redis.yml`, `rocketmq.yml` for services; `example.yml` for reference)
  - `roles/` — Standard Ansible role layout (`tasks/`, `handlers/`, `defaults/`, `vars/`, `templates/`, `files/`)
  - `keys/` — SSH keys for east/west regions
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

# Ping specific hosts
ansible -i inventories/prod.hosts east -m ping

# Run a playbook (default inventory)
ansible-playbook playbooks/nginx.yml

# Run a playbook against specific hosts
ansible-playbook -i inventories/prod.hosts playbooks/redis.yml -e "hosts_var=172.16.1.1"

# Initial server bootstrap (requires vault password)
ansible-playbook -i inventories/init.hosts --vault-id pwd.vault -e "hosts_var=10.0.10.12" playbooks/init.yml

# Dry run (check mode)
ansible-playbook playbooks/example.yml -C

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

- **Inventory model**: Hosts grouped by region (`east`, `west`) with sub-groups for function (`dbservers`, `webservers`). Group vars in `inventories/group_vars/` set region-specific SSH keys, ports, and credentials.
- **Global defaults** in `group_vars/all.yml`: custom SSH port (300), `ansible` user with key-based auth, vault-encrypted become password.
- **Credentials**: All passwords/secrets use Ansible Vault (`!vault |` encrypted strings). Never store plaintext credentials.
- **Existing roles**: audit, categraf, fact, kafka, nginx, ntp, promtail, redis, rocketmq, security, sshd, sysctl.
- **Salt states** use the `map.jinja` pattern for cross-platform support (Debian/RedHat).
- **Ansible config** (`ansible.cfg`): 50 forks, SSH pipelining enabled, fact caching to JSON files, `interpreter_python = auto`, paths relative to `~/ansible/`.
- **Gitignore strategy**: Per-directory `.gitignore` files (in `ansible/` and `saltproject/`) instead of root-level, ensuring rules work when directories are deployed standalone.
