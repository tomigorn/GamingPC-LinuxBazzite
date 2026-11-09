import os
import unittest
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "config/home/bazzite/.local/bin/discord-surround-linker")
loader = SourceFileLoader("dsl", SCRIPT)
dsl = module_from_spec(spec_from_loader("dsl", loader))
loader.exec_module(dsl)


def node(i, name):
    return {"id": i, "type": "PipeWire:Interface:Node", "info": {"props": {"node.name": name}}}


def port(i, node_id, direction, ch):
    return {"id": i, "type": "PipeWire:Interface:Port",
            "info": {"props": {"node.id": node_id, "port.direction": direction, "audio.channel": ch, "port.name": ch}}}


def link(i, out_port, in_port):
    return {"id": i, "type": "PipeWire:Interface:Link", "info": {"output-port-id": out_port, "input-port-id": in_port}}


def base():
    objs = [node(10, "vencord-screen-share"), port(11, 10, "in", "FL"), port(12, 10, "in", "FR"),
            node(20, "discord_surround_downmix"), node(30, "discord_surround_downmix_out"),
            port(31, 30, "out", "FL"), port(32, 30, "out", "FR"),
            node(40, "game")]
    for n, ch in enumerate(["FC", "SL", "SR", "RL", "RR"]):
        objs.append(port(21 + n, 20, "in", ch))
    for n, ch in enumerate(["FL", "FR", "FC", "SL", "SR", "RL", "RR"]):
        objs.append(port(41 + n, 40, "out", ch))
    return objs


class Plan(unittest.TestCase):
    def state(self, objs):
        st = {}
        dsl.apply_batch(st, objs)
        return st

    def test_captured_surround_app_is_linked(self):
        st = self.state(base() + [link(90, 41, 11), link(91, 42, 12)])
        add, drop = dsl.plan(st)
        self.assertEqual(add, {(43, 21), (44, 22), (45, 23), (46, 24), (47, 25), (31, 11), (32, 12)})
        self.assertEqual(drop, set())

    def test_nothing_captured_nothing_to_do(self):
        add, drop = dsl.plan(self.state(base()))
        self.assertEqual((add, drop), (set(), set()))

    def test_existing_links_not_relinked(self):
        st = self.state(base() + [link(90, 41, 11), link(91, 42, 12), link(92, 43, 21), link(93, 31, 11)])
        add, _ = dsl.plan(st)
        self.assertNotIn((43, 21), add)
        self.assertNotIn((31, 11), add)

    def test_uncaptured_app_feed_is_dropped(self):
        st = self.state(base() + [link(92, 43, 21)])
        _, drop = dsl.plan(st)
        self.assertEqual(drop, {(43, 21)})

    def test_downmix_missing_does_nothing(self):
        objs = [o for o in base() if o["id"] != 20] + [link(90, 41, 11)]
        self.assertEqual(dsl.plan(self.state(objs)), (set(), set()))


class ApplyBatch(unittest.TestCase):
    def test_removal_deletes_object(self):
        st = {}
        dsl.apply_batch(st, [node(1, "a")])
        dsl.apply_batch(st, [{"id": 1, "info": None}])
        self.assertEqual(st, {})

    def test_update_replaces_object(self):
        st = {}
        dsl.apply_batch(st, [node(1, "a")])
        dsl.apply_batch(st, [node(1, "b")])
        self.assertEqual(st[1]["info"]["props"]["node.name"], "b")


class Stream(unittest.TestCase):
    def test_batches_split_across_reads(self):
        dec = dsl.BatchDecoder()
        self.assertEqual(dec.feed('[{"id": 1}]\n[{"id"'), [[{"id": 1}]])
        self.assertEqual(dec.feed(': 2}]\n'), [[{"id": 2}]])


if __name__ == "__main__":
    unittest.main()
