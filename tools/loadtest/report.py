#!/usr/bin/env python3
"""Builds one HTML page with charts from the JSON results of the load test.

    python3 report.py results/*.json > results/report.html
    python3 report.py --notes notes.html results/*.json > report.html   # + a section with your own conclusions
    python3 report.py --before old/*.json -- results/*.json > report.html  # + "before / after" charts
"""
import json
import pathlib
import sys

args = sys.argv[1:]
notes = ""
if args[:1] == ["--notes"]:
    notes = pathlib.Path(args[1]).read_text(encoding="utf-8")
    args = args[2:]

before = []
if args[:1] == ["--before"]:
    split = args.index("--")
    before = [json.loads(pathlib.Path(p).read_text(encoding="utf-8")) for p in args[1:split]]
    args = args[split + 1:]

runs = [json.loads(pathlib.Path(p).read_text(encoding="utf-8")) for p in args]
template = (pathlib.Path(__file__).parent / "report-template.html").read_text(encoding="utf-8")
data = json.dumps(runs, ensure_ascii=False).replace("</", "<\\/")
before_data = json.dumps(before, ensure_ascii=False).replace("</", "<\\/")
page = template.replace("/*DATA*/[]/*END*/", data).replace("/*BEFORE*/[]/*END*/", before_data).replace("<!--NOTES-->", notes)
sys.stdout.write(page)
