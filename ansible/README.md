---
description: Ansible
---

# Ansible

## Introduction

...

## Install

### Before install

```bash
# denpend
ssh protocal
python2(scp)
python3(sftp)

# network
firewalld

```

### Install on linux

```bash
# root dir
ANSIBLE_ROOT=/opt/ansible
mkdir $ANSIBLE_ROOT && cd $ANSIBLE_ROOT


# option1: install on source
git clone https://github.com/ansible/ansible.git
cd ansible
python setup.py build
python setup.py install
cp -aR examples/* $ANSIBLE_ROOT
# option2: install on pip
pip install ansible==x.x.x
cp -aR examples/* $ANSIBLE_ROOT


# verify
ansible --version


# set ansible.cfg environment
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

## [How To Use](../../../../DevOps/CommandManual/Automation.md#ansible)

### inventory

```bash
# initial: for initalize the system
inventories/initial.host

# test hosts
inventories/test.host

# production hosts
inventories/prod.host
```

### ad-hoc modules

### vars fact template

### ansible-console

### ansible-doc

### ansible-galaxy

### ansible-lint

### ansible-playbook

### ansible-vault

### plugins && api


> Reference:
>
> 1. [Official Website](https://docs.ansible.com/ansible)
> 2. [Repository](https://github.com/ansible/ansible)
> 3. [Ansible Chinese Documentation](https://ansible-tran.readthedocs.io/en/latest/docs/intro.html)
> 4. [Ansible Galaxy](https://galaxy.ansible.com/)
> 5. [Ansible CN Wiki](https://ansible.leops.cn/basic/Introduction/)
> 6. [Ansible Conditional Judgment Grammar](https://www.ityoudao.cn/posts/ansible-conditionals/)
