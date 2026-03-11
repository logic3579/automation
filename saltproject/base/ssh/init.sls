install_openssh:
  pkg.installed:
    - name: openssh

push_ssh_conf:
  file.managed:
    - name: /etc/ssh/ssh_config
    - source: salt://ssh/files/ssh_config
    - user: root
    - group: root
    - mode: '0644'

push_sshd_conf:
  file.managed:
    - name: /etc/ssh/sshd_config
    - source: salt://ssh/files/sshd_config
    - user: root
    - group: root
    - mode: '0600'

start_sshd:
  service.running:
    - name: sshd
    - enable: True
    - watch:
      - file: push_sshd_conf
