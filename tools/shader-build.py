"""Build the retro-crt pipelines with kitty's own shader compiler, exactly as kitty does
(slangc with -warnings-as-errors all), outside of a running window.

It needs kitty's bundled Python, so run it through kitty:

    KITTY_CONFIG_DIRECTORY=$PWD CRT_MODE=check \
        ~/.local/kitty.app/bin/kitty +runpy "exec(open('tools/shader-build.py').read(), {})"

CRT_MODE=check  build every supported combination in a throwaway cache; exit 1 if any fails (CI).
CRT_MODE=warm   build CRT_SHADERS (default "retro-crt crt-live") into kitty's real shader cache, so
                the first kitty-crt start does not wait ~8 s for a cold build.

KITTY_CONFIG_DIRECTORY must point at the directory that contains shaders/.
"""

import os
import tempfile
import time

from kitty.shaders.slang import SlangFailed, build_custom_shader_pipeline_glsl, merge_pipelines, parse_pipeline

MODE = os.environ.get('CRT_MODE', 'check')
COMBOS = ('retro-crt', 'retro-crt crt-live')


def build(combo: str, cache_dir: str = '') -> str:
    pipeline = merge_pipelines([parse_pipeline(name) for name in combo.split()])
    _vert, frag, _meta = build_custom_shader_pipeline_glsl(pipeline, cache_dir=cache_dir)
    return f'{len(pipeline["groups"])} groups, {len(frag)} bytes of GLSL'


def main() -> int:
    if MODE == 'warm':
        combo = os.environ.get('CRT_SHADERS', 'retro-crt crt-live')
        start = time.time()
        summary = build(combo)
        print(f'warm  {combo!r}: {summary} ({time.time() - start:.1f}s)')
        return 0
    failed = False
    for combo in COMBOS:
        start = time.time()
        try:
            with tempfile.TemporaryDirectory() as cache:
                summary = build(combo, cache)
        except SlangFailed as err:
            failed = True
            print(f'FAIL  {combo!r}\n{err}')
        except Exception as err:  # a missing file or a pipeline syntax error
            failed = True
            print(f'FAIL  {combo!r}: {err!r}')
        else:
            print(f'ok    {combo!r}: {summary} ({time.time() - start:.1f}s)')
    return 1 if failed else 0


code = main()
if code:
    raise SystemExit(code)
