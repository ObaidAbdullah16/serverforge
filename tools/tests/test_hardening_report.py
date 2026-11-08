"""Tests for tools/hardening_report.py, using real Lynis reports from the lab
(fixtures/before = fresh server, fixtures/after = after site.yml)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import hardening_report as hr  # noqa: E402

FIX = HERE / "fixtures"


def test_parse_reads_score_and_findings() -> None:
    a = hr.parse(FIX / "before" / "web-stg-1.dat")
    assert a.host == "web-stg-1"
    assert a.index is not None and 0 < a.index < 100
    assert a.lynis_version
    assert a.suggestions, "a fresh server always has suggestions"
    # findings Lynis repeats once per setting are counted once
    assert len(a.suggestions) == len(set(a.suggestions))


def test_parse_handles_odd_lines(tmp_path: Path) -> None:
    f = tmp_path / "srv.dat"
    f.write_text("# comment\nnot a pair\nhardening_index=abc\nwarning[]=X-1\nsuggestion[]=Y-2|text|-|-|\n")
    a = hr.parse(f)
    assert a.index is None
    assert a.warnings == [("X-1", "")]
    assert a.suggestions == [("Y-2", "text")]


def test_before_after_improves_and_lists_fixes() -> None:
    r = hr.build(hr.load(FIX / "before"), hr.load(FIX / "after"), "lab")
    host = r["hosts"][0]
    assert host["after"] > host["before"]
    assert host["change"] == host["after"] - host["before"]
    fixed_ids = {f["id"] for f in r["fixed"]}
    # the two warnings of a fresh server: pending security updates, firewall without rules
    assert {"PKGS-7392", "FIRE-4512"} <= fixed_ids
    assert r["warnings_after"] == []
    # every remaining item we explain carries its reason
    for item in r["remaining"]:
        if item["id"] in hr.WHY_OPEN:
            assert item["why"]


def test_cli_writes_all_outputs(tmp_path: Path) -> None:
    assert hr.main(["--before", str(FIX / "before"), "--after", str(FIX / "after"), "--out", str(tmp_path), "--label", "test"]) == 0
    md = (tmp_path / "report.md").read_text()
    page = (tmp_path / "report.html").read_text()
    data = json.loads((tmp_path / "summary.json").read_text())
    assert "Average hardening index" in md
    assert "<table>" in page and "&rarr;" in page
    assert data["label"] == "test" and data["average_after"] > data["average_before"]


def test_snapshot_without_before(tmp_path: Path) -> None:
    assert hr.main(["--after", str(FIX / "after"), "--out", str(tmp_path)]) == 0
    assert "Hardening index" in (tmp_path / "report.md").read_text()


def test_html_escapes_findings(tmp_path: Path) -> None:
    d = tmp_path / "after"
    d.mkdir()
    (d / "x.dat").write_text("hardening_index=50\nsuggestion[]=T-1|<script>alert(1)</script>|-|-|\n")
    page = hr.to_html(hr.build({}, hr.load(d), "x"))
    assert "<script>alert" not in page
