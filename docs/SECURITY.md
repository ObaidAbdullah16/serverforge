# Security notes

## Controls in the code

| Layer | Control | Where |
|---|---|---|
| Network | AWS security group: SSH from admin IPs only (validation rejects 0.0.0.0/0) | `infra/terraform` |
| Network | ufw default-deny, SSH rate-limited from admin CIDRs, unmanaged rules removed | `roles/firewall` |
| Access | Key-only SSH, no root, `AllowGroups sshusers`, `MaxAuthTries 3`, modern algorithms, no forwarding | `roles/baseline` |
| Access | Config validated with `sshd -t` before it replaces the old one; reload keeps sessions | `roles/baseline` |
| Brute force | fail2ban for sshd and nginx rate-limit offenders | `roles/fail2ban` |
| Patching | Pending updates applied during the run; unattended-upgrades nightly | `roles/baseline` |
| Kernel | sysctl hardening, unused modules blocked, no core dumps | `roles/baseline` |
| Web | TLS 1.2/1.3 (also fixed in the stock `nginx.conf`), CSP and other headers, rate limits | `roles/nginx` |
| App | Own user, code read-only, systemd sandbox (no capabilities, `ProtectSystem=strict`, syscall filter) | `roles/app` |
| Supply chain | Reproducible artifact, SHA-256 checked before install; pinned Ansible and Jenkins versions | `scripts/build-app.sh`, `roles/app` |
| Secrets | SSH keys only in `.keys/` (gitignored); Jenkins stores them as credentials and hands them to a step with `withCredentials` | `jenkins/casc.yaml` |
| Cloud | IMDSv2 only, encrypted EBS, standard CPU credits | `infra/terraform` |

## Known trade-offs in the lab (and what I would do for a client)

| Trade-off | Why here | For a client |
|---|---|---|
| Lab containers run privileged | systemd needs it; throwaway, localhost only | Real VMs |
| Jenkins lab keys are 0644 copies in `lab/.secrets/` | The Jenkins container user must read them | A secrets manager or Jenkins credentials entered once |
| Jenkins plugins resolved at build time | Simple to keep current | Pin versions after a known-good build |
| Self-signed TLS without a domain | Encrypted, but browsers warn | Let's Encrypt (`SF_DOMAIN`) |
| Public IPs, no bastion | No NAT/bastion cost for a demo | Private subnets + SSM Session Manager or a bastion |
| Local backups by default | A copy on the same server | `backup_s3_uri` with versioning + a restore drill (see restore-drill-kit) |
| No log shipping, no file integrity monitoring | Out of scope for the demo | CloudWatch agent or Loki; AIDE |
| Checkov skips | Each one is listed with a reason in `.checkov.yaml` | Revisit per client |
