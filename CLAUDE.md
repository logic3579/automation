# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Infrastructure automation repository containing **Ansible** roles/playbooks and **Salt Project** states for server provisioning and configuration management. Two independent toolsets targeting Linux server fleets across self-hosted KVM/bare-metal, cloud (AWS/GCP), and third-party VPS infrastructure.

## Repository Structure

- `ansible/` — Ansible automation (primary tool), deployed standalone to `~/ansible/` on management machines
  - `inventories/` — Two inventory files, used at different lifecycle stages.
    - **`init.ini`** (bootstrap) targets broad IP ranges by infra type: `kvm` self-hosted, `cloud_aws` / `cloud_gcp` / `cloud_vps` cloud, all rolled up under `cloud:children`. Used by `kvm-init.yml` / `cloud-init.yml` / `vps-init.yml`.
    - **`hosts.ini`** (service deploy, default in `ansible.cfg`) lists only the specific hosts each service runs on. Each leaf group is named `<service>_<topology>_<infra>` (e.g. `kafka_cluster_kvm`, `rocketmq_2m2s_kvm`, `rocketmq_failover_kvm`); roll-ups `kvm:children` and `cloud:children` (currently containing `cloud_vps` for xray / sing-box hosts) let you target an entire infra type. Service playbooks default to this inventory — no `-i` flag needed.
    - `group_vars/` holds per-group variables shared by both inventories: `all`, `kvm`, `cloud`, `cloud_aws`, `cloud_gcp`, `cloud_vps`.
  - `playbooks/` — Bootstrap (`kvm-init.yml`, `cloud-init.yml`, `vps-init.yml`) and service (`kafka.yml`, `nginx.yml`, `redis.yml`, `rocketmq.yml`, `docker.yml`, `xray.yml`, `sing-box.yml`) entry points.
  - `roles/` — Standard Ansible role layout (`tasks/`, `handlers/`, `defaults/`, `vars/`, `templates/`, `files/`)
  - `keys/` — Single `devops.key/devops.pub` key pair authorized for the `devops` user on all managed hosts
  - `ansible.cfg` — Config using `~/ansible/` as deployment root, `~/.ansible/tmp` for runtime temp
  - `.gitignore` — Per-directory gitignore (vault files, retry files, runtime dirs, logs, all of `keys/` except `keys/README.md`)
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

# Service deployment uses the default hosts.ini (no -i needed)
ansible-playbook playbooks/kafka.yml --limit kafka_standalone_kvm
ansible-playbook playbooks/kafka.yml --limit kafka_cluster_kvm -e "kafka_cluster_enabled=yes"
ansible-playbook playbooks/redis.yml --limit redis_cluster_kvm -e "redis_cluster_enabled=yes"
ansible-playbook playbooks/rocketmq.yml --limit rocketmq_failover_kvm -e "rocketmq_mode=failover"
ansible-playbook playbooks/docker.yml --limit kvm

# Reverse-proxy / VPS-app deployment (after vps-init.yml) — target hosts.ini's cloud_vps
ansible-playbook playbooks/xray.yml --limit cloud_vps --vault-id pwd.vault
ansible-playbook playbooks/sing-box.yml --limit cloud_vps --vault-id pwd.vault -e "sing_box_protocol=vless-reality"

# Bootstrap (uses init.ini's broad IP ranges; vault password file holds the shared root password)
ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml --limit kvm --vault-id pwd.vault
ansible-playbook -i inventories/init.ini playbooks/cloud-init.yml --limit cloud_aws
ansible-playbook -i inventories/init.ini playbooks/vps-init.yml --limit cloud_vps --vault-id pwd.vault

# Dry run (check mode)
ansible-playbook playbooks/nginx.yml -C

# Vault operations
ansible-vault encrypt_string 'secret' --name 'var_name' --vault-id pwd.vault

# Lint (must run from the ansible/ directory so the relative paths in ansible.cfg resolve)
cd ansible/ && ansible-lint --offline playbooks/ roles/

# One-time bootstrap on a new machine: install required collections to the user-standard
# location so ansible-lint's own venv (and any other tool) can find them automatically
ansible-galaxy collection install -r requirements.yml
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
      mode: '0644'
      backup: true
    notify: restart ntp
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

- **Inventory model**: Two files for two lifecycle stages.
  - `inventories/init.ini` (bootstrap) groups hosts by infrastructure type — `kvm` self-hosted, `cloud_aws`/`cloud_gcp`/`cloud_vps` cloud, all aggregated under `cloud:children`. Only the three `*-init.yml` playbooks reference it (`-i inventories/init.ini`).
  - `inventories/hosts.ini` (service deploy, default in `ansible.cfg`) lists specific hosts per service. Leaf groups follow `<service>_<topology>_<infra>` (`kafka_cluster_kvm`, `rocketmq_2m2s_kvm`, `rocketmq_failover_kvm`, etc.). Roll-up parent groups via `:children` — `[kvm:children]` covers every KVM service host, `[cloud:children]` currently includes `cloud_vps` (xray / sing-box deployment targets). Service playbooks omit `-i` entirely.
- **Connection model**: Two-tier — `group_vars/all.yml` defines the steady-state default (`devops@2233` + `keys/devops.key`); per-group overrides set the right port (`kvm.yml`: 2233; `cloud.yml`/`cloud_vps.yml`: 22) and provider-specific NTP servers. Init playbooks override connection params in their own `vars:` block to bootstrap from the pre-init account.
- **KVM bootstrap** (`playbooks/kvm-init.yml`): Bootstrap as `root@22` with vault-encrypted password. Runs roles in order: hostname → audit → ntp → security → sysctl → user → sshd. Sets `sshd_port: 2233` and `security_allowed_tcp_ports: [2233]` at playbook level to keep firewall and SSH port in sync. The `sshd` role runs last as the point of no return (changes port, disables password auth). After init, the host is reachable as `devops@2233` via key.
- **Cloud bootstrap** (`playbooks/cloud-init.yml`): Bootstrap as the cloud image default user (`ubuntu`) authenticated via `keys/devops.key` — requires `devops.pub` pre-injected at VM creation time. Runs hostname (in `fqdn_short` mode, preserves cloud-assigned FQDN) → audit → ntp → security (firewall disabled, cloud security groups handle it) → sysctl → user. No `sshd` role: SSH stays on 22. After init, the host is reachable as `devops@22` via key.
- **VPS bootstrap** (`playbooks/vps-init.yml`): Third-party VPS path. Bootstrap as `root@22` with a vault-encrypted **shared** password (set the same root password at provisioning time on every VPS). Same role order as `kvm-init.yml` but with VPS-tuned defaults: `sshd_port: 22` (no port shift), `security_allowed_tcp_ports: [22, 443]` (443 pre-opened for xray/sing-box), `hostname_mode: fqdn_short` to preserve provider-assigned names. UTC timezone + public NTP pool come from `group_vars/cloud_vps.yml`.
- **Cluster mode toggles**:
  - **Kafka** — `kafka_cluster_enabled` (`"no"` default → replication=1 for single-broker; `"yes"` → replication=3 for 3-node KRaft). Config path is `config/server.properties` (Kafka 4.x consolidated the legacy `config/kraft/` subdir).
  - **Redis** — `redis_cluster_enabled` (`"no"` default → single port 6379; `"yes"` → 6 instances on ports 7001-7006 across 3 hosts with `--cluster-replicas 1` for 3M3S).
  - **RocketMQ** — `rocketmq_mode` (`standalone` | `2m-2s-sync` | `failover`). 2m-2s-sync cross-pairs slaves: slave on host_i protects master on host_(i+1)%N. Failover uses DLedger with `dLegerPeers` derived from `ansible_play_batch`.
- **Multi-distro role pattern** (used by `docker` and `sing-box`): tasks/main.yml first runs `include_vars: "{{ ansible_os_family }}.yml"` to load `vars/Debian.yml` or `vars/RedHat.yml` (package repo URL, GPG key path, etc.); then `install.yml` includes `install-debian.yml` or `install-redhat.yml` via `when: ansible_os_family == "<family>"`. Shared package list lives in `vars/main.yml`. `xray` bypasses this — its upstream `install-release.sh` script handles distro detection itself.
- **Credentials**: All passwords/secrets use Ansible Vault (`!vault |` encrypted strings). Never store plaintext credentials. Bootstrap (`kvm-init`, `vps-init`) and protocol secrets (`xray_uuid`, `xray_reality_private_key`, `sing_box_*`, `redis_password`) all reference vault-encrypted defaults that must be populated before use. Decrypt with `--vault-id <path>` at runtime — note `--ask-pass` is for SSH connection password, **not** vault.
- **Template marker**: `ansible_managed` is defined as a regular variable in `group_vars/all.yml` (using template magic vars `template_path`/`template_uid`/`template_host`). The deprecated `ansible.cfg` `DEFAULT_MANAGED_STR` setting was removed (slated for removal in ansible-core 2.23).
- **Existing roles**: audit, categraf, docker, fact, hostname, kafka, nginx, ntp, promtail, redis, rocketmq, security, sing-box, sshd, sysctl, user, xray.
- **Salt states** use the `map.jinja` pattern for cross-platform support (Debian/RedHat).
- **Ansible config** (`ansible.cfg`): 50 forks, SSH pipelining enabled, fact caching to JSON files, `interpreter_python = auto`, paths relative to `~/ansible/`.
- **Gitignore strategy**: Per-directory `.gitignore` files (in `ansible/` and `saltproject/`) instead of root-level, ensuring rules work when directories are deployed standalone. `ansible/keys/` uses `keys/*` + `!keys/README.md` so private key material never gets committed but the README stays tracked.
