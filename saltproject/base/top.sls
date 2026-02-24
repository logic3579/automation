base:
  '*':
    - core
  '^(app|web).(qa|prod).loc$':
    - match: pcre
    - package.tree
    - nginx
  'os:Ubuntu':
    - match: grain
    - repos.ubuntu
  'os_family:RedHat':
    - match: grain
    - repos.epel
  'frontend'
    - match: nodegroup
    - nginx
  'zabbix* or G@role:monitoring':
    - match: compound
    - nagios.server

dev:
  '*':
    - core
  'webserver*dev*':
    - webserver

prod:
  '*':
    - core
  'webserver*prod*':
    - webserver

