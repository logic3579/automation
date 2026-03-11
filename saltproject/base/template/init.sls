{% from "apache/map.jinja" import apache with context %}

install_apache_packages:
  pkg.installed:
    - pkgs:
      - {{ apache.server }}
      - {{ salt['pillar.get']('git', 'git') }}
    - fire_event: True

manage_apache_config:
  file.managed:
    - name: /tmp/{{ grains['os'] }}.conf
    - source: salt://test.conf

# loop
{% set DIRS = ['/dir1','/dir2','/dir3'] %}
{% for DIR in DIRS %}
{{ DIR }}:
  file.directory:
    - user: root
    - group: root
    - mode: '0774'
{% endfor %}
