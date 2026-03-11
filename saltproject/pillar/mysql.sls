# vim: ft=yaml
# WARNING: Replace plaintext credentials with vault-encrypted pillar or external secret management
---
mysql:
  lookup:
    name: myname
    password: REPLACE_WITH_VAULT_ENCRYPTED_VALUE
    user: myuser
    host: localhost
