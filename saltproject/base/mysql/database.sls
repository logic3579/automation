database:
  mysql_database.present:
    - name: {{ salt['pillar.get']('mysql:lookup:name', 'default_db') }}
