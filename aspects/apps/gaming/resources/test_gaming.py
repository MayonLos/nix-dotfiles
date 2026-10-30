import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).parent
STUB = '''#!/usr/bin/env python3
import json, os, pathlib, sys
root=pathlib.Path(os.environ['TEST_ROOT'])
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with (root/'calls').open('a') as f: f.write(json.dumps([name,*args])+'\\n')
if name=='powerprofilesctl':
    if args==['get']: print((root/'profile').read_text().strip())
    else:
        if os.environ.get('FAIL_PROFILE')==args[1]: sys.exit(1)
        (root/'profile').write_text(args[1])
elif name=='systemctl':
    if os.environ.get('FAIL_INHIBITOR')=='1' and 'start' in args: sys.exit(1)
    (root/'inhibitor').write_text('1' if 'start' in args else '0')
elif name=='nvidia-smi':
    print('GPU 0: NVIDIA Test' if os.environ.get('GPU_PRESENT')=='1' else 'No devices were found')
    sys.exit(0 if os.environ.get('GPU_PRESENT')=='1' else 1)
elif name=='wlr-randr':
    print(json.dumps([{'name':'eDP-1','enabled':True,'modes':[{'width':2560,'height':1600,'refresh':165.002,'current':True}]}, {'name':'DP-1','enabled':True,'modes':[{'width':3840,'height':2160,'refresh':59.94,'current':True}]}]))
elif name=='mmsg': print(json.dumps({'monitor':'DP-1'}))
elif name=='xrandr': print('eDP-1 connected primary\\n   2560x1600  165.00*+ 60.00')
else:
    (root/'launch').write_text(json.dumps({'argv':args,'env':dict(os.environ)}))
    sys.exit(int(os.environ.get('GAME_EXIT','0')))
'''


class Gaming(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        for name in ['powerprofilesctl', 'systemctl', 'nvidia-smi', 'gamemoderun',
                     'game-run', 'gamescope', 'wlr-randr', 'mmsg', 'xrandr']:
            file = self.bin / name
            file.write_text(STUB.replace('/usr/bin/env python3', sys.executable))
            file.chmod(0o755)
        (self.root / 'profile').write_text('power-saver')
        self.env = dict(os.environ, TEST_ROOT=str(self.root), XDG_RUNTIME_DIR=str(self.root),
                        PATH=str(self.bin), WAYLAND_DISPLAY='test-0')
        for key in ['FAIL_PROFILE', 'FAIL_INHIBITOR', 'GPU_PRESENT', 'GAME_RUN_GPU', 'GAME_EXIT']:
            self.env.pop(key, None)

    def call(self, script, *args, success=True):
        result = subprocess.run([sys.executable, str(HERE / script), *args],
                                env=self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def hook(self, action, **kwargs):
        return self.call('gamemode-hook.py', action, **kwargs)

    def test_hooks_idempotent_and_restore_manual_original(self):
        self.hook('start')
        self.hook('start')
        self.assertEqual((self.root / 'profile').read_text(), 'performance')
        calls = (self.root / 'calls').read_text()
        self.assertEqual(calls.count('"start"'), 1)
        self.hook('end')
        self.hook('end')
        self.assertEqual((self.root / 'profile').read_text(), 'power-saver')
        self.assertEqual((self.root / 'inhibitor').read_text(), '0')
        self.assertFalse((self.root / 'gaming-mode/state.json').exists())

    def test_concurrent_starts_save_original_once(self):
        processes = [subprocess.Popen([sys.executable, str(HERE / 'gamemode-hook.py'), 'start'],
                                     env=self.env) for _ in range(8)]
        self.assertTrue(all(p.wait() == 0 for p in processes))
        self.hook('end')
        self.assertEqual((self.root / 'profile').read_text(), 'power-saver')

    def test_failed_performance_rolls_back_inhibitor(self):
        self.env['FAIL_PROFILE'] = 'performance'
        self.hook('start', success=False)
        self.assertEqual((self.root / 'inhibitor').read_text(), '0')
        self.assertEqual((self.root / 'profile').read_text(), 'power-saver')
        self.assertFalse((self.root / 'gaming-mode/state.json').exists())

    def test_failed_inhibitor_rolls_back(self):
        self.env['FAIL_INHIBITOR'] = '1'
        self.hook('start', success=False)
        self.assertEqual((self.root / 'profile').read_text(), 'power-saver')
        self.assertFalse((self.root / 'gaming-mode/state.json').exists())

    def test_failed_restore_releases_inhibitor_and_can_retry(self):
        self.hook('start')
        self.env['FAIL_PROFILE'] = 'power-saver'
        self.hook('end', success=False)
        self.assertEqual((self.root / 'inhibitor').read_text(), '0')
        self.assertTrue((self.root / 'gaming-mode/state.json').exists())
        del self.env['FAIL_PROFILE']
        # A new start must recover the old failed restore before reacquiring.
        self.hook('start')
        self.assertEqual((self.root / 'inhibitor').read_text(), '1')
        self.hook('end')
        self.assertEqual((self.root / 'profile').read_text(), 'power-saver')

    def test_nvidia_environment_and_argument_boundaries(self):
        self.env['GPU_PRESENT'] = '1'
        self.call('game-run.py', '--', 'game with spaces', '--argument=$HOME')
        launch = json.loads((self.root / 'launch').read_text())
        self.assertEqual(launch['argv'], ['game with spaces', '--argument=$HOME'])
        self.assertEqual(launch['env']['__GLX_VENDOR_LIBRARY_NAME'], 'nvidia')
        self.assertEqual(launch['env']['MESA_SHADER_CACHE_MAX_SIZE'], '10G')

    def test_missing_gpu_removes_inherited_offload(self):
        self.env.update(__GLX_VENDOR_LIBRARY_NAME='nvidia', DRI_PRIME='1',
                        __NV_PRIME_RENDER_OFFLOAD='1', __VK_LAYER_NV_optimus='NVIDIA_only')
        result = self.call('game-run.py', 'game')
        env = json.loads((self.root / 'launch').read_text())['env']
        self.assertNotIn('__GLX_VENDOR_LIBRARY_NAME', env)
        self.assertNotIn('DRI_PRIME', env)
        self.assertIn('NVIDIA', result.stderr)

    def test_integrated_override_skips_probe_and_preserves_exit(self):
        self.env.update(GAME_RUN_GPU='integrated', GAME_EXIT='7')
        result = self.call('game-run.py', 'game', success=False)
        self.assertEqual(result.returncode, 7)
        self.assertNotIn('nvidia-smi', (self.root / 'calls').read_text())

    def test_gamescope_pointer_output_and_fsr(self):
        self.call('gamescope-run.py', '--render-size', '1920x1080', '--fsr', '--fps', '50', '--', 'a b')
        args = json.loads((self.root / 'launch').read_text())['argv']
        self.assertEqual(args, ['--backend', 'wayland', '-f', '-W', '3840', '-H', '2160', '-w', '1920',
                                '-h', '1080', '-r', '50', '--framerate-limit', '50', '-F', 'fsr', '--', 'game-run', 'a b'])

    def test_gamescope_manual_and_hdr(self):
        self.call('gamescope-run.py', '--size', '2560x1600', '--refresh', '165', '--hdr', '--', 'game')
        args = json.loads((self.root / 'launch').read_text())['argv']
        self.assertEqual(args[:2], ['--backend', 'wayland'])
        self.assertIn('--hdr-enabled', args)
        env = json.loads((self.root / 'launch').read_text())['env']
        self.assertEqual(env['ENABLE_GAMESCOPE_WSI'], '1')
        self.assertEqual(env['DXVK_HDR'], '1')
        self.assertEqual(args[args.index('-r')+1], '165')
        self.assertNotIn('wlr-randr', (self.root / 'calls').read_text())

    def test_gamescope_xorg_and_bad_arguments(self):
        self.env.pop('WAYLAND_DISPLAY')
        self.call('gamescope-run.py', '--', 'game')
        args = json.loads((self.root / 'launch').read_text())['argv']
        self.assertEqual(args[args.index('-W')+1], '2560')
        self.assertNotIn('--backend', args)
        self.call('gamescope-run.py', '--fps', '0', '--', 'game', success=False)
        self.call('gamescope-run.py', '--size', '0x800', '--', 'game', success=False)

    def test_gamescope_keeps_game_hooks_inside_compositor(self):
        self.env.update(__NV_PRIME_RENDER_OFFLOAD='1', __GLX_VENDOR_LIBRARY_NAME='nvidia',
                        __VK_LAYER_NV_optimus='NVIDIA_only', DRI_PRIME='1')
        self.call('gamescope-run.py', '--size', '1280x800', '--refresh', '60', '--', 'game with spaces')
        launch = json.loads((self.root / 'launch').read_text())
        self.assertEqual(launch['argv'][-3:], ['--', 'game-run', 'game with spaces'])
        self.assertNotIn('__NV_PRIME_RENDER_OFFLOAD', launch['env'])
        self.assertNotIn('__GLX_VENDOR_LIBRARY_NAME', launch['env'])
        self.assertNotIn('__VK_LAYER_NV_optimus', launch['env'])
        self.assertNotIn('DRI_PRIME', launch['env'])

    def test_gamescope_removes_only_gamemode_preload(self):
        clean = runpy.run_path(str(HERE / 'gamescope-run.py'))['compositor_environment']
        original = {'LD_PRELOAD': 'libMangoHud.so:libgamemodeauto.so.0 /lib/libgamemodeauto.so.0.0.0:/lib/overlay.so',
                    'DRI_PRIME': '1', 'DISPLAY': 'private'}
        result = clean(original)
        self.assertEqual(result['LD_PRELOAD'], 'libMangoHud.so:/lib/overlay.so')
        self.assertEqual(result['DISPLAY'], 'private')
        self.assertEqual(original['DRI_PRIME'], '1')
        self.assertNotIn('LD_PRELOAD', clean({'LD_PRELOAD': 'libgamemodeauto.so.0'}))


if __name__ == '__main__':
    unittest.main()
