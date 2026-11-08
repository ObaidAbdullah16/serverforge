# Architecture

## Two loops

1. **Configuration** (`site.yml`): makes every server match the code. It runs at the
   start of each release and every night in check mode (drift detection).
2. **Release** (`deploy.yml`): installs a new version of the app with a health gate.

```mermaid
sequenceDiagram
  participant J as Jenkins agent / laptop
  participant S as Server (one at a time)
  J->>J: build-app.sh: tarball + SHA-256
  J->>S: copy tarball, check SHA-256 against the .sha256 file
  J->>S: unpack into releases/<UTC time>-<version>/
  J->>S: ln -sfn + mv -T: current -> new release (atomic)
  J->>S: systemctl restart serverforge
  loop up to 15 times, 2 s apart
    J->>S: GET http://127.0.0.1:8000/healthz
  end
  alt healthy and version matches
    J->>S: record "ok" in deployments.log, keep the newest 3 releases
    J->>S: smoke test through nginx (https://127.0.0.1/healthz + security headers)
  else unhealthy
    J->>S: current -> previous release, restart, record "rolled back"
    J-->>J: fail the play: the other servers are never touched
  end
```

## What runs on each server

| Piece | Where | Notes |
|---|---|---|
| nginx | :80 (redirect), :443 | TLS 1.2/1.3, security headers, rate limit on `/api/`, `/metrics` localhost only |
| app (`serverforge.service`) | 127.0.0.1:8000 | Python stdlib, systemd sandbox, user `serverforge` |
| code | `/opt/serverforge/releases/*`, `current` symlink | owned by root, read-only for the app |
| data | `/var/lib/serverforge/data/notes.json` | the only writable path for the app |
| node_exporter | 127.0.0.1:9100 | opened in ufw only for `monitoring_scrape_cidrs` |
| backups | `/var/backups/serverforge/` | systemd timer 02:30 UTC, 7 kept, optional S3 copy |
| fail2ban | - | `sshd` + `nginx-limit-req` jails, bans through ufw |

## Environments

| | Lab (Docker) | AWS |
|---|---|---|
| Servers | `web-stg-1`, `web-prod-1`, `web-prod-2` | `web-stg-1`, `web-prod-1` (t4g.nano) |
| Reached from laptop | 127.0.0.1:2221-2223 (SSH), 8441-8443 (HTTPS) | public IPs, SSH from your IP only |
| Reached from Jenkins | container names on the compose network | not wired (use the Showcase workflow) |
| Login user | `ansible` (image) | `ubuntu` (AMI) |
| Inventory | `inventories/lab/hosts.yml` | `inventories/aws/hosts.yml` (written by `aws-up.sh`) |

## Jenkins

```mermaid
flowchart LR
  casc[jenkins/casc.yaml] --> ctrl[Controller: 0 executors]
  plugins[jenkins/plugins.txt] --> ctrl
  ctrl -->|SSH, credential agent-ssh,<br/>host key trusted on first use| agent[Agent: Ansible, pytest, linters]
  agent -->|credential lab-ssh via withCredentials| servers[(lab servers)]
```

Nothing is clicked by hand. Delete the containers and `lab-up.sh --with-jenkins` builds the
same Jenkins again: users, credentials, the agent and both jobs.
