#!/usr/bin/env python3
"""Regression checks for baseline comparison failure paths."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('compare', Path(__file__).with_name('bench-compare.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class CompareTest(unittest.TestCase):
    def test_comparison(self):
        with tempfile.TemporaryDirectory() as directory:
            base, new = Path(directory)/'base', Path(directory)/'new'
            base.mkdir()
            new.mkdir()
            self.assertTrue(module.compare(base, new))
            record = dict(skipped_stages={}, status='complete', target='native', postings=1000, method='FIFO', seed=1,
                          runs=21, warmups=2, min_batch_ms=20, environment={},
                          stages={'query': {'p50': 1}}, peak_rss_bytes=100)
            name = 'native-1000-FIFO.json'
            (base/name).write_text(json.dumps(record))
            self.assertTrue(module.compare(base, new))
            def check(change, expected_failure):
                changed = copy.deepcopy(record)
                change(changed)
                (new/name).write_text(json.dumps(changed))
                self.assertEqual(bool(module.compare(base, new)), expected_failure)
            check(lambda r: None, False)
            check(lambda r: r['stages']['query'].update(p50=1.29), False)
            check(lambda r: r['stages']['query'].update(p50=1.31), True)
            check(lambda r: r['stages']['query'].update(p50=float('nan')), True)
            check(lambda r: r['stages'].clear(), True)
            check(lambda r: r.update(peak_rss_bytes=131), True)
            check(lambda r: r.update(status='incomplete'), True)
            check(lambda r: r['environment'].update(cpu='different'), True)
            record['status'] = 'incomplete'
            (base/name).write_text(json.dumps(record))
            self.assertTrue(module.compare(base, new))


if __name__ == '__main__':
    unittest.main()
