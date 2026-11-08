import json
import math
import os
import struct
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "config/home/bazzite/.local/bin/speaker-keepalive")
loader = SourceFileLoader("sk", SCRIPT)
sk = module_from_spec(spec_from_loader("sk", loader))
loader.exec_module(sk)


def report(status):
    buf = bytearray(63)
    buf[0], buf[1], buf[15] = 0x06, 0xB0, status
    return bytes(buf)


class ShouldPlay(unittest.TestCase):
    def test_headset_offline_plays(self):
        self.assertTrue(sk.should_play(report(0x01)))

    def test_headset_online_silent(self):
        self.assertFalse(sk.should_play(report(0x08)))

    def test_headset_cable_charging_silent(self):
        self.assertFalse(sk.should_play(report(0x02)))

    def test_unknown_status_silent(self):
        self.assertFalse(sk.should_play(report(0x05)))

    def test_unreadable_silent(self):
        self.assertFalse(sk.should_play(None))

    def test_short_report_silent(self):
        self.assertFalse(sk.should_play(bytes([0x06, 0xB0, 0x00])))


class Sine(unittest.TestCase):
    def samples(self, chunk):
        return struct.unpack("<%dh" % (len(chunk) // 2), chunk)

    def test_chunk_is_stereo_s16(self):
        gen = sk.SineGenerator(freq=20, amplitude=0.02, rate=48000)
        chunk = gen.chunk(480)
        self.assertEqual(len(chunk), 480 * 2 * 2)
        s = self.samples(chunk)
        self.assertEqual(s[0::2], s[1::2])

    def test_peak_matches_amplitude(self):
        gen = sk.SineGenerator(freq=20, amplitude=0.02, rate=48000)
        s = self.samples(gen.chunk(48000))
        self.assertAlmostEqual(max(s), round(0.02 * 32767), delta=1)

    def test_phase_continues_across_chunks(self):
        whole = sk.SineGenerator(freq=20, amplitude=0.5, rate=48000).chunk(1000)
        gen = sk.SineGenerator(freq=20, amplitude=0.5, rate=48000)
        self.assertEqual(gen.chunk(333) + gen.chunk(667), whole)


class FindSink(unittest.TestCase):
    def node(self, name, cls):
        return {"type": "PipeWire:Interface:Node", "info": {"props": {"node.name": name, "media.class": cls}}}

    def test_picks_arctis_sink(self):
        dump = [
            self.node("alsa_input.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.mono-fallback", "Audio/Source"),
            self.node("music_eq", "Audio/Sink"),
            self.node("alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo", "Audio/Sink"),
        ]
        self.assertEqual(sk.find_sink(json.dumps(dump)), "alsa_output.usb-SteelSeries_Arctis_Nova_Pro_Wireless-00.analog-stereo")

    def test_no_arctis_sink(self):
        self.assertIsNone(sk.find_sink(json.dumps([self.node("music_eq", "Audio/Sink")])))

    def test_garbage_dump(self):
        self.assertIsNone(sk.find_sink("not json"))


if __name__ == "__main__":
    unittest.main()
