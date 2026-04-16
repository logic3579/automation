# categraf

Install and configure [Categraf](https://github.com/flashcatcloud/categraf) monitoring agent.

## Role Variables

### Defaults (`defaults/main.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `categraf_version` | `0.4.5` | Categraf version to install |
| `categraf_root_path` | `/opt/categraf` | Installation directory |
| `categraf_user` | `categraf` | System user |
| `categraf_group` | `categraf` | System group |
| `categraf_hostname` | `""` | Override hostname (empty = auto-detect) |
| `categraf_global_labels` | `{}` | Global metric labels |
| `categraf_interval` | `15` | Collection interval (seconds) |
| `categraf_providers` | `["local"]` | Config providers |
| `categraf_writers` | (see defaults) | Remote write endpoints |

## Example Playbook

```yaml
- hosts: all
  roles:
    - role: categraf
      categraf_version: "0.4.5"
      categraf_writers:
        - url: "http://n9e:17000/prometheus/v1/write"
```

## Handlers

- `restart categraf` — Restarts the categraf service after configuration changes.
