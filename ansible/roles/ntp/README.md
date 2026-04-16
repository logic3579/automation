# ntp

Configure NTP time synchronization using either **chrony** (default) or **ntpd**.

## Role Variables

### Defaults (`defaults/main.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `ntp_service` | `chrony` | NTP implementation: `chrony` or `ntp` |
| `ntp_servers` | Aliyun/Tencent/pool.ntp.org | List of NTP server addresses |
| `ntp_timezone` | `Asia/Shanghai` | System timezone |
| `ntp_enabled` | `true` | Enable NTP service on boot |
| `chrony_makestep_threshold` | `1` | Chrony step threshold (seconds) |
| `chrony_makestep_limit` | `3` | Chrony step limit (corrections) |
| `ntp_allow_networks` | `[]` | Networks allowed to query as NTP clients |

### Internal variables (`vars/main.yml`)

OS-family specific package names, service names, and config file paths are computed automatically based on `ntp_service` and `ansible_os_family`.

## Supported Platforms

- Debian / Ubuntu
- RHEL / CentOS / Rocky Linux

## Example Playbook

```yaml
- hosts: all
  roles:
    - role: ntp
      ntp_service: chrony
      ntp_timezone: Asia/Shanghai
```

## Handlers

- `restart ntp` — Restarts the NTP service after configuration changes.
