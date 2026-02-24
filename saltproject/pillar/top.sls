base:
  '*':
    - default
    - apache
    - mysql
    - ignore_missing: True

dev:
  '*':
    - default

prod:
  '*':
    - default
