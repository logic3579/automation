# Ansible

## Introduction

Infrastructure automation using Ansible for server provisioning and configuration management. Hosts are organized by geographic region (east/west) with roles for common services (kafka, nginx, redis, rocketmq, etc.).

## Environment Setup

### Prerequisites

The Ansible control environment is managed by [uv](https://docs.astral.sh/uv/)
on both macOS and Linux. Do not install Ansible globally with `pip`, `pipx`,
Homebrew, or a system package manager.

Managed hosts need SSH access and a supported Python interpreter. Ensure that
network firewalls or cloud security groups allow the connection method used by
the inventory.

### Install uv

```bash
# macOS and Linux
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Restart the shell if `uv` is not immediately available, then verify it:

```bash
uv --version
```

### Initialize the project environment

Run all commands from the `ansible/` directory. `uv sync` installs the Python
version declared in `.python-version`, creates `.venv`, and installs the exact
Python package versions recorded in `uv.lock`.

```bash
cd ansible/
uv sync --frozen
uv run ansible-galaxy collection install \
  -r requirements.yml \
  -p ~/.ansible/collections \
  --force
uv run ansible --version
uv run ansible-lint --version
```

When `-p` is omitted, `ansible-galaxy collection install` installs collections
under the first configured collection path. With this project's default
Ansible configuration, that path is `~/.ansible/collections`, and collection
content is stored under
`~/.ansible/collections/ansible_collections/<namespace>/<name>`.

Use `uv sync` without `--frozen` only after intentionally changing
`pyproject.toml`; commit the resulting `uv.lock` update. An existing checkout
should use `uv sync --frozen` so every macOS and Linux controller gets the same
resolved Python dependencies.

### Run commands

Repository documentation and automation use `uv run` because it selects the
project environment without relying on shell state:

```bash
uv run ansible all -m ping
uv run ansible-playbook playbooks/nginx.yml -C
```

For an interactive shell, activate the environment once and then run the
commands without the `uv run` prefix:

```bash
source .venv/bin/activate
ansible all -m ping
ansible-playbook playbooks/nginx.yml -C
deactivate
```

Run `uv sync --frozen` before activation. Activation only applies to the
current shell, and commands must still run from the `ansible/` directory so
the project `ansible.cfg` and its relative paths are used.

### Update dependencies

Python tools and Ansible collections use separate dependency files:

- Add or remove Python packages with `uv add <package>` and
  `uv remove <package>`. This updates both `pyproject.toml` and `uv.lock`.
- Upgrade locked Python packages with `uv lock --upgrade`, then run
  `uv sync --frozen`.
- Update collection constraints in `requirements.yml`, then rerun the
  `uv run ansible-galaxy collection install ...` command above.

Review and commit `pyproject.toml`, `uv.lock`, and `requirements.yml` changes
together when they belong to the same dependency update.

### Credentials

```bash
# Generate private and public key
ssh-keygen -t ed25519 -C 'devops@ansible' -f keys/devops_key -N ""

# Option: if private key has password
ssh-agent bash
ssh-add keys/devops_key

# Add public keys to all hosts
ssh-copy-id -i keys/devops_key.pub root@192.168.1.1
ssh-copy-id -i keys/devops_key.pub root@192.168.1.2
ssh-copy-id -i keys/devops_key.pub root@192.168.1.3
```

## Usage

### Inventory

Steady-state hosts are split by provider. `ansible.cfg` loads these files by
default, so routine commands do not need `-i`:

```text
inventories/kvm.ini
inventories/aws.ini
inventories/gcp.ini
inventories/aliyun.ini
inventories/tencent.ini
inventories/vultr.ini
```

`inventories/init.ini` is reserved for bootstrap targets and must always be
selected explicitly with `-i inventories/init.ini`. It uses the same provider
group names (`kvm`, `aws`, `gcp`, `aliyun`, `tencent`, and `vultr`) but is never
part of the default inventory.

Connection and privilege-escalation settings belong to matching files under
`inventories/group_vars/`. Service playbooks declare only whether they need
`become`; they do not select the SSH user or become method.

### Ad-Hoc Commands

```bash
# Ping using default inventory
uv run ansible all -m ping

# Test an AWS bootstrap target as the image's initial user
uv run ansible -i inventories/init.ini aws -m ping \
  -e "ansible_user=ubuntu ansible_port=22"
```

### Playbook Execution

```bash
# Run a playbook with default inventory
uv run ansible-playbook playbooks/nginx.yml

# Bootstrap KVM; root@22 and its encrypted password are defined in the playbook
uv run ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml \
  --vault-id pwd.vault

# Bootstrap an AWS Ubuntu image; replace ubuntu for other image families
uv run ansible-playbook -i inventories/init.ini playbooks/cloud-init.yml \
  --limit aws -e "ansible_user=ubuntu ansible_port=22"

# List tasks and tags without executing
uv run ansible-playbook playbooks/nginx.yml --list-tasks --list-tags

# Dry run (check mode)
uv run ansible-playbook playbooks/nginx.yml -C

# Step through tasks interactively
uv run ansible-playbook playbooks/nginx.yml --step

# Start at a specific task
uv run ansible-playbook playbooks/nginx.yml --start-at-task "your task name"
```

### Playbook Examples

#### Basic Structure

```yaml
- name: Example Playbook
  hosts: "{{ hosts_var }}"
  # become: true
  # Connection user and become method come from inventory group_vars.
  # ignore_errors: false
  gather_facts: true
  # tags: ["foo", "bar"]
  vars:
    - k1: v1
    - k2: v2
  tasks:
    - name: Ping
      ansible.builtin.ping:
      tags:
        - debug

    - name: Debug message
      ansible.builtin.debug:
        msg: "debug msg"

  roles:
    - role: redis
      vars:
        config: redis.conf
        port: 6379
    - role: fact
      dir: /opt/ansible/facts.d/
      factfile: forbidden.fact
      one: aaa
      two: bbb

  environment:
    http_proxy: http://example.com:8080
    PATH: /opt/go/bin:{{ ansible_env.PATH }}
```

#### Templates

```yaml
- name: Deploy template
  ansible.builtin.template:
    src: templates/test.j2
    dest: /tmp/hostname
    mode: "0644"
```

#### Facts and Variables

```yaml
# System facts
- name: Get default IP address
  ansible.builtin.debug:
    msg: "{{ ansible_facts['default_ipv4']['address'] }}"

# Play variables: inventory_hostname, ansible_play_batch
- name: Get host index in play batch
  ansible.builtin.debug:
    msg: "{{ ansible_play_batch.index(inventory_hostname) }}"
```

#### Shell and Command

```yaml
# Shell module (supports pipes, redirects, env vars)
- name: Run shell command
  ansible.builtin.shell: echo "I've got '{{ foo }}' and am not afraid to use it!"

# Shell with register and conditional
- name: Read file contents
  ansible.builtin.shell: cat /tmp/test.conf
  register: file_contents
- ansible.builtin.shell: echo "/tmp/test.conf contains 'hi'"
  when: file_contents.stdout.find('hi') != -1

# Command module (safer, no shell interpretation)
- name: Run command with conditional
  ansible.builtin.command: echo "I've got '{{ foo }}' and am not afraid to use it!"
  when: foo is defined

# Fail when variable is undefined
- name: Require variable foo
  ansible.builtin.fail:
    msg: "Bailing out. this play requires variable foo"
  when: foo is undefined
```

#### Import and Include Tasks

```yaml
# import_tasks: pre-processed at parse time (static)
- ansible.builtin.import_tasks: Debian.yml
  when: ansible_os_family == "Debian"

# include_tasks: processed during execution (dynamic)
- ansible.builtin.include_tasks: "{{ item }}.yaml"
  loop:
    - i1
    - i2
```

#### Error Handling (block/rescue/always)

```yaml
- name: Attempt and graceful roll back demo
  hosts: test
  tasks:
    - block:
        - ansible.builtin.debug:
            msg: "I execute normally"
        - name: Force a failure
          ansible.builtin.command: /bin/false
        - ansible.builtin.debug:
            msg: "I never execute, due to the above task failing"
      rescue:
        - ansible.builtin.debug:
            msg: "I caught an error"
        - name: Force a failure in middle of recovery
          ansible.builtin.command: /bin/false
        - ansible.builtin.debug:
            msg: "I also never execute"
      always:
        - ansible.builtin.debug:
            msg: "This always executes"
  handlers:
    - name: run me even after an error
      ansible.builtin.debug:
        msg: "This handler runs even on error"
```

#### Lookup Plugins

```yaml
- name: Test lookup plugin
  hosts: test
  vars:
    contents: "{{ lookup('file', '/tmp/foo.txt') }}"
    local_home: "{{ lookup('env', 'HOME') }}"
  tasks:
    - ansible.builtin.debug:
        msg: "the value of foo.txt is {{ contents }}"
    - ansible.builtin.debug:
        msg: "The TXT record for example.org. is {{ lookup('dig', 'example.org./TXT') }}"
    - ansible.builtin.debug:
        var: "{{ local_home }}"
```

### Ansible Vault

```bash
# Encrypt a string
uv run ansible-vault encrypt_string 'secret' --name 'var_name' --vault-id pwd.vault

# Run the vault debug section with a password prompt
uv run ansible-playbook playbooks/debug.yml --tags vault --ask-vault-pass
```

Using vault-encrypted variables in playbooks:

```yaml
- name: Vault example
  hosts: test
  vars:
    root_password: !vault |
      $ANSIBLE_VAULT;1.1;AES256
      31633966303334346438316331323761...
  tasks:
    - name: Use vault variable
      ansible.builtin.debug:
        msg: "{{ root_password }}"
```

### Ansible Lint

```bash
uv run ansible-lint --offline playbooks/ roles/
```

## Reference

1. [uv Documentation](https://docs.astral.sh/uv/)
2. [Ansible Documentation](https://docs.ansible.com/ansible)
3. [Ansible Repository](https://github.com/ansible/ansible)
4. [Ansible Galaxy](https://galaxy.ansible.com/)
