"""The monitor choice is a contract between three files that cannot import each other:

  shaders/retro-crt.slang   decodes kitty's `background` colour and holds the monitor table
  bin/crt                   encodes it (CLI, picker, `crt code`)
  config/crt.conf.in        encodes it in the ctrl+alt+N key bindings

If they drift apart a key selects the wrong monitor or the shader silently falls back to amber,
and nothing crashes. These tests pin the contract. Run: python3 -m unittest discover -s tests
"""

import importlib.machinery
import importlib.util
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True  # importing bin/crt must not leave a __pycache__ in the installable bin/ dir


def load_crt():
    loader = importlib.machinery.SourceFileLoader('crt_cli', str(ROOT / 'bin' / 'crt'))
    spec = importlib.util.spec_from_loader('crt_cli', loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


crt = load_crt()
SLANG = (ROOT / 'shaders' / 'retro-crt.slang').read_text()
CONF = (ROOT / 'config' / 'crt.conf.in').read_text()


class CodeRoundTrip(unittest.TestCase):
    def test_every_monitor_and_flat_survives_encode_decode(self):
        for monitor in range(len(crt.MONITORS)):
            for flat in (False, True):
                with self.subTest(monitor=monitor, flat=flat):
                    self.assertEqual(crt.decode(crt.code(monitor, flat)), (monitor, flat))

    def test_code_is_an_invisible_offset_from_black(self):
        for monitor in range(len(crt.MONITORS)):
            for flat in (False, True):
                r, g, b = (int(crt.code(monitor, flat)[i : i + 2], 16) for i in (1, 3, 5))
                self.assertLessEqual(max(r, g, b), 15)
                self.assertEqual(g, 0)

    def test_a_real_background_colour_is_refused_not_misread(self):
        for value in ('#1e1e2e', '#101010', '#000010', '#ffffff'):
            with self.subTest(value=value), self.assertRaises(crt.CrtError):
                crt.decode(value)

    def test_a_monitor_number_past_the_table_is_refused(self):
        with self.assertRaises(crt.CrtError):
            crt.decode('#0000%02x' % len(crt.MONITORS))

    def test_default_black_is_amber_curved(self):
        self.assertEqual(crt.decode('#000000'), (0, False))
        self.assertEqual(crt.MONITORS[0], 'amber')


class ShaderAgrees(unittest.TestCase):
    def test_monitor_count(self):
        count = int(re.search(r'static const int NUM_MONITORS = (\d+);', SLANG).group(1))
        self.assertEqual(count, len(crt.MONITORS))

    def test_every_monitor_after_the_first_has_a_case(self):
        table = re.search(r'monitor_look\(int monitor, bool flat\) \{(.*?)\n\}', SLANG, re.S).group(1)
        cases = sorted(int(n) for n in re.findall(r'case (\d+):', table))
        self.assertEqual(cases, list(range(1, len(crt.MONITORS))))

    def test_monitor_names_match_the_shader_comment(self):
        comment = re.search(r'NUM_MONITORS = \d+;\s*// (.+)', SLANG).group(1).split()
        self.assertEqual(tuple(comment), crt.MONITORS)

    def test_validity_threshold_matches(self):
        self.assertIn('all(c <= int3(15))', SLANG)

    def test_flat_is_red_bit_zero_and_monitor_is_blue(self):
        self.assertIn('ctl.flat = valid && ((c.x & 1) != 0);', SLANG)
        self.assertIn('(valid && c.z < NUM_MONITORS) ? c.z : 0', SLANG)

    def test_picker_and_docs_describe_every_monitor(self):
        self.assertEqual(set(crt.DESCRIPTIONS), set(crt.MONITORS))


class KeyBindingsAgree(unittest.TestCase):
    def test_ctrl_alt_digits_select_monitors_in_order(self):
        bindings = re.findall(r'^map ctrl\+alt\+(\d) set_colors --all --configured background=(#[0-9a-f]{6})$', CONF, re.M)
        self.assertEqual(len(bindings), len(crt.MONITORS))
        for position, (digit, colour) in enumerate(bindings):
            self.assertEqual(int(digit), position + 1)
            self.assertEqual(colour, crt.code(position, False))

    def test_default_monitor_file_is_amber(self):
        text = (ROOT / 'config' / 'crt-monitor.conf').read_text()
        self.assertIn(f'background {crt.code(0, False)}', text)

    def test_colour_only_remote_control_allowlist(self):
        self.assertIn('allow_remote_control password', CONF)
        self.assertIn('remote_control_password "" get-colors set-colors', CONF)


if __name__ == '__main__':
    unittest.main()
