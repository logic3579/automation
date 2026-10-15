# Repository Guidelines

## Project Layout

This repository contains two independent infrastructure automation stacks:

- `ansible/` is the primary workspace. `playbooks/` contains bootstrap, service, and debug entry points; `roles/` contains reusable roles; `inventories/` contains static and dynamic sources with matching `group_vars/` and `host_vars/`.
- `saltproject/` contains Salt states under `base/`, pillar data under `pillar/`, and example master/minion configuration. States commonly use `map.jinja` for OS-specific values.

Keep this file as the canonical agent guide. Use the code and configuration as the source of truth when updating documentation.

## Ansible Environment

Run Ansible commands from `ansible/` so the project configuration and relative paths are used. macOS and Linux controllers use uv with Python 3.13; do not install project Ansible tools globally.

```bash
cd ansible/
uv sync --frozen
uv run ansible-galaxy collection install -r requirements.yml -p ~/.ansible/collections
```

`pyproject.toml` declares Python dependencies, including Ansible tooling and the AWS SDK; `uv.lock` pins their versions, and `.python-version` selects Python 3.13. Update the lockfile when intentionally changing dependencies. Galaxy collections are declared separately in `requirements.yml` (`ansible.posix`, `community.general`, and `amazon.aws`).

Use `uv run` in documentation and automation. Interactive shells may activate `.venv/bin/activate` after syncing. `.venv/` is generated and ignored; recreate it if its interpreter link is broken rather than committing or editing generated environment files. Ansible logs and fact caches live under `~/.ansible/` as configured in `ansible.cfg`.

## Inventory and Address Planning

- The only default source is `inventories/kvm.ini`. Select every cloud source explicitly with `-i`; do not load the entire inventory directory or add `init.ini` to the default.
- `inventories/init.ini` is for bootstrap only and shares provider group names with the steady-state sources. Keep bootstrap and steady-state sources separate when invoking commands.
- Static cloud sources are `aliyun.ini`, `aws.ini`, `gcp.ini`, `tencent.ini`, and `vultr.ini`. Service groups follow `<service>_<topology>_<provider>` and roll up through their provider's `[<provider>:children]`. There is no shared `cloud` group.
- Matching provider/account `group_vars/` files own connection and privilege-escalation settings. Provider timezone/NTP overrides also belong there; `group_vars/all.yml` contains only global values, currently the `ansible_managed` template marker.

Each cloud provider reserves an entire `/16` in the address plan:

| Provider | Reserved CIDR |
| --- | --- |
| Aliyun | `10.0.0.0/16` |
| AWS | `10.10.0.0/16` |
| GCP | `10.20.0.0/16` |
| Tencent | `10.30.0.0/16` |
| Vultr | `10.100.0.0/16` |

The first four provider files list three planned `/24` subnets whose third octets are 0, 1, and 2. KVM currently uses addresses in `10.200.0.0/24`, `10.200.1.0/24`, and `10.200.2.0/24`. CIDR comments document planning only; they neither create cloud networks nor expand into inventory hosts. Keep future allocations disjoint, and do not infer actual VPC settings from these comments.

### AWS Dynamic Inventory

`inventories/aws_proj_dev.aws_ec2.yml` explicitly discovers running EC2 instances using profile `proj-dev` in `eu-central-1`. It currently has no tag opt-in filter. Instance IDs are both inventory names and connection targets; AWS host variables use the `aws_` prefix. Matching `group_vars/aws_proj_dev.yml` connects as `ssm-user` using EC2 Instance Connect and SSH over Session Manager with `keys/aws_ssm_key`.

Discovery needs the configured AWS profile and EC2 describe permissions. Connections additionally need the AWS CLI, Session Manager plugin, appropriate Instance Connect/SSM permissions, and a suitably configured target. Inspect discovery before targeting a specific instance.

```bash
uv run ansible-inventory -i inventories/aws_proj_dev.aws_ec2.yml --graph
uv run ansible -i inventories/aws_proj_dev.aws_ec2.yml aws_proj_dev --list-hosts
```

## Bootstrap and Deployment

Service playbooks declare `become: true` when needed, but must not hardcode `remote_user` or `become_method`; inventory variables select the connection and escalation details. Many service playbooks target `all`, so always choose the intended inventory and narrow service group with `--limit`.

- `playbooks/kvm-init.yml` targets `kvm`, fixes bootstrap at `root@22`, and requires `--vault-id pwd.vault` for its encrypted `ansible_ssh_pass`. Replace the Vault placeholder with the actual encrypted password before use. It configures SSH and the firewall for port 2233; `sshd` runs last. Steady-state KVM access is `devops@2233` with `keys/devops_key` and sudo.
- `playbooks/cloud-init.yml` targets `all`; select one provider from `init.ini` with `--limit` and override the image account through extra vars, for example `-e "ansible_user=ubuntu ansible_port=22"`. The image account must already authorize `devops_key.pub`. The host firewall is disabled by this playbook, so ingress rules belong to the provider network configuration. Static provider steady-state access is `devops@22` with sudo; the AWS dynamic account uses its separate SSM connection.

Use check mode before changing remote hosts. These examples are previews; bootstrap still requires valid keys and Vault material:

```bash
uv run ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml --vault-id pwd.vault -C
uv run ansible-playbook -i inventories/init.ini playbooks/cloud-init.yml --limit aws -e "ansible_user=ubuntu ansible_port=22" -C
uv run ansible-playbook playbooks/nginx.yml --limit nginx_standalone_kvm -C
uv run ansible-playbook -i inventories/vultr.ini playbooks/xray.yml --limit vultr --vault-id pwd.vault -C
```

Cluster settings live in each role's `defaults/main.yml`: Kafka uses `kafka_cluster_enabled` (`"no"`/`"yes"`), Redis uses `redis_cluster_enabled` (`"no"`/`"yes"`), and RocketMQ uses `rocketmq_mode` (`standalone`, `2m-2s-sync`, or `failover`). Cluster membership is currently derived from `ansible_play_batch`, while these playbooks set `serial: 1`; review batch sizing and topology calculations before any cluster deployment or changes to `serial`/`--limit`.

## Role Conventions

Use `roles/ntp/` as a compact reference and follow these conventions when modifying roles:

- Role directory names match `^[a-z][a-z0-9_]*$`: use `sing_box`; external product, package, and playbook names may retain hyphens.
- Put user-facing, role-prefixed variables in `defaults/main.yml`; reserve `vars/main.yml` for internal/computed values. Keep version and configuration defaults in role files rather than duplicating them in this guide.
- Keep `tasks/main.yml` readable; split substantial installation and configuration logic into `install.yml` and `configure.yml`. Prefer flat task lists; use blocks when needed for error handling. Docker and sing-box load OS-specific variables from `vars/Debian.yml` or `vars/RedHat.yml`.
- Use fully qualified module names, YAML dictionary arguments, and `loop` instead of `with_items`. Task names are short, verb-first, and unprefixed, such as `Install dependency packages`.
- Quote file modes as strings (`"0644"`) and whole Jinja expressions (`"{{ variable }}"`). Otherwise quote only when necessary.
- Access facts through `ansible_facts.<name>`. Connection variables and magic variables such as `ansible_user`, `inventory_hostname`, and `ansible_play_batch` retain their existing names.
- Configuration templates should start with `# {{ ansible_managed }}` where the target format supports comments. Set explicit owner, group, and mode; back up replaced service configuration and notify the relevant handler when changes require a reload or restart.
- Handler names use capitalized verb-noun wording, such as `Restart nginx`; keep `notify` and `listen` references consistent. Do not manufacture changes with `echo` or debug tasks just to trigger handlers.
- Keep certificate validation enabled. Store secrets with Ansible Vault rather than plaintext variables or templates.

## Validation

There is currently no checked-in role smoke-test suite or CI workflow. For playbook, role, or inventory changes, run the relevant syntax/inventory checks and lint from `ansible/`:

```bash
uv run ansible-inventory -i inventories/kvm.ini --graph
uv run ansible-playbook playbooks/nginx.yml --syntax-check
uv run ansible-lint --offline playbooks/ roles/
```

Choose the playbook and explicit inventory affected by the change; use the appropriate Vault options and local key material when required. For remote previews, use a narrow `--limit` and `-C`. Check mode may need connectivity and cannot validate every installation or handler path. Documentation-only changes require checking referenced paths/commands and `git diff --check`; report any checks blocked by the local environment.

`playbooks/debug.yml` defaults to localhost. Use `--tags facts` for a limited facts check; the Vault section needs Vault material. Avoid the full run or `env`/`facts_full` dumps when their output could expose secrets.

## Salt

Review `base/top.sls`, `pillar/top.sls`, and the master's file/pillar roots before changing states. Some top-file entries refer to states not present in this checkout; verify the selected target resolves. Use `map.jinja` and pillar for platform-specific configuration.

On a configured Salt controller, target the affected minion and preview before applying:

```bash
salt '<minion-id>' test.ping
salt '<minion-id>' state.apply '<state_name>' test=True
```

## Secrets and Change Hygiene

Never commit plaintext credentials, private keys, Vault passwords, or generated runtime files. Pass Vault material at runtime with `--vault-id <path>` or `--ask-vault-pass`. Everything in `ansible/keys/` except its README is ignored; see `ansible/keys/README.md` for key generation and distribution. Preserve per-directory ignore rules so `ansible/` and `saltproject/` can be deployed independently.

Use focused Conventional Commits, such as `fix(inventory): ...`, `refactor(role): ...`, or `docs: ...`. Pull requests should describe the behavior change, affected hosts/groups, validation, and deployment risks; link related issues when available.
