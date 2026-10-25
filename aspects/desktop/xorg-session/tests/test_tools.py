"""Pure fixture checks for shared image discovery and RandR policy."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'resources' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


wallpaper = load('wallpaper')
outputs = load('outputs')


class ToolsTests(unittest.TestCase):
    def test_wallpaper_follows_managed_and_local_symlinks_without_cycles(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'public'
            source.mkdir()
            (source / '005.png').write_bytes(b'fixture')
            collection = root / 'collection'
            collection.mkdir()
            (collection / 'managed').symlink_to(source, target_is_directory=True)
            local = collection / 'local'
            local.mkdir()
            (local / 'personal.jpg').write_bytes(b'fixture')
            (local / 'loop').symlink_to(collection, target_is_directory=True)
            (local / 'duplicate.png').symlink_to(source / '005.png')
            (local / 'not-image.txt').write_text('fixture')
            self.assertEqual(wallpaper.images(collection), sorted([str(source / '005.png'), str(local / 'personal.jpg')]))
            self.assertTrue((local / 'personal.jpg').exists())

    def test_randr_hotplug_uses_actual_connector_names_and_internal_first(self):
        text = 'Screen 0: fixture\nHDMI-0 connected 1920x1080+0+0\nDP-1 disconnected\neDP-1-1 connected primary 2560x1600+0+0\n'
        topology = outputs.topology(text)
        command = outputs.layout_command(topology)
        self.assertEqual(command, ['xrandr', '--output', 'DP-1', '--off', '--output', 'eDP-1-1', '--auto', '--primary', '--pos', '0x0', '--output', 'HDMI-0', '--auto', '--right-of', 'eDP-1-1'])

    def test_randr_does_not_blank_last_display_when_detection_is_empty(self):
        self.assertEqual(outputs.layout_command([('HDMI-0', False)]), [])
        self.assertEqual(outputs.layout_command([]), [])


if __name__ == '__main__':
    unittest.main()
