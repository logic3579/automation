---
description: Salt Project(saltstack)
---

# Salt Project

## Introduction

...

## Install

### Before Install

```bash
# Check your network ports
4505  # Event Publisher/Subscriber port
4506  # Data payloads and minion returns (file services/return data)

# Check system requirements
# already install salt-minion and config

# Check your permissions
```

### Install On Ubuntu

```bash
# install repository key and create the apt sources list file
curl -fsSL -o /etc/apt/keyrings/salt-archive-keyring-2023.gpg https://repo.saltproject.io/salt/py3/ubuntu/22.04/amd64/SALT-PROJECT-GPG-PUBKEY-2023.gpg
echo "deb [signed-by=/etc/apt/keyrings/salt-archive-keyring-2023.gpg arch=amd64] https://repo.saltproject.io/salt/py3/ubuntu/22.04/amd64/latest jammy main" | tee /etc/apt/sources.list.d/salt.list

# install
apt update
apt install salt-master salt-minion [salt-api...]

```

### Config and Boot

#### Config

[Salt Config](/DevOps/ServiceConf/saltstack.md)

#### Boot(systemd)

```bash
# boot
cat > /lib/systemd/system/salt-master.service << "EOF"
[Unit]
Description=The Salt Master Server
Documentation=man:salt-master(1) file:///usr/share/doc/salt/html/contents.html https://docs.saltproject.io/en/latest/contents.html
After=network.target

[Service]
LimitNOFILE=100000
Type=notify
NotifyAccess=all
ExecStart=/usr/bin/salt-master

[Install]
WantedBy=multi-user.target
EOF

cat > /lib/systemd/system/salt-minion.service << "EOF"
[Unit]
Description=The Salt Minion
Documentation=man:salt-minion(1) file:///usr/share/doc/salt/html/contents.html https://docs.saltproject.io/en/latest/contents.html
After=network.target salt-master.service

[Service]
KillMode=process
Type=notify
NotifyAccess=all
LimitNOFILE=8192
ExecStart=/usr/bin/salt-minion

[Install]
WantedBy=multi-user.target
EOF

systemctl enable salt-master && systemctl start salt-master
systemctl enable salt-minion && systemctl start salt-minion


# dependencies packages
# select all packages
salt-call pip.list
salt-pip install <package name>
```

## [How To Use](../../../../DevOps/CommandManual/Automation.md#saltstack)

### minion keys

### match minion and groups

### modules

### state structure

### grains

### pillar

## Salt Rosters

### salt-ssh

```bash
# install
apt install salt-ssh
pip install --upgrade salt-ssh

# config
cat /etc/salt/roster
node1:
  host: 192.168.1.1
  port: 22
  user: root
  passwd: test123
  timeout: 5

node2:
  host: 192.168.1.2
  port: 22
  user: root
  passwd: test123

# use
salt-ssh '*' test.ping
```

> Reference:
>
> 1.  [Official Website](https://docs.saltproject.io/salt/user-guide/en/latest/topics/overview.html)
> 2.  [Repository](https://github.com/saltstack/salt)
> 3.  [SaltStack Chinese Documentation](https://docs.saltstack.cn/topics/tutorials/starting_states.html)
> 4.  [SaltStack Chinese Manual](https://github.com/watermelonbig/SaltStack-Chinese-ManualBook/blob/master/chapter05/05-11.Salt-Best-Practices.md)
> 5.  [saltstack-formulas](https://github.com/saltstack-formulas)
