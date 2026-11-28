#!/usr/bin/env python3
"""Bundle layout test (docs/engine.md "Bundle layout"; the Administrator, 2026-11-17). Run by scripts/check.local.sh.

Builds the sample app (schemas/examples/sample-manifest.json + tests/fixture-app, in a temporary copy) after adding the
same marked block to two of its scripts, then checks:
  1. the Contents list names every part, file and engine part, and each line number points at that banner line;
  2. the block is kept once ($shared) and each script holds one "# @@SHARED" line in its place;
  3. the engine's own Expand-SharedBlock (engine/ps/03-files.ps1, run in pwsh) gives back each script's text exactly;
  4. a second build of the same app gives the same bytes (an app's lock and its stale check rest on this);
  5. the build stops when an engine part is not in the part lists, and when a step has "urlConfig" and no "url";
  6. the count of `catch { $null = $_ }` with no reason comment on the same line is exactly SILENT_CATCHES (docs/code-standard-rade.md X7).
Output: one PASS or FAIL line per check, then "LAYOUT pass=N fail=M"; exit 1 on a failure. Needs Python 3 and pwsh 7.
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BLOCK = ('# >>> demo-common: generated from scripts/gov/src/demo-common.ps1 by a test (do not edit)\n'
         '# Returns the sum of two numbers.\nfunction Get-DemoSum([int]$A, [int]$B) { return $A + $B }\n'
         '# <<< demo-common\n')
RESULTS = []
DISCARD = 'catch { $null = $_ }'   # the discarded-error form that rule X7 counts
# Engine PowerShell sources that rule X7 covers (the files the bundle is made of).
ENGINE_PS = ('engine/rade_ui.ps1', 'engine/ps/*.ps1', 'engine/ps/window/*.ps1')
# Standards plan Stage 5 (the Administrator approved the plan, 2026-11-17; this count is an agent's work under it).
# Discarded-error catches with no reason on their line (106 of 129 on 2026-11-17).
# This number may only go down: lower it when you add reasons; never raise it.
SILENT_CATCHES = 99


def check(ok, what):
    """Record and print one result line."""
    RESULTS.append(bool(ok))
    print(('PASS ' if ok else 'FAIL ') + what)


def make_app(tmp):
    """Copy the sample app into `tmp`, add BLOCK to two scripts, and return (app folder, {name: expected text})."""
    app = tmp / 'app'
    shutil.copytree(ROOT / 'tests/fixture-app', app)
    (app / 'scripts').mkdir(exist_ok=True)
    shutil.copy(ROOT / 'schemas/examples/sample-manifest.json', app / 'scripts/paste_bundles.json')
    want = {}
    for name in ('SAMPLE-T01-check-r1.ps1', 'SAMPLE-T03-verify-r1.ps1'):
        p = app / 'scripts/gov' / name
        text = p.read_bytes().decode('ascii').replace('\r\n', '\n')
        text = text + ('' if text.endswith('\n') else '\n') + BLOCK + '# end of test file\n'
        p.write_bytes(text.encode('ascii'))
        want[name] = text
    return app, want


def check_contents(text):
    """Check 1: each Contents row points at its banner line."""
    lines = text.split('\n')
    rows = re.findall(r'^#   line +(\d+)  +(.*)$', text, re.M)
    bad = [r for r in rows if not lines[int(r[0]) - 1].strip().endswith(r[1].strip()[:-3] if r[1].endswith('...') else r[1].strip())]
    check(rows and not bad, 'contents: %d rows, each line number points at its banner%s' % (len(rows), '' if not bad else ': ' + str(bad[:2])))
    kinds = [r[1].strip().split(':')[0].split(' ')[0] for r in rows]
    check({'Part', 'File', 'Engine'} <= set(kinds), 'contents: lists parts, files and engine parts')


def check_run_steps(text):
    """Check 1b (90-161.Z R43 E1): the numbered run steps are the first lines after the hash line, ASCII, and never end the header."""
    lines = text.split('\n')
    head = text[:text.index('\n#>\n')]
    check(lines[1] == '<#' and lines[3].strip() == 'HOW TO RUN THIS SCRIPT (on a work computer):' and lines[4].strip().startswith('1. '),
          'run steps: the first lines after the hash line and the GENERATED line')
    # engine-v41 (90-161.Z R43): the kit code standard C6 needs GENERATED and its source in the first 15 lines of a generated file.
    check(any('GENERATED' in line and ' from ' in line for line in lines[:15]), 'run steps: a GENERATED line with its source is in the first 15 lines')
    check(head.isascii() and '#>' not in head[3:], 'run steps: ASCII, and no "#>" inside the header')
    check('\n         . $script:PasteBody\n' in head and lines[-2] == '. $script:PasteBody', 'run steps: step 5 names the real last line of the bundle')


def check_shared(text, want):
    """Checks 2 and 3: one $shared entry, one SHARED line per script, and pwsh puts the block back exactly."""
    check(text.count("$shared['demo-common-") == 1 and text.count('# @@SHARED demo-common-') == 2,
          'shared block: kept once, one SHARED line in each of the 2 scripts')
    part = text[text.index('# ==== Part 1 of'):text.index('# ==== Part 4 of')]   # settings, shared blocks, files: assignments only
    fn = (ROOT / 'engine/ps/03-files.ps1').read_text()
    fn = fn[fn.index('function Expand-SharedBlock'):]
    fn = fn[:fn.index('\n}\n') + 3]
    with tempfile.TemporaryDirectory() as d:
        script = Path(d) / 'expand.ps1'
        script.write_text(part + '\n' + fn + '\n$out = @{}\nforeach ($f in $files) { if ($f.Kind -eq "text") { $out[$f.Name] = Expand-SharedBlock $f.Data } }\n'
                          '$out | ConvertTo-Json -Compress\n')
        run = subprocess.run(['pwsh', '-NoProfile', '-File', str(script)], capture_output=True, text=True)
    got = json.loads(run.stdout or '{}')
    for name, text_want in want.items():
        g = (got.get(name) or '').replace('\r\n', '\n') + '\n'   # Write-BundleFile adds the last line break
        check(g == text_want, 'expand: %s comes back byte for byte' % name)


def build(app, root=ROOT):
    """Build the app in `app` with the engine under `root`; return the finished process."""
    return subprocess.run([sys.executable, '-B', str(root / 'engine/rade_build.py'), '--app-root', str(app)], capture_output=True, text=True)


def check_same_bytes(app, first):
    """Check 4: build again and compare the bundle with the bytes of the first build."""
    bundle = next((app / 'scripts/gov/paste').glob('*.ps1'))
    bundle.unlink()
    again = build(app)
    check(again.returncode == 0 and bundle.read_bytes() == first, 'second build: the same bytes as the first (%d)' % len(first))


def check_build_stops(tmp, app):
    """Check 5: the build fails for an unlisted engine part and for a step with "urlConfig" and no "url".

    Args:
        tmp: a temporary folder; a copy of the engine with one extra part is made in it.
        app: the test app's folder; its manifest is changed (run this check last).
    """
    engine = tmp / 'rade'
    for rel in ('engine', 'assets/logo'):
        shutil.copytree(ROOT / rel, engine / rel)
    (engine / 'engine/ps/99-not-listed.ps1').write_text('# a part that no list names\n')
    r = build(app, engine)
    check(r.returncode != 0 and 'part lists differ' in r.stderr, 'build stops for an engine part that no list names')
    manifest = app / 'scripts/paste_bundles.json'
    m = json.loads(manifest.read_text())
    step = m['bundles'][0]['steps'][0]
    step.pop('url', None)
    step['urlConfig'] = 'saved-address.txt'
    manifest.write_text(json.dumps(m))
    r = build(app)
    check(r.returncode != 0 and 'urlConfig' in r.stderr, 'build stops for a step with "urlConfig" and no "url"')


def count_discards():
    """Count the discarded-error catches in the engine PowerShell, and those with no `#` comment after them on their line.

    One line may hold several; each counts. An occurrence followed later on its line by a `#` comment has a reason.

    Returns:
        (all, silent): the number of catches, and the number of them with no reason.
    """
    total = silent = 0
    for pattern in ENGINE_PS:
        for path in sorted(ROOT.glob(pattern)):
            for line in path.read_text(encoding='utf-8').split('\n'):
                pos = line.find(DISCARD)
                while pos >= 0:
                    total += 1
                    end = pos + len(DISCARD)
                    silent += '#' not in line[end:]
                    pos = line.find(DISCARD, end)
    return total, silent


def check_catch_reasons():
    """Check 6: the count of silent catches equals SILENT_CATCHES, so the number can only go down."""
    total, silent = count_discards()
    if silent < SILENT_CATCHES:
        note = ': fewer than the constant, so lower SILENT_CATCHES in tests/bundle_layout_test.py to %d' % silent
    elif silent > SILENT_CATCHES:
        note = ': more than the constant; give the new catch a reason comment on its line (never raise the constant)'
    else:
        note = ''
    check(silent == SILENT_CATCHES, 'discarded-error catches with no reason: %d of %d (constant %d)%s' % (silent, total, SILENT_CATCHES, note))


def check_uninstall_field():
    """Check 6 (engine-v40; 90-161.Z R43 E3): the manifest field "uninstall" gives its step numbers, and the build stops
    for an install step named as an Uninstall step, an unknown step, or an app without mode deploy and "restore"."""
    sys.path.insert(0, str(ROOT / 'engine'))
    import rade_build
    b = {'steps': [{'name': 'T01'}, {'name': 'U01'}, {'name': 'U02', 'after': ['U01']}]}
    good = {'name': 'App', 'steps': ['T01'], 'mode': 'deploy', 'restore': {'testSites': 'local'}, 'backup': ['L'], 'uninstall': ['U01']}
    check(rade_build.uninstall_part(good, b) == '@(1)' and rade_build.uninstall_part(dict(good, uninstall=[]), b) == '@()',
          'uninstall: the step numbers, or @() for none')
    for why, a in (('an install step', dict(good, uninstall=['T01'])), ('an unknown step', dict(good, uninstall=['U09'])),
                   ('no restore', {k: v for k, v in good.items() if k != 'restore'}), ('not deploy', dict(good, mode='test')),
                   ('a step with "after"', dict(good, uninstall=['U02']))):
        try:
            rade_build.uninstall_part(a, b)
            stopped = False
        except AssertionError:
            stopped = True
        check(stopped, 'uninstall: the build stops for %s' % why)


def main():
    """Build the test app and run the checks."""
    with tempfile.TemporaryDirectory() as d:
        app, want = make_app(Path(d))
        b = build(app)
        check(b.returncode == 0, 'build of the test app' + ('' if b.returncode == 0 else ': ' + b.stdout[-300:] + b.stderr[-300:]))
        bundle = next((app / 'scripts/gov/paste').glob('*.ps1'), None)
        text = bundle.read_text(encoding='ascii') if bundle else ''
        check_contents(text)
        check_run_steps(text)
        check_shared(text, want)
        if bundle:
            check_same_bytes(app, bundle.read_bytes())
        check_build_stops(Path(d), app)
        check_uninstall_field()
    check_catch_reasons()
    print('LAYOUT pass=%d fail=%d' % (RESULTS.count(True), RESULTS.count(False)))
    return 0 if all(RESULTS) else 1


if __name__ == '__main__':
    sys.exit(main())
