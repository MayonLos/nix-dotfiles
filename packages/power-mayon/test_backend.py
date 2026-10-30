"""Safety and telemetry tests using private sysfs/procfs fixtures."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

import backend


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.sys = self.base / 'sys'
        self.proc = self.base / 'proc'
        self.config = self.base / 'config'
        self.state = self.base / 'state'
        self.runtime = self.base / 'runtime'
        for path in (self.sys, self.proc, self.config, self.state, self.runtime):
            path.mkdir()
        backend.SYS = self.sys
        backend.PROC = self.proc
        self.environ = mock.patch.dict(os.environ, {
            'XDG_CONFIG_HOME': str(self.config),
            'XDG_STATE_HOME': str(self.state),
            'XDG_RUNTIME_DIR': str(self.runtime),
        }, clear=False)
        self.environ.start()
        self.addCleanup(self.environ.stop)

    def put(self, root, relative, value):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(value) + '\n', encoding='utf-8')
        return path

    def ppd_profile(self, current='balanced'):
        return {'current': current, 'available': list(backend.PROFILES), 'error': None}

    def test_battery_energy_and_charge_fallback_and_estimated_time(self):
        battery = 'class/power_supply/BAT0'
        self.put(self.sys, battery + '/type', 'Battery')
        self.put(self.sys, battery + '/status', 'Discharging')
        self.put(self.sys, battery + '/capacity', '50')
        self.put(self.sys, battery + '/voltage_now', '12000000')
        self.put(self.sys, battery + '/charge_now', '2000000')
        self.put(self.sys, battery + '/charge_full', '4000000')
        self.put(self.sys, battery + '/charge_full_design', '5000000')
        self.put(self.sys, battery + '/current_now', '-500000')
        self.put(self.sys, battery + '/cycle_count', '120')
        item, = backend.batteries()
        self.assertEqual(item['energy_wh'], 24)
        self.assertEqual(item['full_wh'], 48)
        self.assertEqual(item['design_wh'], 60)
        self.assertEqual(item['health_percent'], 80)
        self.assertEqual(item['power_w'], 6)
        self.assertEqual(item['time_to_empty_s'], 14400)
        self.assertEqual(item['cycles'], 120)

    def test_battery_energy_files_take_precedence_over_charge_fallback(self):
        battery = 'class/power_supply/BAT0'
        for field, value in {
            'type': 'Battery', 'status': 'Charging', 'voltage_now': '12000000',
            'energy_now': '10000000', 'energy_full': '30000000',
            'energy_full_design': '40000000', 'charge_now': '99999999',
            'power_now': '5000000',
        }.items():
            self.put(self.sys, f'{battery}/{field}', value)
        item, = backend.batteries()
        self.assertEqual(item['energy_wh'], 10)
        self.assertEqual(item['full_wh'], 30)
        self.assertEqual(item['design_wh'], 40)
        self.assertEqual(item['power_w'], 5)
        self.assertEqual(item['time_to_full_s'], 14400)

    def test_rapl_ignores_nested_zones_and_handles_counter_wrap(self):
        package = 'class/powercap/intel-rapl:0'
        child = package + ':0'
        self.put(self.sys, package + '/name', 'package-0')
        self.put(self.sys, package + '/energy_uj', '50000000')
        self.put(self.sys, package + '/max_energy_range_uj', '1000000000')
        self.put(self.sys, child + '/name', 'core')
        self.put(self.sys, child + '/energy_uj', '500000000')
        self.put(self.sys, child + '/max_energy_range_uj', '1000000000')
        self.assertEqual(set(backend.rapl()), {'intel-rapl:0'})
        first = {'intel-rapl:0': (950000000, 1000000000)}
        last = {'intel-rapl:0': (50000000, 1000000000)}
        self.assertEqual(backend.delta_power(first, last, 10), 10)

    def test_process_stat_parses_parenthesized_process_name(self):
        process = self.proc / '321'
        process.mkdir()
        fields = ['0'] * 20
        fields[0] = 'R'
        fields[11] = '12'
        fields[12] = '7'
        fields[19] = '987654'
        (process / 'stat').write_text('321 (worker (render) helper) ' + ' '.join(fields))
        snapshot = backend.process_snapshot()
        self.assertEqual(snapshot[(321, 987654)], ('worker (render) helper', 19))

    def test_missing_and_unknown_sysfs_are_reported_without_failing(self):
        self.assertEqual(backend.batteries(), [])
        self.assertIsNone(backend.ac_online())
        self.assertEqual(backend.conservation(), {
            'available': False, 'enabled': None, 'kind': 'firmware-conservation',
            'threshold_percent': None,
        })
        self.assertIsNone(backend.rapl().get('missing'))

        self.put(self.sys, 'class/power_supply/AC/type', 'Mains')
        self.put(self.sys, 'class/power_supply/AC/online', '2')
        self.assertIsNone(backend.ac_online())

    def test_nvidia_smi_is_opt_in_and_skips_suspended_gpu(self):
        device = 'bus/pci/devices/0000:01:00.0'
        self.put(self.sys, device + '/vendor', '0x10de')
        self.put(self.sys, device + '/class', '0x030000')
        self.put(self.sys, device + '/power/runtime_status', 'suspended')
        self.put(self.sys, device + '/power_state', 'D3cold')
        with mock.patch.object(backend, 'run', side_effect=AssertionError('nvidia-smi called')) as run:
            default = backend.gpu_data()
            opted_in = backend.gpu_data(nvidia=True)
        run.assert_not_called()
        self.assertFalse(default['query_enabled'])
        self.assertTrue(opted_in['query_enabled'])
        self.assertEqual(opted_in['devices'][0]['runtime_status'], 'suspended')

    def test_history_is_bounded_rate_limited_and_private(self):
        data = {
            'batteries': [{'power_w': 4.5}],
            'cpu': {'package_power_w': 10.0},
            'ac_online': False,
            'profile': {'current': 'balanced'},
        }
        for index in range(backend.LIMIT + 2):
            data['timestamp'] = 1000 + index * 30
            backend.record(data)
        data['timestamp'] += 29
        backend.record(data)
        history_file = backend.root('STATE') / 'history.json'
        history = json.loads(history_file.read_text())
        self.assertEqual(len(history), 720)
        self.assertEqual(history[0]['timestamp'], 1000 + 2 * 30)
        self.assertEqual(history[-1]['timestamp'], 1000 + (backend.LIMIT + 1) * 30)
        self.assertEqual(history_file.stat().st_mode & 0o777, 0o600)
        self.assertEqual(history_file.parent.stat().st_mode & 0o777, 0o700)

    def test_config_defaults_closed_and_unknown_source_does_not_set_profile(self):
        self.assertEqual(backend.config(), backend.DEFAULTS)
        self.assertIsNone(backend.ac_online())
        backend.save(backend.root('CONFIG') / 'config.json', {
            'enabled': True, 'ac': 'performance', 'battery': 'power-saver',
        })
        with mock.patch.object(backend, 'profile', return_value=self.ppd_profile()), \
             mock.patch.object(backend, 'run') as run:
            self.assertEqual(backend.tick(), '电源状态未知，保持模式')
        run.assert_not_called()

    def test_unknown_config_source_is_rejected_without_rewriting(self):
        path = backend.root('CONFIG') / 'config.json'
        backend.save(path, {'enabled': False, 'ac': 'turbo', 'battery': 'power-saver'})
        before = path.read_bytes()
        with self.assertRaises(ValueError):
            backend.config()
        self.assertEqual(path.read_bytes(), before)

    def test_gamemode_pending_blocks_manual_and_automatic_changes_then_resumes(self):
        marker = self.runtime / 'gaming-mode/state.json'
        marker.parent.mkdir()
        marker.write_text('{"active":false}')
        self.put(self.sys, 'class/power_supply/AC/type', 'Mains')
        self.put(self.sys, 'class/power_supply/AC/online', '1')
        with mock.patch.object(backend, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'GameMode'):
                backend.set_mode('performance')
            run.assert_not_called()

            backend.save(backend.root('CONFIG') / 'config.json', {
                'enabled': True, 'ac': 'performance', 'battery': 'power-saver',
            })
            self.assertEqual(backend.tick(), '让出 GameMode / 等待恢复')
            run.assert_not_called()

            marker.unlink()
            with mock.patch.object(backend, 'profile', return_value=self.ppd_profile()), \
                 mock.patch.object(backend, 'run', side_effect=['', 'performance']) as resumed:
                self.assertEqual(backend.tick(), '自动规则: performance')
            self.assertEqual(resumed.call_args_list, [
                mock.call('powerprofilesctl', 'set', 'performance'),
                mock.call('powerprofilesctl', 'get'),
            ])

    def test_gamemode_inactive_or_malformed_journal_always_yields_without_rewriting(self):
        marker = self.runtime / 'gaming-mode/state.json'
        marker.parent.mkdir()
        self.put(self.sys, 'class/power_supply/AC/type', 'Mains')
        self.put(self.sys, 'class/power_supply/AC/online', '1')
        backend.save(backend.root('CONFIG') / 'config.json', {
            'enabled': True, 'ac': 'balanced', 'battery': 'power-saver',
            'gamemode': 'performance',
        })
        for content in (
            {'active': False, 'profile': 'power-saver'},
            {'profile': 'power-saver'},
            {'active': True, 'profile': 'turbo'},
            ['invalid-shape'],
        ):
            marker.write_text(json.dumps(content), encoding='utf-8')
            before = marker.read_bytes()
            with mock.patch.object(backend, 'run') as run:
                self.assertEqual(backend.tick(), '让出 GameMode / 等待恢复')
            run.assert_not_called()
            self.assertEqual(marker.read_bytes(), before)

        marker.write_text('{ broken json', encoding='utf-8')
        before = marker.read_bytes()
        with mock.patch.object(backend, 'run') as run:
            self.assertEqual(backend.tick(), '让出 GameMode / 等待恢复')
        run.assert_not_called()
        self.assertEqual(marker.read_bytes(), before)

    def test_active_gamemode_override_preserves_journal_and_keep_does_not_restore(self):
        marker = self.runtime / 'gaming-mode/state.json'
        marker.parent.mkdir()
        journal = {'active': True, 'profile': 'power-saver'}
        marker.write_text(json.dumps(journal), encoding='utf-8')
        self.put(self.sys, 'class/power_supply/AC/type', 'Mains')
        self.put(self.sys, 'class/power_supply/AC/online', '1')
        config_path = backend.root('CONFIG') / 'config.json'
        backend.save(config_path, {
            'enabled': True, 'ac': 'balanced', 'battery': 'power-saver',
            'gamemode': 'performance',
        })

        current = ['balanced']

        def run(*args):
            if args == ('powerprofilesctl', 'get'):
                return current[0]
            if args == ('powerprofilesctl', 'list'):
                return 'power-saver:\nbalanced:\nperformance:'
            if args[0:2] == ('powerprofilesctl', 'set'):
                current[0] = args[2]
                return ''
            raise AssertionError(f'unexpected command: {args!r}')

        with mock.patch.object(backend, 'run', side_effect=run):
            self.assertEqual(backend.tick(), 'GameMode 规则: performance')
            self.assertEqual(current[0], 'performance')
            self.assertEqual(json.loads(marker.read_text()), journal)

            # Switching the policy back to keep must leave the active profile
            # alone. The existing GameMode end hook owns restoration.
            backend.save(config_path, {
                'enabled': True, 'ac': 'balanced', 'battery': 'power-saver',
                'gamemode': 'keep',
            })
            before = marker.read_bytes()
            self.assertEqual(backend.tick(), '让出 GameMode / 等待恢复')
            self.assertEqual(current[0], 'performance')
            self.assertEqual(marker.read_bytes(), before)

            # Simulate the existing hook restoring its journaled profile and
            # removing the journal; the ordinary AC rule resumes afterwards.
            current[0] = journal['profile']
            marker.unlink()
            self.assertEqual(backend.tick(), '自动规则: balanced')
            self.assertEqual(current[0], 'balanced')

    def test_auto_configure_accepts_explicit_gamemode_profile(self):
        with mock.patch.object(sys, 'argv', [
            'power-mayon', 'auto', 'configure', '--gamemode', 'performance',
        ]):
            with mock.patch.object(backend, 'run') as run:
                backend.main()
        run.assert_not_called()
        self.assertEqual(backend.config()['gamemode'], 'performance')

    def test_invalid_profile_and_invalid_or_ambiguous_conservation_never_run_controls(self):
        with mock.patch.object(backend, 'run') as run:
            with self.assertRaises(ValueError):
                backend.set_mode('turbo')
            run.assert_not_called()

            node = self.put(self.sys, 'bus/platform/drivers/ideapad_acpi/one/conservation_mode', '2')
            self.assertFalse(backend.conservation()['available'])
            for suffix in ('one', 'two'):
                self.put(self.sys, f'bus/platform/drivers/ideapad_acpi/{suffix}/conservation_mode', '0')
            self.assertFalse(backend.conservation()['available'])

            for value in ('on', 'off'):
                with mock.patch.object(sys, 'argv', ['power-mayon', 'conservation', value]):
                    with self.assertRaisesRegex(ValueError, '唯一有效'):
                        backend.main()
            run.assert_not_called()

    def test_symlink_state_file_is_rejected(self):
        target = self.base / 'target.json'
        target.write_text('{}')
        link = backend.root('CONFIG') / 'config.json'
        link.parent.mkdir()
        link.symlink_to(target)
        with self.assertRaises(ValueError):
            backend.save(link, backend.DEFAULTS)
        with self.assertRaises(OSError):
            backend.load(link, {})

    def test_symlinked_xdg_directory_is_rejected(self):
        external = self.base / 'external'
        external.mkdir()
        link = self.base / 'linked-config'
        link.symlink_to(external, target_is_directory=True)
        with mock.patch.dict(os.environ, {'XDG_CONFIG_HOME': str(link)}):
            with self.assertRaises(ValueError):
                backend.save(backend.root('CONFIG') / 'config.json', backend.DEFAULTS)


if __name__ == '__main__':
    unittest.main()
