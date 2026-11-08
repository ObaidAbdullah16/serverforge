"""Turn Lynis reports into a client-ready hardening report (Markdown + HTML + JSON).

    python3 tools/hardening_report.py --before reports/raw/before \
        --after reports/raw/after --out reports/before-after --label lab

Each directory holds one <host>.dat file per server (Lynis --report-file output),
as fetched by playbooks/audit.yml. --before is optional: without it you get a
single snapshot. Standard library only.
"""

from __future__ import annotations

import argparse
import html
import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

# What site.yml changes, in plain words (shown in every report).
CONTROLS = [
    ("SSH", "Key-only logins, no root login, only the sshusers group, 3 tries, modern ciphers, idle sessions closed"),
    ("Firewall", "ufw default-deny; SSH only from admin networks and rate-limited; only 80/443 public"),
    ("Brute force", "fail2ban bans repeated SSH failures and clients that keep hitting the rate limit"),
    ("Patching", "Pending updates applied now; security updates installed automatically every night"),
    ("Kernel", "Network hardening (no redirects, source routing, spoofed packets), restricted kernel info, unused modules blocked"),
    ("Accounts", "Named admin accounts with keys, sudo through a validated sudoers file, umask 027, idle shells closed"),
    ("Web", "nginx with TLS 1.2/1.3 only, security headers, rate limits, internal endpoints hidden"),
    ("App", "Runs as its own user inside a systemd sandbox (read-only system, no privileges, limited syscalls)"),
    ("Logs and data", "Persistent, size-limited journal; nightly verified backups with a tested restore script"),
    ("Monitoring", "node_exporter on localhost (opened only to an allowed Prometheus server)"),
]

# Findings we leave open on purpose, and why (shown next to remaining items).
WHY_OPEN = {
    "FILE-6310": "Separate partitions are decided when a server is created; out of scope for an existing server.",
    "KRNL-5788": "Container lab: there is no kernel image inside a container. Not seen on real VMs.",
    "KRNL-6000": "Container lab: kernel settings are written but not applied inside a container.",
    "ACCT-9628": "Container lab: auditd needs the host kernel. Enabled on real VMs.",
    "BOOT-5264": "Per-service systemd sandboxing is applied to the app; distro services keep their defaults.",
    "AUTH-9230": "Not applicable: nobody logs in with a password (key-only SSH).",
    "AUTH-9262": "Not applicable: nobody logs in with a password (key-only SSH).",
    "AUTH-9286": "Not applicable: nobody logs in with a password (key-only SSH).",
    "AUTH-9284": "Locked system accounts are normal on Ubuntu; reviewed, nothing to remove.",
    "LOGG-2154": "Next step: ship logs off the server (CloudWatch agent, Loki or a syslog host).",
    "FINT-4350": "Next step: file integrity monitoring (AIDE) for regulated workloads.",
    "HRDN-7230": "Optional: a malware scanner (ClamAV/rkhunter) for servers that accept uploads.",
    "LYNIS": "The Ubuntu package of Lynis lags behind upstream; findings are still valid.",
    "DEB-0810": "apt-listbugs is a Debian (not Ubuntu) tool; not useful here.",
    "NAME-4028": "Lab/cloud servers often have no DNS domain set; harmless.",
    "FIRE-4513": "Informational: unused firewall rules are reviewed by hand.",
    "PKGS-7394": "Optional patch-reporting tool; unattended-upgrades already patches nightly.",
}


@dataclass
class Audit:
    host: str
    index: int | None = None
    lynis_version: str = ""
    os: str = ""
    date: str = ""
    warnings: list[tuple[str, str]] = field(default_factory=list)
    suggestions: list[tuple[str, str]] = field(default_factory=list)


def parse(path: Path) -> Audit:
    """Parse one Lynis report.dat (key=value lines, key[]=value for lists)."""
    a = Audit(host=path.stem)
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in raw or raw.startswith("#"):
            continue
        key, _, value = raw.partition("=")
        if key == "hardening_index":
            a.index = int(value) if value.strip().isdigit() else None
        elif key == "lynis_version":
            a.lynis_version = value
        elif key == "os_fullname":
            a.os = value
        elif key == "report_datetime_start":
            a.date = value
        elif key == "hostname" and value:
            a.host = value
        elif key in ("warning[]", "suggestion[]"):
            parts = value.split("|")
            item = (parts[0].strip(), parts[1].strip() if len(parts) > 1 else "")
            target = a.warnings if key == "warning[]" else a.suggestions
            if item not in target:  # Lynis repeats some findings once per setting
                target.append(item)
    return a


def load(directory: Path | None) -> dict[str, Audit]:
    if directory is None:
        return {}
    files = sorted(directory.glob("*.dat"))
    if not files:
        raise SystemExit(f"no .dat files in {directory}")
    return {f.stem: parse(f) for f in files}


def build(before: dict[str, Audit], after: dict[str, Audit], label: str) -> dict:
    hosts = []
    fixed: dict[tuple[str, str], int] = {}
    for name, a in sorted(after.items()):
        b = before.get(name)
        row = {
            "host": a.host,
            "after": a.index,
            "before": b.index if b else None,
            "change": (a.index - b.index) if b and a.index is not None and b.index is not None else None,
            "warnings_before": len(b.warnings) if b else None,
            "warnings_after": len(a.warnings),
            "suggestions_before": len(b.suggestions) if b else None,
            "suggestions_after": len(a.suggestions),
        }
        hosts.append(row)
        if b:
            for item in b.warnings + b.suggestions:
                if item not in a.warnings + a.suggestions:
                    fixed[item] = fixed.get(item, 0) + 1

    remaining: dict[tuple[str, str], int] = {}
    for a in after.values():
        for item in a.warnings + a.suggestions:
            remaining[item] = remaining.get(item, 0) + 1

    def avg(key: str) -> float | None:
        vals = [h[key] for h in hosts if h[key] is not None]
        return round(sum(vals) / len(vals), 1) if vals else None

    first = next(iter(after.values()))
    return {
        "generated": datetime.now(UTC).strftime("%Y-%m-%d %H:%M UTC"),
        "label": label,
        "lynis_version": first.lynis_version,
        "os": first.os,
        "hosts": hosts,
        "average_before": avg("before"),
        "average_after": avg("after"),
        "fixed": [{"id": i, "text": t, "hosts": n} for (i, t), n in sorted(fixed.items())],
        "remaining": [
            {"id": i, "text": t, "hosts": n, "why": WHY_OPEN.get(i, "")}
            for (i, t), n in sorted(remaining.items())
        ],
        "warnings_after": sorted({f"{i}: {t}" for a in after.values() for i, t in a.warnings}),
    }


def to_markdown(r: dict) -> str:
    has_before = r["average_before"] is not None
    out = [
        "# Server hardening report",
        "",
        f"Generated {r['generated']} - environment: **{r['label']}** - {r['os']} - Lynis {r['lynis_version']}",
        "",
    ]
    if has_before:
        out += [
            f"**Average hardening index: {r['average_before']} -> {r['average_after']}** "
            f"({len(r['fixed'])} findings resolved).",
            "",
            "| Server | Before | After | Change | Warnings | Suggestions |",
            "|---|---:|---:|---:|---|---|",
        ]
        for h in r["hosts"]:
            change = f"+{h['change']}" if (h["change"] or 0) > 0 else str(h["change"])
            out.append(
                f"| {h['host']} | {h['before']} | {h['after']} | {change} | "
                f"{h['warnings_before']} -> {h['warnings_after']} | {h['suggestions_before']} -> {h['suggestions_after']} |"
            )
    else:
        out += ["| Server | Hardening index | Warnings | Suggestions |", "|---|---:|---:|---:|"]
        for h in r["hosts"]:
            out.append(f"| {h['host']} | {h['after']} | {h['warnings_after']} | {h['suggestions_after']} |")
    out += ["", "## What was changed", ""]
    out += [f"- **{area}:** {text}" for area, text in CONTROLS]
    if r["fixed"]:
        out += ["", "## Findings resolved", ""]
        out += [f"- `{f['id']}` {f['text']}" for f in r["fixed"]]
    out += ["", "## Still open (and why)", ""]
    for f in r["remaining"]:
        why = f" - _{f['why']}_" if f["why"] else ""
        out.append(f"- `{f['id']}` {f['text']}{why}")
    out += [
        "",
        "---",
        "The hardening index is Lynis's own 0-100 score: useful to compare before and after on the",
        "same servers, not a certification. In the container lab, kernel, boot and audit checks do",
        "not apply, so real VMs score differently.",
        "",
    ]
    return "\n".join(out)


def to_html(r: dict) -> str:
    e = html.escape
    has_before = r["average_before"] is not None
    if has_before:
        head = "<tr><th>Server</th><th class=n>Before</th><th class=n>After</th><th class=n>Change</th><th>Warnings</th><th>Suggestions</th></tr>"
        rows = "".join(
            f"<tr><td>{e(h['host'])}</td><td class=n>{h['before']}</td><td class=n><b>{h['after']}</b></td>"
            f"<td class='n up'>{'+' if (h['change'] or 0) > 0 else ''}{h['change']}</td>"
            f"<td>{h['warnings_before']} &rarr; {h['warnings_after']}</td><td>{h['suggestions_before']} &rarr; {h['suggestions_after']}</td></tr>"
            for h in r["hosts"]
        )
        hero = (
            f"<div class=hero><div><span>Before</span><b>{r['average_before']}</b></div>"
            f"<div class=arrow>&rarr;</div><div><span>After</span><b class=good>{r['average_after']}</b></div>"
            f"<div><span>Findings resolved</span><b>{len(r['fixed'])}</b></div></div>"
        )
    else:
        head = "<tr><th>Server</th><th class=n>Hardening index</th><th>Warnings</th><th>Suggestions</th></tr>"
        rows = "".join(
            f"<tr><td>{e(h['host'])}</td><td class=n><b>{h['after']}</b></td><td>{h['warnings_after']}</td><td>{h['suggestions_after']}</td></tr>"
            for h in r["hosts"]
        )
        hero = f"<div class=hero><div><span>Average hardening index</span><b>{r['average_after']}</b></div></div>"
    controls = "".join(f"<li><b>{e(a)}</b> {e(t)}</li>" for a, t in CONTROLS)
    fixed = "".join(f"<li><code>{e(f['id'])}</code> {e(f['text'])}</li>" for f in r["fixed"]) or "<li>-</li>"
    remaining = "".join(
        f"<li><code>{e(f['id'])}</code> {e(f['text'])}{'<br><i>' + e(f['why']) + '</i>' if f['why'] else ''}</li>"
        for f in r["remaining"]
    )
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Server hardening report - {e(r['label'])}</title>
<style>
:root {{ --ink:#17181c; --muted:#5d606b; --line:#e2e1da; --bg:#f7f7f4; --card:#fff; --accent:#0f6b5c; --good:#1a7f37; }}
@media (prefers-color-scheme: dark) {{ :root {{ --ink:#ececea; --muted:#a3a5ad; --line:#2c2d33; --bg:#111214; --card:#1a1b1f; --accent:#4cc3a6; --good:#57ab5a; }} }}
* {{ box-sizing: border-box; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }}
main {{ max-width:960px; margin:0 auto; padding:32px 16px 48px; }}
h1 {{ margin:0 0 4px; font-size:1.7rem; }} h2 {{ margin:32px 0 10px; font-size:1.15rem; }}
.meta {{ color:var(--muted); margin:0 0 20px; }}
.hero {{ display:flex; flex-wrap:wrap; gap:16px; align-items:center; background:var(--card); border:1px solid var(--line); border-radius:14px; padding:18px 22px; }}
.hero div {{ display:flex; flex-direction:column; }} .hero span {{ color:var(--muted); font-size:.85rem; }}
.hero b {{ font-size:2rem; line-height:1.1; }} .hero .arrow {{ font-size:1.6rem; color:var(--muted); }} .good {{ color:var(--good); }}
.table {{ overflow-x:auto; }} table {{ border-collapse:collapse; width:100%; background:var(--card); border:1px solid var(--line); border-radius:12px; margin-top:16px; }}
th,td {{ text-align:left; padding:8px 12px; border-bottom:1px solid var(--line); white-space:nowrap; }} th {{ font-size:.82rem; color:var(--muted); font-weight:600; }}
th.n, td.n {{ text-align:right; font-variant-numeric:tabular-nums; }} td.up {{ color:var(--good); font-weight:600; }}
ul {{ padding-left:20px; }} li {{ margin:4px 0; }} i {{ color:var(--muted); }}
code {{ font-size:.82rem; border:1px solid var(--line); border-radius:5px; padding:1px 5px; }}
.note {{ color:var(--muted); font-size:.9rem; border-top:1px solid var(--line); margin-top:32px; padding-top:12px; }}
</style></head><body><main>
<h1>Server hardening report</h1>
<p class=meta>{e(r['generated'])} &middot; environment <b>{e(r['label'])}</b> &middot; {e(r['os'])} &middot; Lynis {e(r['lynis_version'])}</p>
{hero}
<div class=table><table>{head}{rows}</table></div>
<h2>What was changed</h2><ul>{controls}</ul>
<h2>Findings resolved</h2><ul>{fixed}</ul>
<h2>Still open (and why)</h2><ul>{remaining}</ul>
<p class=note>The hardening index is Lynis's own 0-100 score: useful to compare the same servers before and after,
not a certification. In the container lab, kernel, boot and audit checks do not apply, so real VMs score differently.</p>
</main></body></html>
"""


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--before", type=Path, help="directory with the 'before' .dat files (optional)")
    p.add_argument("--after", type=Path, required=True, help="directory with the current .dat files")
    p.add_argument("--out", type=Path, required=True, help="output directory")
    p.add_argument("--label", default="lab", help="environment name shown in the report")
    args = p.parse_args(argv)

    report = build(load(args.before), load(args.after), args.label)
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "report.md").write_text(to_markdown(report), encoding="utf-8")
    (args.out / "report.html").write_text(to_html(report), encoding="utf-8")
    (args.out / "summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if report["average_before"] is not None:
        print(f"hardening index {report['average_before']} -> {report['average_after']} ({len(report['fixed'])} findings resolved)")
    else:
        print(f"hardening index {report['average_after']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
