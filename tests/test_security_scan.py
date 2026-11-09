import json
import os
import tempfile
import time
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "config/home/bazzite/.local/bin/security-scan")
loader = SourceFileLoader("ss", SCRIPT)
ss = module_from_spec(spec_from_loader("ss", loader))
loader.exec_module(ss)


def trivy(*sevs):
    return json.dumps({"Results": [{"Vulnerabilities": [{"VulnerabilityID": "CVE-%d" % i, "Severity": s, "PkgName": "p"} for i, s in enumerate(sevs)]},
                                   {"Vulnerabilities": None}]})


class Parse(unittest.TestCase):
    def test_trivy_counts(self):
        self.assertEqual(ss.trivy_counts(trivy("HIGH", "CRITICAL", "HIGH")), {"CRITICAL": 1, "HIGH": 2})

    def test_trivy_counts_clean(self):
        self.assertEqual(ss.trivy_counts(json.dumps({"Results": []})), {"CRITICAL": 0, "HIGH": 0})

    def test_clam_finds(self):
        out = "/x/a.txt: Eicar-Test-Signature FOUND\n/x/b: OK\nLibClamAV Warning: foo\n"
        self.assertEqual(ss.clam_finds(out), ["/x/a.txt: Eicar-Test-Signature FOUND"])

    def test_lynis_summary(self):
        dat = "hardening_index=65\nwarning[]=ACCT-9634|Check auditd|-|-|\nsuggestion[]=X|y|-|-|\n"
        self.assertEqual(ss.lynis_summary(dat), (65, ["ACCT-9634 Check auditd"]))

    def test_quadlet_images(self):
        texts = ["[Container]\nImage=docker.io/a/b:v3\nAutoUpdate=registry\n", "Image=docker.io/c:latest\n", "Image=docker.io/a/b:v3\n"]
        self.assertEqual(ss.quadlet_images(texts), ["docker.io/a/b:v3", "docker.io/c:latest"])


class Rules(unittest.TestCase):
    def test_virus_alerts(self):
        self.assertTrue(ss.should_alert({"clam": ["/x: Sig FOUND"], "images": {}}))

    def test_critical_cve_alerts(self):
        self.assertTrue(ss.should_alert({"clam": [], "images": {"a": {"CRITICAL": 1, "HIGH": 0}}}))

    def test_high_cve_does_not_alert(self):
        self.assertFalse(ss.should_alert({"clam": [], "images": {"a": {"CRITICAL": 0, "HIGH": 41}}, "lynis": (65, ["W"])}))

    def test_due(self):
        now = time.time()
        self.assertTrue(ss.due(None, now, 7))
        self.assertTrue(ss.due(now - 8 * 86400, now, 7))
        self.assertFalse(ss.due(now - 86400, now, 7))


class NewFiles(unittest.TestCase):
    def test_only_files_changed_since(self):
        d = tempfile.mkdtemp()
        old, new = os.path.join(d, "old"), os.path.join(d, "sub", "new")
        os.makedirs(os.path.dirname(new))
        open(old, "w").close()
        since = time.time() + 1
        open(new, "w").close()
        os.utime(new, (since + 5, since + 5))
        self.assertEqual(ss.new_files([d, os.path.join(d, "missing")], since, ctime=False), [new])


class Summary(unittest.TestCase):
    def test_lines(self):
        lines = ss.summary_lines({"clam": [], "clam_count": 12, "images": {"docker.io/qmcgaw/gluetun:v3": {"CRITICAL": 0, "HIGH": 41}},
                                  "lynis": (65, ["ACCT-9634 Check auditd"]), "failures": []})
        self.assertEqual(lines, ["ClamAV     12 files, nothing found",
                                 "Trivy      gluetun:v3: 0 critical, 41 high",
                                 "Lynis      hardening 65, 1 warning"])

    def test_lines_virus_and_skipped_lynis(self):
        lines = ss.summary_lines({"clam": ["/x: Sig FOUND"], "clam_count": 3, "images": {}, "lynis": None, "failures": ["trivy: no db"]})
        self.assertEqual(lines, ["ClamAV     3 files, 1 FOUND: /x: Sig FOUND",
                                 "Lynis      not due (weekly)",
                                 "Failed     trivy: no db"])


if __name__ == "__main__":
    unittest.main()
