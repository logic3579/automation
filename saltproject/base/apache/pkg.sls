{% from "apache/map.jinja" import apache with context %}

include:
  - apache

apache:
  pkg.installed:
    - name: {{ apache.server }}
  service.running:
    - name: {{ apache.service }}
    - enable: True

