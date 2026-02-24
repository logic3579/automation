{% if grains['os_family'] == 'RedHat' %}
git: git
{% elif grains['os_family'] == 'Debian' %}
git: git-core
{% endif %}

