# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure automation repository containing **Ansible** roles/playbooks and **Salt Project** states for server provisioning and configuration management. Two independent toolsets targeting Linux server fleets across self-hosted KVM/bare-metal, cloud (AWS/GCP), and third-party VPS infrastructure.

## Repository Structure

- `ansible/` — Ansible automation (primary tool), deployed standalone to `~/ansible/` on management machines
  - `inventories/` — Flat inventory sources split by provider.
    - **`init.ini`** is the explicit bootstrap source with `kvm`, `aws`, `gcp`, `aliyun`, `tencent`, and `vultr` groups. It is never part of the default inventory. `kvm-init.yml` fixes bootstrap at `root@22`; provider bootstrap overrides the image's initial connection through extra vars.
    - **`kvm.ini`, `aws.ini`, `gcp.ini`, `aliyun.ini`, `tencent.ini`, `vultr.ini`** are steady-state sources explicitly listed in `ansible.cfg`. Service topology groups follow `<service>_<topology>_<provider>` and provider parent groups aggregate their own children. There is no shared `cloud` group.
    - `group_vars/` has one matching file per provider. Each provider owns its connection, become method, timezone, and NTP configuration; `all.yml` contains only genuine global values.
  - `playbooks/` — Bootstrap (`kvm-init.yml`, `cloud-init.yml`), service (`kafka.yml`, `nginx.yml`, `redis.yml`, `rocketmq.yml`, `docker.yml`, `xray.yml`, `sing-box.yml`), and developer-utility (`debug.yml`) entry points.
  - `roles/` — Standard Ansible role layout (`tasks/`, `handlers/`, `defaults/`, `vars/`, `templates/`, `files/`)
  - `keys/` — Single `devops_key/devops_key.pub` key pair authorized for the `devops` user on all managed hosts
  - `pyproject.toml` / `.python-version` / `uv.lock` — uv-managed Python 3.13 control environment with locked `ansible-core` and `ansible-lint` dependencies
  - `requirements.yml` — Ansible Galaxy collection dependencies, installed under `~/.ansible/collections` by default
  - `ansible.cfg` — Paths resolved relative to the cfg file (steady-state provider inventories, `roles/`); user-shared state lives under `~/.ansible/` (`cache/`, `ansible.log`). Smart gathering, `result_format=yaml`, profile_tasks + timer callbacks, force_handlers, pipelined SSH.
  - `.gitignore` — Per-directory gitignore (`.venv`, vault files, retry files, runtime dirs, all of `keys/` except `keys/README.md`)
- `saltproject/` — Salt states and pillars
  - `base/` — State tree with `top.sls` routing; states use `map.jinja` pattern for OS-family abstraction
  - `pillar/` — Pillar data (`top.sls` routes pillar to minions)
  - `.gitignore` — Per-directory gitignore (pyc files, __pycache__)

## Common Commands

### Ansible

Run these commands from `ansible/`. Use `uv run` in documentation, scripts, and
automation; an interactive shell may instead run `source .venv/bin/activate`
after `uv sync --frozen` and omit the prefix until `deactivate`.

```bash
# Reproduce the locked Python environment and install Galaxy collections
uv sync --frozen
uv run ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections --force

# Ping hosts using default inventory (hosts per ansible.cfg)
uv run ansible all -m ping

# Run a playbook (default inventory, all hosts)
uv run ansible-playbook playbooks/nginx.yml

# Service deployment uses the default provider inventories (no -i needed)
uv run ansible-playbook playbooks/kafka.yml --limit kafka_standalone_kvm
uv run ansible-playbook playbooks/kafka.yml --limit kafka_cluster_kvm -e "kafka_cluster_enabled=yes"
uv run ansible-playbook playbooks/redis.yml --limit redis_cluster_kvm -e "redis_cluster_enabled=yes"
uv run ansible-playbook playbooks/rocketmq.yml --limit rocketmq_failover_kvm -e "rocketmq_mode=failover"
uv run ansible-playbook playbooks/docker.yml --limit kvm

# Reverse-proxy / Vultr deployment (after cloud-init.yml)
uv run ansible-playbook playbooks/xray.yml --limit vultr --vault-id pwd.vault
uv run ansible-playbook playbooks/sing-box.yml --limit vultr --vault-id pwd.vault -e "sing_box_protocol=vless-reality"

# Bootstrap (explicit init.ini; KVM uses Vault, providers override the image user)
uv run ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml --vault-id pwd.vault
uv run ansible-playbook -i inventories/init.ini playbooks/cloud-init.yml --limit aws -e "ansible_user=ubuntu ansible_port=22"
uv run ansible-playbook -i inventories/init.ini playbooks/cloud-init.yml --limit vultr -e "ansible_user=ubuntu ansible_port=22"

# Dry run (check mode)
uv run ansible-playbook playbooks/nginx.yml -C

# Local debug toolkit (vault / inventory / facts / lookup / templating smoke tests on localhost)
uv run ansible-playbook playbooks/debug.yml --ask-vault-pass
uv run ansible-playbook playbooks/debug.yml --tags facts          # single section
uv run ansible-playbook playbooks/debug.yml -e target=kafka_cluster_kvm   # against a remote group

# Vault operations
uv run ansible-vault encrypt_string 'secret' --name 'var_name' --vault-id pwd.vault

# Lint (must run from the ansible/ directory so the relative paths in ansible.cfg resolve)
uv run ansible-lint --offline playbooks/ roles/
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

Role directory names must match `^[a-z][a-z0-9_]*$`. Use underscores for
multi-word role identifiers (`sing_box`), while external product, package,
service, and playbook names may retain their native hyphen (`sing-box`).

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
- **Quote style**: follow ansible-lint's suggested `yaml.quoted-strings` config (`quote-type: double`, `required: only-when-needed`). Mode values **must** be quoted with double quotes — `"0644"`, `"0755"`, `"0600"` — to prevent YAML loaders from parsing octals as integers. Jinja2 expressions also use double quotes: `"{{ var }}"`. Single quotes only when escape semantics must be avoided.

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
      mode: "0644"
      backup: true
    notify: Restart ntp
  ```

### Handlers

- **Capitalized verb-noun** naming (ansible-lint `name[casing]` rule): `Restart ntp`, `Restart kafka`, `Restart sshd`. All `notify:` and `listen:` references must match exactly.
- Port verification uses `listen:` to chain on the restart handler:
  ```yaml
  - name: Restart kafka
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
    listen: Restart kafka
  ```

### Anti-patterns to Avoid

- `command: echo` or `debug: + changed_when: true` to trigger handlers — use `notify:` on template/config tasks.
- `always:` blocks solely to fire notifications.
- `with_items:` — use `loop:` instead.
- Inline parameter syntax: `file: path=/etc/foo state=directory`.
- Hardcoded passwords — use Ansible Vault.
- `validate_certs: no` — keep certificate validation enabled.

## Architecture Notes

- **Inventory model**: `ansible.cfg` explicitly lists the six steady-state provider files, keeping `inventories/init.ini` out of routine commands. `init.ini` uses the same provider group names and is selected only with `-i`. Provider files are independent; no `cloud` roll-up or shared cloud variables exist. Service leaf groups follow `<service>_<topology>_<provider>` and may be aggregated under their provider with `:children`.
- **Connection model**: Inventory owns `ansible_user`, `ansible_port`, `ansible_ssh_private_key_file`, `ansible_become_method`, and `ansible_become_user` for steady-state operations. Every service playbook only declares `become: true`; it must not hardcode `remote_user` or `become_method`. `group_vars/all.yml` contains no connection defaults. KVM bootstrap is the explicit exception with fixed play-level `root@22`; provider bootstrap uses extra vars to override the image's initial account.
- **KVM bootstrap** (`playbooks/kvm-init.yml`): Invoke the explicit bootstrap inventory with `--vault-id pwd.vault`; the playbook targets `kvm`, fixes `ansible_user: root` plus `ansible_port: 22`, and stores the root password as an `ansible_ssh_pass: !vault` placeholder that must be re-encrypted. It runs hostname → audit → ntp → security → sysctl → user → sshd. `sshd_port: 2233` and `security_allowed_tcp_ports: [2233]` keep firewall and SSH in sync. The `sshd` role runs last as the point of no return. After init, `group_vars/kvm.yml` connects as `devops@2233` via key and escalates with sudo.
- **Provider bootstrap** (`playbooks/cloud-init.yml`): AWS, GCP, Aliyun, Tencent, and Vultr use one bootstrap playbook. Select the provider in `init.ini` and pass its image user through extra vars, for example `--limit aws -e "ansible_user=ubuntu ansible_port=22"`. The image must have `devops_key.pub` pre-injected. The play runs hostname (`fqdn_short`) → audit → ntp → security (host firewall disabled) → sysctl → user → sshd. After init, the matching provider `group_vars` connects as `devops@22` and escalates with sudo.
- **Cluster mode toggles**:
  - **Kafka** — `kafka_cluster_enabled` (`"no"` default → replication=1 for single-broker; `"yes"` → replication=3 for 3-node KRaft). Config path is `config/server.properties` (Kafka 4.x consolidated the legacy `config/kraft/` subdir).
  - **Redis** — `redis_cluster_enabled` (`"no"` default → single port 6379; `"yes"` → 6 instances on ports 7001-7006 across 3 hosts with `--cluster-replicas 1` for 3M3S).
  - **RocketMQ** — `rocketmq_mode` (`standalone` | `2m-2s-sync` | `failover`). 2m-2s-sync cross-pairs slaves: slave on host_i protects master on host_(i+1)%N. Failover uses DLedger with `dLegerPeers` derived from `ansible_play_batch`.
- **Multi-distro role pattern** (used by `docker` and `sing_box`): tasks/main.yml first runs `include_vars: "{{ ansible_facts.os_family }}.yml"` to load `vars/Debian.yml` or `vars/RedHat.yml` (package repo URL, GPG key path, etc.); then `install.yml` includes `install-debian.yml` or `install-redhat.yml` via `when: ansible_facts.os_family == "<family>"`. Shared package list lives in `vars/main.yml`. `xray` bypasses this — its upstream `install-release.sh` script handles distro detection itself.
- **Fact access**: Use `ansible_facts.<name>` (e.g. `ansible_facts.os_family`, `ansible_facts.default_ipv4.address`) rather than the top-level `ansible_<name>` form — the latter is deprecated in ansible-core 2.20 and removed in 2.24 (`INJECT_FACTS_AS_VARS`). Magic vars (`ansible_play_batch`, `inventory_hostname`, `ansible_managed`, connection params like `ansible_user` / `ansible_port`) are not facts and stay as-is.
- **Local facts**: no in-repo scaffold currently. When per-host custom facts are needed, drop `*.fact` files (INI / JSON / executable → stdout JSON) under remote `/etc/ansible/facts.d/` and refresh via `setup: filter=ansible_local`; they surface as `ansible_facts.ansible_local.<name>.<section>.<key>`.
- **Credentials**: All persisted passwords/secrets use Ansible Vault (`!vault |` encrypted strings). Never store plaintext credentials. KVM bootstrap decrypts its `ansible_ssh_pass` with `--vault-id pwd.vault`; protocol secrets (`xray_uuid`, `xray_reality_private_key`, `sing_box_*`, `redis_password`) use `--vault-id <path>` or `--ask-vault-pass`. Provider bootstrap authenticates via `keys/devops_key`.
- **Template marker**: `ansible_managed` is defined as a regular variable in `group_vars/all.yml` (using template magic vars `template_path`/`template_uid`/`template_host`). The deprecated `ansible.cfg` `DEFAULT_MANAGED_STR` setting was removed (slated for removal in ansible-core 2.23).
- **Existing roles**: audit, categraf, docker, hostname, kafka, nginx, ntp, promtail, redis, rocketmq, security, sing_box, sshd, sysctl, user, xray.
- **Salt states** use the `map.jinja` pattern for cross-platform support (Debian/RedHat).
- **Ansible environment**: macOS and Linux controllers use uv with Python 3.13. `pyproject.toml` declares direct Python dependencies, `uv.lock` pins the complete environment, and `uv sync --frozen` reproduces it in the ignored `.venv/`. Use `uv run` for stateless command execution; activating `.venv/bin/activate` is an interactive convenience only. Galaxy collections are separate from Python packages: `requirements.yml` declares them and the default install root is `~/.ansible/collections`.
- **Ansible config** (`ansible.cfg`): paths are relative (resolved against the cfg file's directory, so both the repo layout and a standalone `~/ansible/` deploy work). 50 forks, SSH pipelining, smart gathering (re-uses JSON fact cache when fresh), `result_format = yaml` for readable per-task output, `ansible.posix.profile_tasks` + `timer` callbacks for per-task / total-play timing, `force_handlers = True` so handlers still fire on partial failure, `host_key_checking = False` for bootstrap. User-shared state (log + fact cache) lives under `~/.ansible/`.
- **Gitignore strategy**: Per-directory `.gitignore` files (in `ansible/` and `saltproject/`) instead of root-level, ensuring rules work when directories are deployed standalone. `ansible/keys/` uses `keys/*` + `!keys/README.md` so private key material never gets committed but the README stays tracked.
