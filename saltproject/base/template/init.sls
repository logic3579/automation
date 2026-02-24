{% from "template/map.jinja" import apache with context %}

template print:
  pkg.installed:
    - name: {{ apache }}
    - name: {{ pillar['apache'] }}
    - name: {{ pillar['git'] }}
    - fire_event: True

  file.managed:
    - name: /tmp/{{ grains['os'] }}.conf
    - source: salt://test.conf

# loop
{% set DIRS = ['/dir1','/dir2','/dir3'] %}
{% for DIR in DIRS %}
{{ DIR }}:
  file.directory:
    - user: {{ salt.cmd.run('whoami') }}
    - group: {{ salt.cmd.run('whoami') }}
    - mode: 774
{% endfor %}
