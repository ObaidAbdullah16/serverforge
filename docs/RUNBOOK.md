# Runbook

All commands run from the repository root. Add `INV=aws` in front to target the AWS lab.

## A release failed

The play stopped with *"Release X failed its health check on HOST. Rolled back to Y."*

1. Nothing to do for users: HOST is back on Y, and the other servers were never touched.
2. Find out why: `ssh` to the server (lab: `ssh -i .keys/lab_ed25519 -p 2222 ansible@127.0.0.1`),
   then `journalctl -u serverforge -n 50` and `cat /var/lib/serverforge/deployments.log`.
3. Fix, build a new version, deploy to staging first.

## Roll back on purpose

```bash
bash scripts/rollback.sh production      # one release back, one server at a time, health checked
```

## Drift found (nightly job is unstable, or `drift.sh` exited 2)

1. Read `reports/drift-*.txt`: every `changed` task shows the diff between the server and the code.
2. Ask who changed it and why. A real fix belongs in the code (pull request), not on the server.
3. Put the server back: `bash scripts/site.sh --limit <host>`. Then run `drift.sh` again: exit 0.

## Locked out of SSH

The roles validate `sshd` config before using it and keep the automation user in
`sshusers`, so this should not happen. If it does:

- Lab: `docker exec -it serverforge-lab-web-prod-1-1 bash`
- AWS: EC2 Serial Console or Session Manager. Then check `/etc/ssh/sshd_config.d/10-serverforge.conf`,
  `sshd -t`, `ufw status`, `fail2ban-client status sshd` (unban: `fail2ban-client set sshd unbanip <ip>`).

## Restore data

```bash
# on the server
sudo /usr/local/sbin/serverforge-restore                     # newest backup
sudo /usr/local/sbin/serverforge-restore /var/backups/serverforge/serverforge-<time>.tar.gz
# from your laptop: prove backup + restore work end to end
bash -c 'source scripts/lib.sh; play backup-test.yml'
```

## Certificate problems (real domain)

`sudo certbot certificates`, `sudo certbot renew --dry-run`. Renewal reloads nginx via
`/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh`.
