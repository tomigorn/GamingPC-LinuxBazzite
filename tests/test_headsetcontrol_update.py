import os
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "config/home/bazzite/.local/bin/headsetcontrol-update")
loader = SourceFileLoader("hu", SCRIPT)
hu = module_from_spec(spec_from_loader("hu", loader))
loader.exec_module(hu)


class ParseVersion(unittest.TestCase):
    def test_release(self):
        self.assertEqual(hu.parse_version("HeadsetControl 4.2.0\n"), ("4.2.0", None))

    def test_commit_build(self):
        self.assertEqual(hu.parse_version("HeadsetControl 0.0.0-e529bc1\n"), (None, "e529bc1"))

    def test_release_with_commit_suffix_is_the_release(self):
        self.assertEqual(hu.parse_version("HeadsetControl 4.1.0-abcdef0"), ("4.1.0", None))

    def test_garbage(self):
        self.assertIsNone(hu.parse_version("command not found"))
        self.assertIsNone(hu.parse_version(""))
        self.assertIsNone(hu.parse_version(None))

    def test_two_part_version(self):
        self.assertEqual(hu.parse_version("HeadsetControl 3.1"), ("3.1", None))


class Compare(unittest.TestCase):
    def test_numeric_not_lexical(self):
        self.assertTrue(hu.is_newer("4.10.0", "4.9.0"))
        self.assertFalse(hu.is_newer("4.9.0", "4.10.0"))

    def test_equal_is_not_newer(self):
        self.assertFalse(hu.is_newer("4.2.0", "4.2.0"))

    def test_release_update(self):
        self.assertTrue(hu.needs_update(("4.1.0", None), "4.2.0"))

    def test_up_to_date(self):
        self.assertFalse(hu.needs_update(("4.2.0", None), "4.2.0"))

    def test_never_downgrade(self):
        self.assertFalse(hu.needs_update(("4.3.0", None), "4.2.0"))

    def test_commit_before_release_updates(self):
        self.assertTrue(hu.needs_update((None, "e529bc1"), "4.2.0", "ahead"))

    def test_commit_at_release_is_current(self):
        self.assertFalse(hu.needs_update((None, "91ee690"), "4.2.0", "identical"))

    def test_commit_after_release_never_downgrades(self):
        self.assertFalse(hu.needs_update((None, "d4fb352"), "4.2.0", "behind"))

    def test_unknown_commit_counts_as_old(self):
        self.assertTrue(hu.needs_update((None, "deadbee"), "4.2.0", None))
        self.assertTrue(hu.needs_update((None, "deadbee"), "4.2.0", "diverged"))


class Output(unittest.TestCase):
    def test_update_line(self):
        self.assertEqual(hu.update_line("0.0.0-e529bc1", "4.2.0"), "headsetcontrol 0.0.0-e529bc1 → 4.2.0")

    def test_version_text(self):
        self.assertEqual(hu.version_text(("4.2.0", None)), "4.2.0")
        self.assertEqual(hu.version_text((None, "e529bc1")), "0.0.0-e529bc1")

    def test_dir_name(self):
        self.assertEqual(hu.dir_name("4.2.0"), "headsetcontrol-4.2.0")
        self.assertEqual(hu.dir_name((None, "e529bc1")), "headsetcontrol-0.0.0-e529bc1")


class Layout(unittest.TestCase):
    def test_tarball_url(self):
        self.assertEqual(hu.tarball_url("4.2.0"), "https://github.com/Sapd/HeadsetControl/releases/download/4.2.0/headsetcontrol-4.2.0.tar.gz")

    def test_stale_dirs_keep_current_and_previous(self):
        names = ["headsetcontrol-4.0.0", "headsetcontrol-4.1.0", "headsetcontrol-4.2.0", "headsetcontrol",
                 "headsetcontrol-4.3.0.partial", "pdfsam-basic-5.3.1-linux-x64"]
        self.assertEqual(hu.stale_dirs(names, ("headsetcontrol-4.2.0", "headsetcontrol-4.1.0")), ["headsetcontrol-4.0.0"])

    def test_build_cmd_wraps_on_host(self):
        self.assertEqual(hu.build_cmd(["cmake", "--build", "b"], in_container=False), ["distrobox", "enter", "vscode", "--", "cmake", "--build", "b"])

    def test_build_cmd_direct_in_container(self):
        self.assertEqual(hu.build_cmd(["cmake", "--build", "b"], in_container=True), ["cmake", "--build", "b"])


if __name__ == "__main__":
    unittest.main()
