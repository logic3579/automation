# Ansible

## Introduction

Infrastructure automation using Ansible for server provisioning and configuration management. Hosts are organized by geographic region (east/west) with roles for common services (kafka, nginx, redis, rocketmq, etc.).

## Install

### Prerequisites

```bash
# Dependencies
# - SSH protocol
# - Python 2 (scp) or Python 3 (sftp)

# Network
# - Ensure firewall allows SSH traffic
```

### Install on Linux

```bash
# Root directory
ANSIBLE_ROOT=/opt/ansible
mkdir $ANSIBLE_ROOT && cd $ANSIBLE_ROOT

# Option 1: install from source
git clone https://github.com/ansible/ansible.git
cd ansible
python setup.py build
python setup.py install
cp -aR examples/* $ANSIBLE_ROOT

# Option 2: install via pip
pip install ansible==x.x.x
cp -aR examples/* $ANSIBLE_ROOT

# Verify
ansible --version

# Set ansible.cfg environment
export ANSIBLE_CONFIG=/opt/ansible
```

### Credentials

```bash
# Generate private and public key
ssh-keygen -t rsa -b 1024 -C 'for ansible key' -f /opt/ansible/keys/ansible -q -N ""
mv /opt/ansible/keys/ansible /opt/ansible/keys/ansible.key

# Option: if private key has password
ssh-agent bash
ssh-add ~/.ssh/id_rsa

# Add public keys to all hosts
ssh-copy-id -i /opt/ansible/keys/ansible.key root@192.168.1.1
ssh-copy-id -i /opt/ansible/keys/ansible.key root@192.168.1.2
ssh-copy-id -i /opt/ansible/keys/ansible.key root@192.168.1.3
```

## Usage

### Inventory

```bash
# Inventories
inventories/init.ini      # For initializing new servers
inventories/hosts.ini     # Production hosts (default in ansible.cfg)
```

### Ad-Hoc Commands

```bash
# Ping using default inventory
ansible all -m ping

# Ping specific hosts with a special inventory
ansible -i inventories/init.ini 10.0.10.12,10.0.10.13 -m ping
```

### Playbook Execution

```bash
# Run a playbook with default inventory
ansible-playbook playbooks/nginx.yml

# Run with specific inventory and host override
ansible-playbook -i inventories/init.ini playbooks/kvm-init.yml -e "hosts_var=10.0.10.12,10.0.10.13"

# Override remote user and become method
ansible-playbook playbooks/redis.yml -u root --become --become-method su

# List tasks and tags without executing
ansible-playbook playbooks/nginx.yml --list-tasks --list-tags

# Dry run (check mode)
ansible-playbook playbooks/nginx.yml -C

# Step through tasks interactively
ansible-playbook playbooks/nginx.yml --step

# Start at a specific task
ansible-playbook playbooks/nginx.yml --start-at-task "your task name"
```

### Playbook Examples

#### Basic Structure

```yaml
- name: Example Playbook
  hosts: "{{ hosts_var }}"
  # remote_user: root
  # become: true
  # become_method: su
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
ansible-vault encrypt_string 'secret' --name 'var_name' --vault-id pwd.vault

# Run playbook with vault password prompt
ansible-playbook playbooks/kvm-init.yml --ask-vault-pass
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
ansible-lint playbooks/nginx.yml
```

## Reference

1. [Ansible Documentation](https://docs.ansible.com/ansible)
2. [Ansible Repository](https://github.com/ansible/ansible)
3. [Ansible Galaxy](https://galaxy.ansible.com/)
