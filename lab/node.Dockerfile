# A throwaway "server" for the local lab: Ubuntu 24.04 with systemd and SSH, so
# Ansible sees what it would see on a real VM (services, users, sudo, a firewall).
# Built by scripts/lab-up.sh. Not for production use: it runs privileged.
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive \
    container=docker

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server sudo python3 python3-apt \
      iproute2 iptables kmod ca-certificates curl gnupg less procps \
 && rm -rf /var/lib/apt/lists/* \
 # an empty package cache must also look OLD, or Ansible's apt "cache_valid_time"
 # would trust it and skip `apt-get update` on the first run
 && touch -d @0 /var/lib/apt/lists \
 # units that make no sense inside a container
 && rm -f /etc/systemd/system/*.wants/*getty* /lib/systemd/system/*.wants/*getty* \
          /lib/systemd/system/sysinit.target.wants/systemd-udev* \
          /lib/systemd/system/sysinit.target.wants/systemd-firstboot.service \
 # every node must get its own SSH host keys (generated at start, see CMD)
 && rm -f /etc/ssh/ssh_host_*

# The automation user, like "ubuntu" on an EC2 instance: key-only login + passwordless sudo.
ARG LAB_PUBKEY
RUN test -n "$LAB_PUBKEY" || { echo "LAB_PUBKEY build arg is required (scripts/lab-up.sh sets it)"; exit 1; } \
 && useradd --create-home --shell /bin/bash ansible \
 && echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ansible \
 && chmod 0440 /etc/sudoers.d/90-ansible \
 && install -d -m 0700 -o ansible -g ansible /home/ansible/.ssh \
 && echo "$LAB_PUBKEY" > /home/ansible/.ssh/authorized_keys \
 && chown ansible:ansible /home/ansible/.ssh/authorized_keys \
 && chmod 0600 /home/ansible/.ssh/authorized_keys

RUN systemctl enable ssh.socket

STOPSIGNAL SIGRTMIN+3
# Create this node's host keys (first start only), then hand over to systemd.
CMD ["/bin/sh", "-c", "ssh-keygen -A && exec /sbin/init"]
