# Service S7 - Server Setup & Hardening (Ansible)

**Promise:** "Your Linux server, secured and reproducible: SSH locked down, firewall,
automatic security patches, HTTPS, backups and monitoring. Delivered as Ansible code you
keep, with a before/after security score."
**Founding price:** $99-$249 per server group (India: Rs 6k-15k). Add-ons: app deployment
with rollback, Jenkins/GitHub Actions pipeline, monthly drift check (Care Plan).

## Day 0 - free 15-minute call

Ask: provider (EC2, Lightsail, DigitalOcean, Hetzner, on-prem), OS version, what runs on it,
who logs in today and how, open ports, domain, backups, anything that must not restart.
Explain access: *"Create a user for me with my public key and sudo, or give me a
snapshot/staging copy first. No passwords, ever. You remove my key when we're done."*

## Day 1 - snapshot + audit (no changes yet)

1. Client takes a snapshot (EC2: AMI/EBS snapshot). No snapshot, no changes.
2. Add their server to an inventory, check `ansible all -m ping`.
3. `bash scripts/audit.sh before` -> the "before" score and findings.

## Day 2 - harden staging first

1. Fill in `sf_admin_cidrs`, `baseline_admins`, domain/email for Let's Encrypt.
2. `harden.yml` (or full `site.yml`) on staging/the snapshot copy; run twice (second run = 0 changes).
3. Test their app, SSH from a second terminal **before** closing the first one.

## Day 3 - production + report

1. Same playbook on production, in a window they choose.
2. `bash scripts/audit.sh after`, then `tools/hardening_report.py --before ... --after ...`.
3. Deliver: the report (HTML/PDF), the Ansible code (their Git repo), a 10-minute walkthrough
   video, and the runbook. Remove your key or hand over to their admin.

## Day 30 - follow-up

Run `drift.sh` against their servers (read-only, check mode) and send the result.
Offer the Care Plan: monthly drift check + patch review + one small change.

## What never to do

- Never change production without a snapshot and a tested rollback path.
- Never apply SSH changes without a second open session.
- Never store client keys in this repository; never ask for root passwords.
