# Server hardening report

Generated 2026-10-25 21:07 UTC - environment: **lab** - Ubuntu 24.04.5 LTS - Lynis 3.0.9

**Average hardening index: 60.0 -> 80.0** (16 findings resolved).

| Server | Before | After | Change | Warnings | Suggestions |
|---|---:|---:|---:|---|---|
| web-prod-1 | 60 | 80 | +20 | 2 -> 0 | 40 -> 28 |
| web-prod-2 | 60 | 80 | +20 | 2 -> 0 | 40 -> 28 |
| web-stg-1 | 60 | 80 | +20 | 2 -> 0 | 40 -> 28 |

## What was changed

- **SSH:** Key-only logins, no root login, only the sshusers group, 3 tries, modern ciphers, idle sessions closed
- **Firewall:** ufw default-deny; SSH only from admin networks and rate-limited; only 80/443 public
- **Brute force:** fail2ban bans repeated SSH failures and clients that keep hitting the rate limit
- **Patching:** Pending updates applied now; security updates installed automatically every night
- **Kernel:** Network hardening (no redirects, source routing, spoofed packets), restricted kernel info, unused modules blocked
- **Accounts:** Named admin accounts with keys, sudo through a validated sudoers file, umask 027, idle shells closed
- **Web:** nginx with TLS 1.2/1.3 only, security headers, rate limits, internal endpoints hidden
- **App:** Runs as its own user inside a systemd sandbox (read-only system, no privileges, limited syscalls)
- **Logs and data:** Persistent, size-limited journal; nightly verified backups with a tested restore script
- **Monitoring:** node_exporter on localhost (opened only to an allowed Prometheus server)

## Findings resolved

- `ACCT-9626` Enable sysstat to collect accounting (no results)
- `AUTH-9328` Default umask in /etc/login.defs could be more strict like 027
- `BANN-7126` Add a legal banner to /etc/issue, to warn unauthorized users
- `BANN-7130` Add legal banner to /etc/issue.net, to warn unauthorized users
- `DEB-0280` Install libpam-tmpdir to set $TMP and $TMPDIR for PAM sessions
- `DEB-0811` Install apt-listchanges to display any significant changes prior to any upgrade via APT.
- `DEB-0831` Install needrestart, alternatively to debian-goodies, so that you can run needrestart after upgrades to determine which daemons are using old versions of libraries and need restarting.
- `DEB-0880` Install fail2ban to automatically ban hosts that commit multiple authentication errors.
- `FIRE-4512` iptables module(s) loaded, but no rules active
- `KRNL-5820` If not required, consider explicit disabling of core dump in /etc/security/limits.conf file
- `PKGS-7370` Install debsums utility for the verification of packages with known good database.
- `PKGS-7392` Found one or more vulnerable packages.
- `PKGS-7392` Update your system with apt-get update, apt-get upgrade, apt-get dist-upgrade and/or unattended-upgrades
- `PKGS-7420` Consider using a tool to automatically apply upgrades
- `TOOL-5002` Determine if automation tools are present for system management
- `USB-1000` Disable drivers like USB storage when not used, to prevent unauthorized storage or data theft

## Still open (and why)

- `ACCT-9622` Enable process accounting
- `ACCT-9628` Enable auditd to collect audit information - _Container lab: auditd needs the host kernel. Enabled on real VMs._
- `AUTH-9230` Configure password hashing rounds in /etc/login.defs - _Not applicable: nobody logs in with a password (key-only SSH)._
- `AUTH-9262` Install a PAM module for password strength testing like pam_cracklib or pam_passwdqc - _Not applicable: nobody logs in with a password (key-only SSH)._
- `AUTH-9284` Look at the locked accounts and consider removing them - _Locked system accounts are normal on Ubuntu; reviewed, nothing to remove._
- `AUTH-9286` Configure maximum password age in /etc/login.defs - _Not applicable: nobody logs in with a password (key-only SSH)._
- `AUTH-9286` Configure minimum password age in /etc/login.defs - _Not applicable: nobody logs in with a password (key-only SSH)._
- `BOOT-5264` Consider hardening system services - _Per-service systemd sandboxing is applied to the app; distro services keep their defaults._
- `DEB-0810` Install apt-listbugs to display a list of critical bugs prior to each APT installation. - _apt-listbugs is a Debian (not Ubuntu) tool; not useful here._
- `FILE-6310` To decrease the impact of a full /home file system, place /home on a separate partition - _Separate partitions are decided when a server is created; out of scope for an existing server._
- `FILE-6310` To decrease the impact of a full /tmp file system, place /tmp on a separate partition - _Separate partitions are decided when a server is created; out of scope for an existing server._
- `FILE-6310` To decrease the impact of a full /var file system, place /var on a separate partition - _Separate partitions are decided when a server is created; out of scope for an existing server._
- `FILE-7524` Consider restricting file permissions
- `FINT-4350` Install a file integrity tool to monitor changes to critical and sensitive files - _Next step: file integrity monitoring (AIDE) for regulated workloads._
- `FIRE-4513` Check iptables rules to see which rules are currently not used - _Informational: unused firewall rules are reviewed by hand._
- `HRDN-7230` Harden the system by installing at least one malware scanner, to perform periodic file system scans - _Optional: a malware scanner (ClamAV/rkhunter) for servers that accept uploads._
- `HTTP-6710` Change the HTTPS and SSL settings for enhanced protection of sensitive data and privacy
- `KRNL-5788` Determine why /vmlinuz or /boot/vmlinuz is missing on this Debian/Ubuntu system. - _Container lab: there is no kernel image inside a container. Not seen on real VMs._
- `KRNL-6000` One or more sysctl values differ from the scan profile and could be tweaked - _Container lab: kernel settings are written but not applied inside a container._
- `LOGG-2154` Enable logging to an external logging host for archiving purposes and additional protection - _Next step: ship logs off the server (CloudWatch agent, Loki or a syslog host)._
- `LYNIS` This release is more than 4 months old. Check the website or GitHub to see if there is an update available. - _The Ubuntu package of Lynis lags behind upstream; findings are still valid._
- `NAME-4028` Check DNS configuration for the dns domain name - _Lab/cloud servers often have no DNS domain set; harmless._
- `NETW-3200` Determine if protocol 'dccp' is really needed on this system
- `NETW-3200` Determine if protocol 'rds' is really needed on this system
- `NETW-3200` Determine if protocol 'sctp' is really needed on this system
- `NETW-3200` Determine if protocol 'tipc' is really needed on this system
- `PKGS-7394` Install package apt-show-versions for patch management purposes - _Optional patch-reporting tool; unattended-upgrades already patches nightly._
- `SSH-7408` Consider hardening SSH configuration

---
The hardening index is Lynis's own 0-100 score: useful to compare before and after on the
same servers, not a certification. In the container lab, kernel, boot and audit checks do
not apply, so real VMs score differently.
