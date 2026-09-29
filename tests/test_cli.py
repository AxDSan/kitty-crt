"""`crt` as a process: the paths the key bindings and the shell use, against a fake `kitten`.

A fake kitten stands in for kitty so these run anywhere (CI has no display). Linux only (/proc).
Run: python3 -m unittest discover -s tests
"""

import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CRT = ROOT / 'bin' / 'crt'

FAKE_KITTEN = """#!/bin/sh
# argv: @ <command> ...   State is one file: the background colour, as `kitten @ get-colors` prints it.
state="$FAKE_STATE"
if [ -n "$FAKE_REQUIRE_FD" ] && [ ! -e "/proc/$$/fd/$FAKE_REQUIRE_FD" ]; then
    echo "bad file descriptor: fd $FAKE_REQUIRE_FD is closed" >&2
    exit 1
fi
case "$2" in
get-colors) printf 'background              %s\\nforeground              #dddddd\\n' "$(cat "$state")" ;;
set-colors) for a in "$@"; do case "$a" in background=*) printf '%s' "${a#background=}" > "$state" ;; esac; done ;;
*) echo "unexpected command $2" >&2; exit 2 ;;
esac
"""


class CrtProcess(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        tmp = Path(self.tmp.name)
        self.state = tmp / 'background'
        self.state.write_text('#000000')
        self.kitten = tmp / 'kitten'
        self.kitten.write_text(FAKE_KITTEN)
        self.kitten.chmod(self.kitten.stat().st_mode | stat.S_IXUSR)
        self.config = tmp / 'config'
        self.config.mkdir()

    def crt(self, *args, env=None, pass_fds=()):
        environment = {
            'PATH': os.environ['PATH'],
            'KITTY_CRT_KITTEN': str(self.kitten),
            'FAKE_STATE': str(self.state),
            'KITTY_CONFIG_DIRECTORY': str(self.config),
            **(env or {}),
        }
        return subprocess.run([sys.executable, str(CRT), *args], env=environment, capture_output=True, text=True, timeout=20, pass_fds=pass_fds)

    def background(self):
        return self.state.read_text()

    def test_steps_through_the_monitors_and_wraps(self):
        seen = [self.crt('next').stdout.strip() for _ in range(6)]
        self.assertEqual(seen, ['green', 'white', 'ice', 'color', 'amber', 'green'])
        self.assertEqual(self.background(), '#000001')

    def test_prev_wraps_below_the_first_monitor(self):
        self.assertEqual(self.crt('prev').stdout.strip(), 'color')
        self.assertEqual(self.background(), '#000004')

    def test_a_named_monitor_and_flat_combine(self):
        self.assertEqual(self.crt('ice').stdout.strip(), 'ice')
        self.assertEqual(self.crt('flat').stdout.strip(), 'ice (flat)')
        self.assertEqual(self.background(), '#010003')
        self.assertEqual(self.crt('curved').stdout.strip(), 'ice')
        self.assertEqual(self.crt('toggle-flat').stdout.strip(), 'ice (flat)')

    def test_status_reads_what_kitty_reports(self):
        self.state.write_text('#010002')
        self.assertEqual(self.crt('status').stdout.strip(), 'white (flat)')

    def test_refuses_to_switch_when_the_background_is_a_real_colour(self):
        self.state.write_text('#1e1e2e')
        result = self.crt('next')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('#1e1e2e', result.stderr)
        self.assertEqual(self.background(), '#1e1e2e')  # left exactly as it was

    def test_save_writes_the_start_monitor_for_kitty_crt(self):
        self.crt('green')
        self.crt('save')
        saved = (self.config / 'crt-monitor.conf').read_text()
        self.assertIn('background #000001', saved)

    def test_unknown_command_fails_loudly(self):
        result = self.crt('nope')
        self.assertEqual(result.returncode, 1)
        self.assertIn('unknown command', result.stderr)

    @unittest.skipUnless(Path('/proc/self/fd').is_dir(), 'needs /proc')
    def test_uses_the_private_channel_a_key_binding_launch_provides(self):
        # `launch --type=background --allow-remote-control` passes the channel as KITTY_LISTEN_ON=fd:N.
        # subprocess closes fds above 2 in children by default; crt must keep that one open for kitten.
        left, right = os.pipe()
        self.addCleanup(os.close, left)
        try:
            env = {'KITTY_LISTEN_ON': f'fd:{right}', 'FAKE_REQUIRE_FD': str(right)}
            result = self.crt('next', env=env, pass_fds=(right,))
        finally:
            os.close(right)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'green')
        self.assertEqual(self.background(), '#000001')


if __name__ == '__main__':
    unittest.main()
