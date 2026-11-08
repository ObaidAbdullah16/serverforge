# Jenkins build agent with Ansible and the test tools. The controller connects to
# it over SSH (the official jenkins/ssh-agent image) and runs pipelines here.
# Build context: the repository root (so the pinned requirements are used).
FROM jenkins/ssh-agent:9.3.3-jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv openssh-client git curl \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-dev.txt /tmp/req/
RUN python3 -m venv /opt/ansible \
 && /opt/ansible/bin/pip install --no-cache-dir -r /tmp/req/requirements-dev.txt \
 # SSH sessions start with a clean PATH, so put the tools where it already looks
 && for t in ansible ansible-community ansible-playbook ansible-lint ansible-inventory yamllint pytest ruff; do \
      ln -s "/opt/ansible/bin/$t" "/usr/local/bin/$t"; \
    done \
 && rm -rf /tmp/req
