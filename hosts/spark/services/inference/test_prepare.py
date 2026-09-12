import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

import prepare

spec = importlib.util.spec_from_file_location('guard', pathlib.Path(__file__).with_name('memory-guard.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class PreparationTests(unittest.TestCase):
    def test_incomplete_download_is_not_ready(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            (directory / 'config.json').write_text('{}')
            (directory / 'weights').write_bytes(b'ab')
            self.assertEqual(prepare.missing_files(directory, {
                'config.json': 2, 'weights': 4, 'tokenizer.json': 8,
            }), {'weights': 4, 'tokenizer.json': 8})

    def test_packed_table_needs_metadata_and_complete_length(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            table = directory / 'embedding.packed_u8'
            table.write_bytes(b'ab')
            self.assertFalse(prepare.packed_complete(directory))
            table.with_suffix('.packed_u8.json').write_text(json.dumps({
                'total_rows': 2, 'row_width': 2,
            }))
            self.assertFalse(prepare.packed_complete(directory))
            table.write_bytes(b'abcd')
            self.assertTrue(prepare.packed_complete(directory))

    def test_disk_floor_is_kept_even_when_already_prepared(self):
        self.assertEqual(prepare.required_space({}, True, True), 20 * prepare.GIB)
        self.assertEqual(prepare.required_space({'weights': 10}, False, False),
                         83 * prepare.GIB + 10)

    def test_disk_failure_precedes_build_and_download(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            manifest = directory / 'manifest.json'
            manifest.write_text('{"weights": 100}')
            config = directory / 'config.json'
            config.write_text(json.dumps({
                'stateDir': str(directory), 'modelRevision': 'test',
                'manifest': str(manifest), 'image': 'test-image',
            }))
            with patch.object(prepare.subprocess, 'run') as run, patch.object(
                prepare.shutil, 'disk_usage'
            ) as usage:
                run.return_value.returncode = 1
                usage.return_value.free = 10
                with self.assertRaisesRegex(SystemExit, 'Insufficient disk'):
                    prepare.main(config)
                run.assert_called_once_with(['podman', 'image', 'exists', 'test-image'], check=False)


class MemoryTests(unittest.TestCase):
    def mem(self, available, free):
        return {'MemAvailable': available * guard.GIB_KB, 'MemFree': free * guard.GIB_KB}

    def test_reclaimable_cache_is_not_itself_pressure(self):
        self.assertFalse(guard.pressured(self.mem(30, 1)))
        self.assertTrue(guard.pressured(self.mem(13, 2)))
        self.assertTrue(guard.pressured(self.mem(9, 4)))

    def test_low_startup_memory_refuses(self):
        with patch.object(guard, 'memory', return_value=self.mem(90, 10)):
            with self.assertRaisesRegex(SystemExit, '98 GiB'):
                guard.main('preflight')

    def test_watch_debounces_and_stops_service_not_container(self):
        samples = [self.mem(9, 4)] * 4 + [self.mem(30, 4)] + [self.mem(9, 4)] * 5
        with patch.object(guard, 'memory', side_effect=samples) as memory, patch.object(
            guard.time, 'sleep'
        ), patch.object(guard.subprocess, 'run') as run:
            guard.main('watch')
            self.assertEqual(memory.call_count, 10)
            run.assert_called_once_with([
                'systemctl', '--no-block', 'stop', 'podman-vllm.service',
            ], check=True)


if __name__ == '__main__':
    unittest.main()
