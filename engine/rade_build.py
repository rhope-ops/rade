#!/usr/bin/env python3
"""RADE engine: build an application's round bundles from its RADE manifest (schemas/rade-manifest.schema.json).

Consolidated from rade_build.py, rade_fields.py, rade_hash.py, and rade_parts.py (DEC-LINES, DEC-RADE, DEC-NIPR).
App facts come from the manifest "application" block; RADE's own logo is assets/logo/rho-fulcrum-128.png.

Usage:
  python3 engine/rade_build.py --app-root DIR [--manifest scripts/paste_bundles.json] [--check] [--sha]
  python3 engine/rade_build.py --content FILE...
Run target: Python 3 (the build).
Network: none.
Writes: bundle files (.ps1, .txt, .sha256.json) in the application's output folder.
Credentials: none.
"""
import argparse
import base64
import fnmatch
import hashlib
import json
import re
import sys
import textwrap
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rade_tokens

ENGINE_ROOT = Path(__file__).resolve().parent.parent
WINDOW_FILE = ENGINE_ROOT / 'engine/window.json'
APPS_FILE = ENGINE_ROOT / 'apps.json'
ENGINE_DIR = ENGINE_ROOT / 'engine/ps'
ENGINE_PARTS = [
    '01-base.ps1', '02-config.ps1', '03-files.ps1', '04-steps.ps1', '05-installed.ps1',
    '06-round.ps1', '12-resume.ps1', '07-checks.ps1', '16-site-scripts.ps1', '13-maintenance.ps1',
    '14-sp-restore.ps1', '17-uninstall.ps1', '09-start.ps1', '10-window.ps1', '11-text-mode.ps1',
]
WINDOW_PARTS = [
    'window/ui-shell.ps1', 'window/ui-cards.ps1', 'window/ui-runner.ps1',
]
WINDOW_SLOT = '    # @@WINDOW@@\n'
SP_PARTS = {'14-sp-restore.ps1', '16-site-scripts.ps1'}
SP_CHECKS = {'pnp', 'net-site', 'site-rights'}

HASH_LINE = '# @@BUNDLE-HASH %s @@\n'
GUARD_START = (
    "# ==== Paste guard, start (GENERATED): the text to the guard end is one script block; only the guard end runs it.\n"
    "$script:PasteBody = {\n"
)
GUARD_END = (
    "}\n"
    "# ==== Paste guard, end (GENERATED): the script block above runs only from here, so a cut paste runs nothing.\n"
    "$script:PasteOuter = $MyInvocation   # the whole text (engine/ps/05-installed.ps1 reads it when no file or ISE pane holds it)\n"
    ". $script:PasteBody\n"
)
TRAIL = re.compile(r'(?:\n[ \t]*)+\Z')
REVISION = re.compile(r'(?<![A-Za-z0-9])[rR][0-9]+(?![0-9A-Za-z])')

BACKUP_RE = r'[A-Za-z0-9]([A-Za-z0-9 _()-]*[A-Za-z0-9_)-])?'
START_RE = re.compile(
    r'(?:https://\S+|[A-Za-z0-9][A-Za-z0-9 ._-]*(/[A-Za-z0-9][A-Za-z0-9 ._-]*)*\.(?:ps1|html?|exe))'
)
WIN_RESERVED = {'CON', 'PRN', 'AUX', 'NUL'} | {'%s%d' % (p, k) for p in ('COM', 'LPT') for k in range(1, 10)}
BANNER = re.compile(r'^\s*# (==== |---- File )')
SHARED_RE = re.compile(r'^# >>> ([\w-]+): generated from .*?\n# <<< \1\n', re.M | re.S)
SHARED_LINE = '# @@SHARED %s@@ (RADE writes the shared block "%s" here; its text is in the bundle part "Shared blocks")'

SCRIPT_EXTS = [
    '.ps1', '.psm1', '.psd1', '.bat', '.cmd', '.vbs', '.js', '.wsf', '.hta',
    '.py', '.sh', '.exe', '.dll', '.msi', '.lnk', '.scr',
]
BASE_CHECKS = ['nipr', 'ps', 'lang', 'onedrive', 'disk', 'write', 'child', 'outlook', 'net-bookmark']
TEXT = {'.ps1', '.json', '.txt', '.md', '.csv', '.html', '.htm', '.css', '.js'}
TEXT_LIMITS = {
    'application name': 48, 'version': 14, 'summary': 150, 'step name': 56, 'step note': 200,
    'step title': 56, 'guide line': 100, 'guide lines': 10, 'doneText': 24, 'step doing': 80,
    'step help': 160, 'answer prompt': 120, 'answer choice': 33,
}
RUN_STEPS = (
    '  HOW TO RUN THIS SCRIPT (on a work computer):\n'
    '  1. Click in the text on this page, then press Ctrl+A, then press Ctrl+C.\n'
    '  2. Open the Start menu and type ISE. Click Windows PowerShell ISE.\n'
    '     Do not click Windows PowerShell ISE (x86). Do not click Run as administrator.\n'
    '  3. In Windows PowerShell ISE, click File > New. A new tab (for example Untitled2.ps1) opens.\n'
    '  4. Click in the top pane (the script pane) under the new tab, then press Ctrl+V.\n'
    '  5. Wait until this line shows at the bottom of the script pane, then press F5:\n'
    '         . $script:PasteBody\n'
    '  6. Wait until the RADE window opens, then do the steps in that window.\n'
    '     If it is not open after 1 minute, click RADE on the taskbar.\n'
    '  7. If RADE is not on the taskbar, ask for help in the Teams channel %s.\n'
    '     Do not paste the red text from Windows PowerShell ISE in Teams: it can show your folder names.\n\n'
)

ENGINE_RELEASE = 52
ROOT, APP, MANIFEST = None, None, None


def q(s):
    """Return `s` as a PowerShell single-quoted string ('' for each quote inside)."""
    return "'" + s.replace("'", "''") + "'"


def qx(s):
    """Return `s` as a PowerShell string expression (ASCII-safe for older PowerShell hosts).

    Args:
        s: input string to encode.

    Returns:
        PowerShell single-quoted string or ASCII concatenation expression.
    """
    if all(ord(c) < 128 for c in s):
        return q(s)
    parts, run = [], ''
    for c in s:
        if ord(c) < 128:
            run += c
            continue
        if run:
            parts.append(q(run))
            run = ''
        o = ord(c)
        units = [o] if o < 0x10000 else [0xD800 + ((o - 0x10000) >> 10), 0xDC00 + ((o - 0x10000) & 0x3FF)]
        parts.extend('[string][char]0x%04X' % u for u in units)
    if run:
        parts.append(q(run))
    return '(' + ' + '.join(parts) + ')'


def wrap_b64(b64_text):
    """Wrap base64 text at 100 chars inside a PowerShell single-quoted here-string."""
    if not b64_text:
        return "''"
    return "@'\n" + '\n'.join(textwrap.wrap(b64_text, 100)) + "\n'@"


def indent(text, pad):
    """Return `text` with `pad` put before each line that is not empty."""
    return ''.join((pad + x) if x.strip('\n') else x for x in text.splitlines(keepends=True))


def file_sha(rel):
    """Return the first 12 hex of the SHA-256 of one engine file (`rel` under the RADE root)."""
    return hashlib.sha256((ENGINE_ROOT / rel).read_bytes()).hexdigest()[:12]


def engine_text(include_sp=True):
    """Join the engine's PowerShell parts in run order, placing WINDOW_PARTS inside 10-window.ps1.

    Args:
        include_sp: when False, omit SharePoint-only parts (14-sp-restore.ps1, 16-site-scripts.ps1).

    Returns:
        Combined PowerShell engine script string starting with a newline.
    """
    def read(rel):
        """Read one engine PowerShell part as UTF-8."""
        return (ENGINE_DIR / rel).read_text(encoding='utf-8')
    on_disk = sorted(p.relative_to(ENGINE_DIR).as_posix() for p in ENGINE_DIR.rglob('*.ps1'))
    assert on_disk == sorted(ENGINE_PARTS + WINDOW_PARTS), 'engine/ps and the part lists differ: %s' % sorted(
        set(on_disk) ^ set(ENGINE_PARTS + WINDOW_PARTS))
    assert sum(read(p).count(WINDOW_SLOT) for p in ENGINE_PARTS) == 1, 'the window slot (# @@WINDOW@@) must be there once'
    def banner(rel):
        """Return the banner comment for one engine part."""
        return '# ==== Engine part: engine/ps/%s (sha256 %s)\n' % (rel, file_sha('engine/ps/' + rel))
    parts = ENGINE_PARTS if include_sp else [p for p in ENGINE_PARTS if p not in SP_PARTS]
    ui_head = '# ==== Engine part: engine/rade_ui.ps1 (sha256 %s)\n' % file_sha('engine/rade_ui.ps1')
    ui_body = (ENGINE_ROOT / 'engine/rade_ui.ps1').read_text(encoding='utf-8')
    window = indent(ui_head + ui_body, '    ') + ''.join(indent(banner(w) + read(w), '    ') for w in WINDOW_PARTS)
    text = ''.join(banner(p) + read(p).replace(WINDOW_SLOT, window) for p in parts)
    return '\n' + text


def app_capabilities(app=None):
    """Return normalized capability flags and settings for `app` (default APP).

    Args:
        app: optional application manifest dict (defaults to global APP).

    Returns:
        Dict with sharepoint, sitePrefix, niprLabel, round, and aumidPrefix.
    """
    a = app if app is not None else (APP or {})
    caps = a.get('capabilities') or {}
    sp = caps.get('sharepoint')
    if isinstance(sp, dict):
        sp_flag = sp.get('enabled')
        site_prefix = sp.get('sitePrefix', 'https://usaf.dps.mil/sites/')
        nipr_label = sp.get('niprLabel', '.area52.')
    else:
        sp_flag = sp
        site_prefix = 'https://usaf.dps.mil/sites/'
        nipr_label = '.area52.'
    return {
        'sharepoint': sp_flag,
        'sitePrefix': site_prefix,
        'niprLabel': nipr_label,
        'round': caps.get('round', True),
        'aumidPrefix': caps.get('aumidPrefix', ''),
    }


def sp_enabled_for_bundle(b, app=None):
    """Return True when SharePoint parts/checks are enabled for bundle `b` (or specific `app`).

    Args:
        b: bundle dict from manifest.
        app: optional app entry dict from `b['apps']`.

    Returns:
        True when SharePoint parts/checks are enabled, else False.
    """
    if app is None and b.get('apps'):
        return any(sp_enabled_for_bundle(b, a) for a in b['apps'])
    src = app if (app is not None and 'capabilities' in app) else (b if 'capabilities' in b else (APP or {}))
    caps = app_capabilities(src)
    if caps['sharepoint'] is not None:
        return bool(caps['sharepoint'])
    if 'capabilities' not in src:
        return True
    step_names = set(app.get('steps', [])) if app is not None else None
    steps = [s for s in b.get('steps', []) if step_names is None or s['name'] in step_names]
    return any(n in SP_CHECKS for s in steps for n in s.get('needs', []))


ENGINE = engine_text()
CHECK_IDS = re.findall(r"@\{ Id = '([a-z-]+)'", ENGINE)


def canonical(rest):
    """Return the text after the hash line with LF line ends and one trailing LF."""
    return TRAIL.sub('', rest.replace('\r\n', '\n')) + '\n'


def add_line(rest):
    """Return the whole bundle: the SHA-256 hash line of `rest`, then `rest`."""
    rest = canonical(rest)
    return HASH_LINE % hashlib.sha256(rest.encode('utf-8')).hexdigest() + rest


def record(out, text, release):
    """Return the JSON text of the stored hash file (<bundle>.sha256.json)."""
    sha = re.match(r'# @@BUNDLE-HASH ([0-9a-f]{64}) @@\n', text).group(1)
    build_id = re.search(r"(?m)^\$buildId = '([0-9a-f]{8})'$", text).group(1)
    rec = {'file': Path(out).name, 'sha256': sha, 'short': sha[:12] + '...' + sha[-4:], 'buildId': build_id, 'engineRelease': release}
    return json.dumps(rec, indent=2) + '\n'


def stored(out):
    """Return the path of the stored hash file (<out>.sha256.json)."""
    return out.with_name(out.name + '.sha256.json')


def text_copy(out):
    """Return the .txt copy path for a .ps1 bundle path."""
    if Path(out).suffix.lower() != '.ps1':
        raise ValueError('a bundle path must end in .ps1: %s' % out)
    return out.with_suffix('.txt')


def stale(out, text, release, label):
    """Return 1 if bundle, .txt copy, or .sha256.json is missing or out of date, else 0."""
    rec, data = stored(out), text.encode('utf-8')
    old = any(not f.exists() or f.read_bytes() != want for f, want in
              ((out, data), (text_copy(out), data), (rec, record(out, text, release).encode('utf-8'))))
    if old:
        print('STALE ' + label)
    return int(old)


def write(out, text, release):
    """Write the bundle, its .txt copy, and its stored hash file; return the HASH status line."""
    copy = text_copy(out)
    rec = record(out, text, release)
    data = text.encode('utf-8')
    out.write_bytes(data)
    copy.write_bytes(data)
    stored(out).write_bytes(rec.encode('utf-8'))
    sha = json.loads(rec)
    return 'HASH %s %s (%s)' % (out.name, sha['sha256'], sha['short'])


def content_hash(text):
    """Return the SHA-256 content hash of a script with header comments and revision tokens normalized.

    Args:
        text: script source text.

    Returns:
        Hexadecimal SHA-256 digest string.
    """
    lines = text.lstrip('\ufeff').replace('\r\n', '\n').replace('\r', '\n').split('\n')
    i, block = 0, False
    while i < len(lines):
        t = lines[i].strip()
        if block:
            block = '#>' not in t
        elif t.startswith('<#'):
            block = '#>' not in t[2:]
        elif t and not t.startswith('#'):
            break
        i += 1
    body = REVISION.sub('r#', '\n'.join(lines[i:]))
    return hashlib.sha256(body.encode('utf-8')).hexdigest()


def word_list(value, allowed):
    """Return True when `value` is a non-empty list of unique strings in `allowed`."""
    got = [w.strip() for w in value] if isinstance(value, list) and all(isinstance(w, str) for w in value) else []
    return bool(got) and len(set(got)) == len(got) and all(w in allowed for w in got)


def shared_blocks(texts):
    """Find marked shared blocks appearing in two or more text files."""
    seen = {}
    for text in texts.values():
        for m in SHARED_RE.finditer(text):
            key = '%s-%s' % (m.group(1), hashlib.sha256(m.group(0).encode()).hexdigest()[:8])
            seen.setdefault(key, [m.group(0), 0])[1] += 1
    return {k: v[0] for k, v in seen.items() if v[1] > 1}


def window_values():
    """Read and validate engine/window.json layout values.

    Returns:
        Dict mapping engine placeholder tokens to validated string values.
    """
    w = json.loads(WINDOW_FILE.read_text(encoding='utf-8'))
    share, cap = float(w['textColumn']['sharePercent']), int(w['textColumn']['maxPx'])
    min_w, min_h = int(w['minSize']['width']), int(w['minSize']['height'])
    assert 40 <= share <= 100, 'engine/window.json textColumn.sharePercent must be 40 to 100'
    assert 240 <= cap <= 4000, 'engine/window.json textColumn.maxPx must be 240 to 4000'
    assert 400 <= min_w <= 1920 and 300 <= min_h <= 1080, 'engine/window.json minSize must be 400 x 300 to 1920 x 1080'
    frame, step_ms = int(w['cardFrame']['minHeight']), int(w['minStepMs'])
    assert 120 <= frame <= 1080 and 0 <= step_ms <= 3000, 'engine/window.json cardFrame.minHeight must be 120 to 1080 and minStepMs 0 to 3000'
    return {
        '@@TEXT_SHARE@@': repr(share), '@@TEXT_MAX@@': str(cap), '@@MIN_W@@': str(min_w),
        '@@MIN_H@@': str(min_h), '@@FRAME_MIN@@': str(frame), '@@MIN_STEP_MS@@': str(step_ms),
    }


def site_values():
    """Read and validate repo, page, and help from apps.json."""
    c = json.loads(APPS_FILE.read_text(encoding='utf-8'))
    repo, page, help_name = str(c.get('repo', '')), str(c.get('page', '')), str(c.get('help', ''))
    assert re.fullmatch(r'[A-Za-z0-9._-]+/[A-Za-z0-9._-]+', repo), 'apps.json repo must be owner/name'
    assert re.fullmatch(r'https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~/-]*)?', page), 'apps.json page must be an https address'
    assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9 ._-]{0,59}', help_name), 'apps.json help must be a plain channel name'
    return {'@@RADE_REPO@@': repo, '@@HELP@@': help_name}


def logo_path():
    """Return the validated RADE logo path from engine/window.json."""
    rel = str(json.loads(WINDOW_FILE.read_text(encoding='utf-8')).get('logo', ''))
    assert re.fullmatch(r'assets/logo/[A-Za-z0-9._-]+\.png', rel), 'engine/window.json logo must be a PNG under assets/logo/'
    return rel


def ends_in(pat, x):
    """Return True when collect pattern `pat` can match an extension `x`."""
    tail = pat.lower().rsplit('*', 1)[-1]
    if len(tail) >= len(x):
        return fnmatch.fnmatchcase(x, tail[-len(x):])
    return '*' in pat and fnmatch.fnmatchcase(x[len(x) - len(tail):], tail)


def collect_problems(b):
    """Return error lines for any collect entry that could match a script extension."""
    return [
        'collect %s\\%s: the name can match a script file (%s); name the result files by their own extension, for '
        'example *.pdf (scripts never go in results)' % (c['dir'], p, ' '.join(SCRIPT_EXTS))
        for c in b.get('collect', []) for p in c['name'].split(';') if any(ends_in(p, x) for x in SCRIPT_EXTS)
    ]


def part_lines():
    """Return header lines listing each engine PowerShell part and its short SHA-256."""
    # engine/rade_ui.ps1 is listed where the build puts it: first in the window block, before the window parts.
    rels = ['engine/ps/' + x for x in ENGINE_PARTS] + ['engine/rade_ui.ps1'] + ['engine/ps/' + x for x in WINDOW_PARTS]
    rows = [' '.join('%s, sha256 %s;' % (r, file_sha(r)) for r in rels[k:k + 4]) for k in range(0, len(rels), 4)]
    return '  Engine parts, in run order:\n' + ''.join('    %s\n' % r for r in rows)


def run_steps():
    """Return the bundle header run steps with the Teams channel name from apps.json."""
    return RUN_STEPS % site_values()['@@HELP@@']


def name_spot(app):
    """Return PowerShell variable lines for application productName, subtitle, and name."""
    return '\n'.join('$%s = %s' % (k, qx(v)) for k, v in (
        ('appProduct', app.get('productName', '')),
        ('appSubtitle', app.get('subtitle', '')),
        ('appName', app.get('name', '')),
    ))


def hand_part(s):
    """Return the hide and answersOnly PowerShell fields for a guide step.

    Args:
        s: step configuration dict from manifest.

    Returns:
        PowerShell hashtable fragment string (or '').
    """
    def no(why):
        """Stop the build with the step name and error reason."""
        raise SystemExit('step %r: %s' % (s['name'], why))
    out, guide, hide = '', s.get('kind', 'script') == 'guide', s.get('hide')
    if 'hide' in s:
        bad_hide = (
            not guide or not isinstance(hide, list) or not 1 <= len(hide) <= 2
            or len(set(hide)) != len(hide) or set(hide) - {'done', 'failed', 'skip'}
            or ('done' in hide and s.get('answers'))
        )
        if bad_hide:
            no(
                'hide: only for a guide step (kind "guide"): 1 or 2 of done, failed and skip, each one time '
                '(one button stays); not done when the step has answers'
            )
        out += '; Hide = @(%s)' % ', '.join(q(h) for h in hide)
    if 'answersOnly' in s:
        used = [f for f in ('hide', 'doneText', 'doneLog', 'marker', 'url', 'urlConfig', 'file', 'guide') if s.get(f)]
        if s['answersOnly'] is not True or not guide or not s.get('answers') or used:
            no('answersOnly: true, only for a guide step (kind "guide") with "answers" and no Done card (so without: %s)' % (', '.join(used) or 'nothing'))
        out += '; AnswersOnly = $true'
    return out


def restore_part(a):
    """Return the PowerShell hashtable for an app's restore configuration, or '$null'.

    Args:
        a: application dict from manifest.

    Returns:
        PowerShell hashtable string or '$null'.
    """
    r = a.get('restore')
    if not r:
        return '$null'
    assert a.get('backup'), 'app %r: restore needs backup (Restore puts back the lists that Back up saves)' % a['name']
    sites = r.get('testSites', [])
    local = sites == 'local'
    assert local or (isinstance(sites, list) and sites and all(isinstance(n, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]*', n) for n in sites)), \
        'app %r: restore.testSites: "local", or one or more site names (letters, digits, "_", "-")' % a['name']
    pause = '$null'
    pz = r.get('pause')
    if pz:
        plain = re.fullmatch(BACKUP_RE, pz['list']) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9 _-]*', pz['title']) and re.fullmatch(r'[A-Za-z0-9_]+', pz['field'])
        assert plain, 'app %r: restore.pause list, title and field hold plain names only' % a['name']
        assert re.fullmatch(r'[A-Za-z0-9 _-]{1,40}', pz['on']), 'app %r: restore.pause.on: a plain value' % a['name']
        pause = '@{ List = %s; Title = %s; Field = %s; On = %s }' % (q(pz['list']), q(pz['title']), q(pz['field']), q(pz['on']))
    return '@{ TestSites = @(%s); Local = %s; Pause = %s }' % ('' if local else ', '.join(map(q, sites)), '$true' if local else '$false', pause)


def uninstall_part(a, b):
    """Return the PowerShell array of step indexes for an app's uninstall configuration.

    Args:
        a: application dict from manifest.
        b: bundle dict from manifest.

    Returns:
        PowerShell array expression string (for example '@()' or '@(1)').
    """
    names = [s['name'] for s in b['steps']]
    un = a.get('uninstall', [])
    if not un:
        return '@()'
    assert len(set(un)) == len(un) and all(n in names for n in un), 'app %r: uninstall: unique names of steps of this bundle' % a['name']
    both = sorted(set(un) & set(a['steps']))
    assert not both, 'app %r: uninstall: a step is an install step too (%s); give Uninstall its own steps' % (a['name'], ', '.join(both))
    assert a.get('mode') == 'deploy' and (a.get('restore') or not sp_enabled_for_bundle(b, a)), (
        'app %r: uninstall needs mode deploy and "restore" (its test sites; Uninstall backs up first)' % a['name']
    )
    for n in un:
        s = b['steps'][names.index(n)]
        assert not s.get('after') and not s.get('ask'), (
            'app %r: uninstall step %r: no "after" or "ask" (Uninstall runs its steps in order and stops at the first that is not done)'
            % (a['name'], n)
        )
    return '@(%s)' % ', '.join(str(names.index(n)) for n in un)


def step_default(s):
    """Return a step's default tick boolean (comparing file hashes when configured)."""
    d = s.get('default', True)
    if isinstance(d, dict):
        return files_hash(d['paths']) != d['passed']
    return bool(d)


def files_hash(paths):
    """Return the first 16 hex of one SHA-256 over the given app files."""
    h = hashlib.sha256()
    for rel in sorted(paths):
        h.update(rel.encode() + b'\0' + (ROOT / rel).read_bytes() + b'\0')
    return h.hexdigest()[:16]


def here(text):
    """Return `text` as a PowerShell single-quoted here-string (@' ... '@) with LF line ends."""
    text = text.replace('\r\n', '\n')
    if text.endswith('\n'):
        text = text[:-1]
    for line in text.split('\n'):
        if line.startswith("'@"):
            raise SystemExit("cannot embed: a line starts with '@")
    return "@'\n" + text + "\n'@"


def _app_checks(a, b, idx, names, mode):
    """Collect required check IDs and validate step dependency order for one application.

    Args:
        a: application dict from manifest.
        b: bundle dict from manifest.
        idx: list of step indices in `b['steps']` for this application.
        names: ordered list of all step names in bundle `b`.
        mode: application mode ('test' or 'deploy').

    Returns:
        Tuple of (ordered check IDs list, set of required check IDs).
    """
    need = set(BASE_CHECKS) - ({'outlook'} if mode == 'deploy' else set())
    for i in idx:
        for n in b['steps'][i].get('needs', []):
            assert n in CHECK_IDS, 'unknown check %r in step %r' % (n, names[i])
            need.add(n)
    checks = [c for c in CHECK_IDS if c in need]
    byname = {names[i]: b['steps'][i] for i in idx}

    def reach(n, seen=None, byname=byname):
        """Collect all transitive step dependencies for step `n`."""
        seen = seen if seen is not None else set()
        for d in byname[n].get('after', []):
            if d not in seen:
                seen.add(d)
                reach(d, seen, byname)
        return seen

    hand = []
    for i in sorted(idx):
        s = b['steps'][i]
        for d in s.get('after', []):
            if d not in byname or names.index(d) >= i:
                raise SystemExit('app %r: step %r needs %r (after), which is not an earlier step of this app' % (a['name'], names[i], d))
        if s.get('kind') == 'guide':
            hand.append(names[i])
        elif mode == 'deploy' and hand and not (reach(names[i]) & set(hand)):
            raise SystemExit(
                'app %r: automatic step %r comes after the hand step %r but does not need it: move it before, or name the step it needs in "after"'
                % (a['name'], names[i], hand[0])
            )
    return checks, need


def app_lines(b):
    """Return the $apps catalog lines for bundle `b`.

    Args:
        b: bundle dict from manifest.

    Returns:
        List of PowerShell '$apps += ...' lines.
    """
    names = [s['name'] for s in b['steps']]
    apps = b.get('apps') or [{'name': b.get('app', APP['name']), 'summary': b['title'], 'steps': names}]
    out = []
    for a in apps:
        idx = [names.index(n) for n in a['steps']]
        mode, version = a.get('mode', 'test'), a.get('version', '')
        assert mode != 'deploy' or version, 'app %r: a deploy needs a version' % a['name']
        checks, need = _app_checks(a, b, idx, names, mode)
        mk = a.get('marker')
        marker = '$null'
        if mk:
            assert (re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9 ]*', mk['list']) and re.fullmatch(r'[A-Za-z0-9]+', mk['key'])
                    and re.fullmatch(r'[A-Za-z0-9_]+', mk['field'])), 'app %r: marker list, key and field hold letters and digits only' % a['name']
            assert mode == 'deploy' and 'site-rights' in need, 'app %r: a marker needs mode deploy and a step that needs site-rights' % a['name']
            marker = '@{ List = %s; Key = %s; Field = %s }' % (q(mk['list']), q(mk['key']), q(mk['field']))
        start = a.get('start', '')
        assert not start or START_RE.fullmatch(start), 'app %r: start must be a relative .ps1/.html/.exe path or https:// URL' % a['name']
        backup = a.get('backup', [])
        ok = all(re.fullmatch(BACKUP_RE, n) for n in backup) and not {n.upper() for n in backup} & WIN_RESERVED
        assert ok and len({n.lower() for n in backup}) == len(backup), 'app %r: backup: unique plain titles, not a name Windows reserves' % a['name']
        out.append(
            '$apps += @{ Name = %s; Summary = %s; Steps = @(%s); Checks = @(%s); Mode = %s; Version = %s; '
            'Marker = %s; Start = %s; Backup = @(%s); Restore = %s; Uninstall = %s }'
            % (q(a['name']), q(a['summary']), ', '.join(map(str, idx)), ', '.join(map(q, checks)), q(mode), q(version),
               marker, q(start), ', '.join(map(q, backup)), restore_part(a), uninstall_part(a, b))
        )
    return out


def _answer_item(s, i, a, words, no):
    """Validate one answer entry and return its PowerShell hashtable fragment.

    Args:
        s: step configuration dict from manifest.
        i: 1-based question index within `s['answers']`.
        a: single answer dict to validate and format.
        words: mapping of earlier question keys to their allowed answer strings (updated in place).
        no: error-reporting callback taking a failure reason string.

    Returns:
        PowerShell hashtable fragment string for this answer item.
    """
    if not isinstance(a, dict) or set(a) - {'key', 'prompt', 'kind', 'choices', 'failOn', 'showIf'}:
        no('question %d: only key, prompt, kind, choices, failOn and showIf' % i)
    key, prompt, kind, choices = a.get('key'), a.get('prompt'), a.get('kind'), a.get('choices')
    if not isinstance(key, str) or not re.fullmatch(r'[a-z][a-z0-9-]{0,23}', key):
        no('question %d: the key must be 1 to 24 lowercase letters, digits or "-", starting with a letter' % i)
    if key in words:
        no('question %d: the key %r is used twice' % (i, key))
    if not isinstance(prompt, str) or not 1 <= len(prompt) <= TEXT_LIMITS['answer prompt']:
        no('question %r: the prompt must have 1 to %d characters' % (key, TEXT_LIMITS['answer prompt']))
    if kind not in ('yesno', 'pick', 'text'):
        no('question %r: the kind must be yesno, pick or text' % key)
    if kind == 'pick':
        bad_choices = (
            not isinstance(choices, list) or not 2 <= len(choices) <= 4
            or not all(isinstance(c, str) and 1 <= len(c) <= TEXT_LIMITS['answer choice'] for c in choices)
        )
        if bad_choices:
            no('question %r: a pick needs 2 to 4 choices of 1 to %d characters' % (key, TEXT_LIMITS['answer choice']))
        if len({c.strip().lower() for c in choices}) != len(choices):
            no('question %r: the choices of a pick must differ (case and spaces ignored)' % key)
    elif 'choices' in a:
        no('question %r: only a pick has choices' % key)
    mine = [] if kind == 'text' else ['Yes', 'No'] if kind == 'yesno' else [c.strip() for c in choices]
    fail, dep = a.get('failOn'), a.get('showIf')
    if 'failOn' in a and not (s.get('answersOnly') and mine and word_list(fail, mine)):
        no('question %r: failOn (only in a step with "answersOnly": true) names 1 or more answers of this yes/no or pick question, each one time' % key)
    dep_ok = isinstance(dep, dict) and set(dep) == {'key', 'in'} and isinstance(dep['key'], str) and word_list(dep['in'], words.get(dep['key'], []))
    if 'showIf' in a and not dep_ok:
        no('question %r: showIf needs "key" (an earlier yes/no or pick question of this step) and "in" (1 or more of its answers, each one time)' % key)
    more = ('; FailOn = @(%s)' % ', '.join(q(w.strip()) for w in fail)) if fail else ''
    more += ('; ShowKey = %s; ShowIn = @(%s)' % (q(dep['key']), ', '.join(q(w.strip()) for w in dep['in']))) if dep else ''
    words[key] = mine
    return '@{ Key = %s; Prompt = %s; Kind = %s; Choices = @(%s)%s }' % (
        q(key), q(prompt.strip()), q(kind), ', '.join(q(c.strip()) for c in choices or []), more
    )


def answers_part(s):
    """Return the PowerShell Answers field for a guide step, or ''.

    Args:
        s: step configuration dict from manifest.

    Returns:
        PowerShell hashtable fragment string (or '').
    """
    if 'answers' not in s:
        return ''
    qs = s['answers']
    def no(why):
        """Stop the build with the step name and invalid answer reason."""
        raise SystemExit('step %r: answers: %s' % (s['name'], why))
    if s.get('kind', 'script') != 'guide':
        no('only a guide step (kind "guide") can ask questions')
    if not isinstance(qs, list) or not 1 <= len(qs) <= 4:
        no('1 to 4 questions, not %s' % (len(qs) if isinstance(qs, list) else type(qs).__name__))
    words, out = {}, []
    for i, a in enumerate(qs, 1):
        out.append(_answer_item(s, i, a, words, no))
    return '; Answers = @(%s)' % ', '.join(out)


def source_text(rel):
    """Return an app text file decoded as UTF-8."""
    try:
        return (ROOT / rel).read_bytes().decode('utf-8')
    except UnicodeDecodeError as err:
        raise SystemExit('cannot embed %s: invalid UTF-8 text' % rel) from err


def use_shared(text, shared):
    """Return `text` with each shared block replaced by its SHARED line marker."""
    def one(m):
        """Return the SHARED line for a block in `shared`, else the block itself."""
        key = '%s-%s' % (m.group(1), hashlib.sha256(m.group(0).encode()).hexdigest()[:8])
        return (SHARED_LINE % (key, m.group(1)) + '\n') if key in shared else m.group(0)
    out = SHARED_RE.sub(one, text)
    back = re.sub(r'^# @@SHARED (\S+)@@.*\n', lambda m: shared[m.group(1)], out, flags=re.M)
    assert back == text, 'a shared block does not round-trip'
    return out


def file_parts(b):
    """Return ($shared lines, $files lines) for the bundle's files.

    Args:
        b: bundle dict from manifest.

    Returns:
        Tuple of (shared block assignment lines, file assignment lines).
    """
    texts = {f['src']: source_text(f['src']) for f in b['files'] if (ROOT / f['src']).suffix.lower() in TEXT}
    shared = shared_blocks(texts)
    lines = ["$shared[%s] = %s" % (q(k), here(v)) for k, v in sorted(shared.items())]
    parts = []
    for i, f in enumerate(b['files'], 1):
        src = ROOT / f['src']
        data = src.read_bytes()
        sha = hashlib.sha256(data).hexdigest()[:12]
        if f['src'] in texts:
            body, kind = here(use_shared(texts[f['src']], shared)), 'text'
        else:
            b64 = base64.b64encode(data).decode('ascii')
            body, kind = wrap_b64(b64), 'base64'
        parts.append('# ---- File %d of %d: %s\\%s (from %s, sha256 %s)' % (i, len(b['files']), f['dir'], src.name, f['src'], sha))
        parts.append("$files += @{ Dir = %s; Name = %s; Kind = '%s'; Sha = '%s'; Data = %s }"
                     % (q(f['dir']), q(src.name), kind, sha, body))
    return lines, parts


def step_lines(b):
    """Return the $steps lines for bundle `b`.

    Args:
        b: bundle dict from manifest.

    Returns:
        List of PowerShell '$steps += ...' lines.
    """
    steps = [
        '$steps += @{ Name = %s; Title = %s; Dir = %s; File = %s; Default = $%s; AskParam = %s; AskPrompt = %s; ScreenOnly = %s; Minutes = %d; Args = %s; '
        'Note = %s; Kind = %s; Guide = @(%s); Url = %s; UrlConfig = %s; Marker = %s; Estimate = %d; '
        'DoneText = %s; DoneLog = %s; Makes = @(%s); After = @(%s); Optional = $%s; Help = %s }'
        % (q(s['name']), q(s.get('title', '')), q(s['dir']), q(s['file']), 'true' if step_default(s) else 'false',
           q(s.get('ask', {}).get('param', '')), q(s.get('ask', {}).get('prompt', '')), q(s.get('screenOnly', '')),
           int(s.get('minutes', 30)), q(s.get('args', '')), q(s.get('note', '')), q(s.get('kind', 'script')),
           ', '.join(q(g) for g in s.get('guide', [])), q(s.get('url', '')), q(s.get('urlConfig', '')), q(s.get('marker', '')),
           int(s.get('estimate', 0)) * 60, q(s.get('doneText', '')), q(s.get('doneLog', '')),
           ', '.join('@{ kind = %s; name = %s }' % (q(m['kind']), q(m['name'])) for m in s.get('makes', [])), ', '.join(q(a) for a in s.get('after', [])),
           'true' if s.get('default', True) is False else 'false', q(s.get('help', '')))
        for s in b['steps']
    ]
    for s in b['steps']:
        assert s.get('url') or not s.get('urlConfig'), 'a step with "urlConfig" needs its own "url" (the host rule): %s' % s['name']
        assert (s.get('kind') == 'guide' and not s['file']) or any(f['dir'] == s['dir'] and Path(f['src']).name == s['file'] for f in b['files']), s
    def doing(s):
        """Return Doing field string if present."""
        return ('; Doing = %s' % q(s['doing'].strip())) if s.get('doing') else ''
    return [line[:-2] + doing(s) + hand_part(s) + answers_part(s) + ' }' for line, s in zip(steps, b['steps'], strict=True)]


def fetch_lines(b):
    """Return the $fetch lines for data files in bundle `b`.

    Args:
        b: bundle dict from manifest.

    Returns:
        List of PowerShell '$fetch += ...' lines.
    """
    fetch = []
    for f in b.get('fetch', []):
        if 'src' in f:
            data = (ROOT / f['src']).read_bytes()
            url = 'https://raw.githubusercontent.com/' + APP['repo'] + '/' + b.get('release', 'main') + '/' + f['src']
            fetch.append((f['dir'], Path(f['src']).name, url, hashlib.sha256(data).hexdigest()))
        else:
            fetch.append((f['dir'], f['name'], f['url'], ''))
    return ['$fetch += @{ Dir = %s; Name = %s; Url = %s; Sha = %s }' % tuple(q(x) for x in t) for t in fetch]


def help_rules_line():
    """Return the PowerShell $appHelpRules line from manifest application.helpRules."""
    rules = APP.get('helpRules', [])
    items = []
    for r in rules:
        cov = ('; Covers = %s' % q(r['covers'])) if r.get('covers') else ''
        items.append('@{ Re = %s; Text = %s%s }' % (q(r['re']), q(r['text']), cov))
    return '$appHelpRules = @(%s)' % ', '.join(items)


def engine_for_app(include_sp=True):
    """Substitute window.json, apps.json, and application placeholders into ENGINE.

    Args:
        include_sp: when False, omit SharePoint-only engine parts.

    Returns:
        Parameterized PowerShell engine script string for the current APP.
    """
    ui_file = ENGINE_ROOT / 'engine/rade_ui.ps1'
    rade_tokens.check_tokens(ui_file.read_text(encoding='utf-8'))
    in_ps = {k: v for k, v in site_values().items() if k != '@@RADE_REPO@@'}
    caps = app_capabilities()
    engine = ENGINE if include_sp else engine_text(include_sp=False)
    for src, values in (('engine/window.json', window_values()), ('apps.json', in_ps)):
        for k, v in values.items():
            if engine.count(k) != 1:
                raise SystemExit('the engine must hold %s exactly once (%s)' % (k, src))
            engine = engine.replace(k, v)
    engine = (
        engine
        .replace('@@SP_ENABLED@@', 'true' if include_sp else 'false')
        .replace("'@@NIPR_LABEL@@'", q(caps['niprLabel']))
        .replace("'@@SITE_PREFIX@@'", q(caps['sitePrefix']))
    )
    return engine.replace('@@HOME@@', APP['home']).replace('@@PREFIX@@', APP['prefix']).replace('@@APP@@', APP['folder'])


def app_logo_bytes(field='logo'):
    """Return PNG bytes for application.logo or application.logoDark, or b''.

    Args:
        field: manifest application key ('logo' or 'logoDark').

    Returns:
        Raw PNG bytes, or b'' if the field is unset.
    """
    rel = APP.get(field)
    if not rel:
        return b''
    path = (ROOT / rel).resolve()
    if rel.startswith('/') or '..' in Path(rel).parts or not path.is_relative_to(ROOT):
        sys.exit('application.%s: the path must stay inside the application repo: %s' % (field, rel))
    if not path.is_file():
        sys.exit('application.%s: no file at %s' % (field, rel))
    data = path.read_bytes()
    if not data.startswith(b'\x89PNG\r\n\x1a\n'):
        sys.exit('application.%s: not a PNG file: %s' % (field, rel))
    return data


def bundle_body(b):
    """Return the bundle body (Settings, Shared blocks, Files, Steps, Applications, Engine).

    Args:
        b: bundle dict from manifest.

    Returns:
        Combined PowerShell bundle body string before header and paste guard.
    """
    shared, files = file_parts(b)
    collect = ['$collect += @{ Dir = %s; Name = %s; Step = %s }' % (q(c['dir']), q(c['name']), q(c.get('step', ''))) for c in b.get('collect', [])]
    cleanup = ['$cleanup += @{ Path = %s; Kind = %s }' % (q(c['path']), q(c['kind'])) for c in b.get('cleanup', [])]
    known = sorted({f.name for d, pat in APP['knownDirs'] for f in (ROOT / d).glob(pat)})
    logo = base64.b64encode(LOGO.read_bytes()).decode('ascii')
    app_logo, app_dark = (base64.b64encode(app_logo_bytes(f)).decode('ascii') for f in ('logo', 'logoDark'))
    go = q('https://raw.githubusercontent.com/' + APP['repo'] + '/main/go.md')
    rel = q('https://raw.githubusercontent.com/' + APP['repo'] + '/main/rade-release.json')
    parts = [
        ('Settings', [
            '$goUrl = %s' % go, '$releaseUrl = %s' % rel,
            "$webAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) RADE'",
            '$logoPng = ' + wrap_b64(logo),
            '$scriptExts = @(' + ', '.join(q(x) for x in SCRIPT_EXTS) + ')',
            '$appLogoPng = ' + wrap_b64(app_logo),
            '$appLogoDarkPng = ' + wrap_b64(app_dark),
            help_rules_line(),
            '$ownPatterns = @(' + ', '.join(q(p) for p in APP['own']) + ')',
            '$round = %s' % q(b.get('round', 'R00')), '$appFolder = %s' % q(APP['folder']),
            '$appDisplay = %s' % q(APP.get('displayName', '')),
            name_spot(APP),
            "$usersRoot = $(if ($env:USERPROFILE) { Split-Path -Parent $env:USERPROFILE } else { Join-Path $env:SystemDrive 'Users' })",
        ]),
        ('Shared blocks (%d): each is written back into the files that name it' % len(shared), ['$shared = @{}'] + shared),
        ('Files written to this computer (%d)' % len(b['files']), ['$files = @()'] + files),
        ('Steps (%d), downloads, results to collect, clean-up' % len(b['steps']),
         ['$fetch = @()'] + fetch_lines(b) + ['$steps = @()'] + step_lines(b) + ['$collect = @()'] + collect + ['$cleanup = @()'] + cleanup),
        ('Applications', ['$known = @(%s)' % ', '.join(q(k) for k in known), '$apps = @()'] + app_lines(b)),
    ]
    text = ''.join('# ==== Part %d of %d: %s\n%s\n' % (i, len(parts) + 1, title, '\n'.join(lines)) for i, (title, lines) in enumerate(parts, 1))
    end_head = '# ==== Part %d of %d: the RADE engine (engine/ps, in run order)' % (len(parts) + 1, len(parts) + 1)
    return text + end_head + engine_for_app(include_sp=sp_enabled_for_bundle(b))


def contents(head, body):
    """Return the generated Contents comment with exact bundle line numbers.

    Args:
        head: header string preceding the Contents block.
        body: bundle body string whose section banners are indexed.

    Returns:
        Generated Contents comment block ending with a newline.
    """
    marks, inside = [], False
    for n, line in enumerate(body.split('\n'), 1):
        if inside:
            inside = not line.startswith("'@")
        elif BANNER.match(line):
            marks.append((n, line.strip()[7:]))
        elif line.endswith("@'"):
            inside = True
    first = head.count('\n') + len(marks) + 3
    rows = ['#   line %5d  %s' % (first + n - 1, (('  ' if line.startswith('File') else '') + line)[:150]) for n, line in marks]
    return '# ==== Contents (GENERATED; the line numbers are lines of this bundle)\n' + '\n'.join(rows) + '\n'


def build(b):
    """Build and return the complete signed bundle text for manifest bundle `b`.

    Args:
        b: bundle dict from manifest.

    Returns:
        Complete bundle script string with SHA-256 hash line and paste guard.
    """
    bad = collect_problems(b)
    if bad:
        sys.exit('\n'.join(bad))
    body = bundle_body(b)
    build_id = hashlib.sha256(body.encode('utf-8')).hexdigest()[:8]
    modes = {a.get('mode', 'test') for a in b.get('apps', [])} or {'test'}
    sends = (' on this computer. It sends nothing.' if modes == {'deploy'} else ', then opens an Outlook draft with them (never sent; a deploy makes no draft).'
             if 'deploy' in modes else ', then opens an Outlook draft with them (never sent).')
    head = (
        '<#\n  GENERATED by the RADE engine from %s; do not edit. Run it with the steps below.\n%s'
        '  RADE, round bundle: %s.\n'
        '  GENERATED by the RADE engine (%s engine/rade_build.py, sha256 %s) from %s; do not edit.\n'
        '%s'
        '  What it does: it uses your Windows profile folder. It writes the files below into the task folders under\n'
        '  %%OneDrive%%\\RADE\\%s (replacing older copies), runs the steps,\n'
        '  and saves its results in Rounds\\%s%s No download, no admin rights.\n'
        '  To read it: the Contents list below gives the line of each part and file; each part starts with a "# ====" line.\n'
        '#>\n%s$buildId = \'%s\'\n$engineRelease = %d\n'
        % (MANIFEST, run_steps(), b['title'], site_values()['@@RADE_REPO@@'], file_sha('engine/rade_build.py'),
           MANIFEST, part_lines(), APP['folder'], b.get('round', 'R00'), sends, GUARD_START, build_id, ENGINE_RELEASE)
    )
    return add_line(head + contents(head, body) + body.rstrip('\n') + '\n' + GUARD_END)


def text_lengths(b):
    """Return WARNING lines for any manifest text field exceeding TEXT_LIMITS.

    Args:
        b: bundle dict from manifest.

    Returns:
        List of formatted warning strings for fields exceeding limits.
    """
    found = []
    def over(what, field, value):
        """Append a warning if `value` exceeds TEXT_LIMITS[field]."""
        if isinstance(value, str) and len(value) > TEXT_LIMITS[field]:
            found.append('WARNING text length: %s: %s has %d characters, the limit is %d (docs/window-design.md "Text lengths")'
                         % (what, field, len(value), TEXT_LIMITS[field]))
    if not b.get('apps') and APP:
        over('application %r' % str(APP.get('name', ''))[:40], 'application name', APP.get('name'))
    for app in b.get('apps', []):
        what = 'application %r' % app.get('name', '')[:40]
        over(what, 'application name', app.get('name'))
        over(what, 'version', app.get('version'))
        over(what, 'summary', app.get('summary'))
    for st in b.get('steps', []):
        what = 'step %r' % st.get('name', '')[:40]
        over(what, 'step name', st.get('name'))
        over(what, 'step title', st.get('title'))
        over(what, 'step note', st.get('note'))
        over(what, 'doneText', st.get('doneText'))
        over(what, 'step doing', st.get('doing'))
        over(what, 'step help', st.get('help'))
        for g in st.get('guide', []):
            over(what, 'guide line', g)
        numbered = [g for g in st.get('guide', []) if isinstance(g, str) and re.match(r'\d+\.\s+\S', g)]
        if len(numbered) > TEXT_LIMITS['guide lines']:
            found.append('WARNING text length: %s: guide has %d numbered lines, the limit is %d (docs/window-design.md "Text lengths")'
                         % (what, len(numbered), TEXT_LIMITS['guide lines']))
    return found


LOGO = ENGINE_ROOT / logo_path()
ENGINE_SHA = hashlib.sha256(b''.join(
    rel.encode() + b'\0' + (ENGINE_ROOT / rel).read_bytes() + b'\0'
    for rel in ['engine/rade_build.py', 'engine/rade_ui.ps1'] + ['engine/ps/' + x for x in ENGINE_PARTS + WINDOW_PARTS]
    + ['engine/window.json', 'apps.json', logo_path()] + rade_tokens.FILES
)).hexdigest()


def main():
    """Parse CLI arguments and build, check, print SHA, or compute content hashes."""
    global ROOT, APP, MANIFEST
    ap = argparse.ArgumentParser(description='Build RADE round bundles for one application.')
    ap.add_argument('--app-root', help='the application repo root')
    ap.add_argument('--manifest', default='scripts/paste_bundles.json', help='manifest path inside the app repo')
    ap.add_argument('--check', action='store_true', help='exit 1 if a bundle is out of date')
    ap.add_argument('--sha', action='store_true', help="print the engine's sha256 (every engine file) and exit")
    ap.add_argument('--content', nargs='+', help='print content hashes for the given script files')
    a = ap.parse_args()
    if a.content:
        for f in a.content:
            print('CONTENT %s %s' % (content_hash(Path(f).read_text(encoding='utf-8')), f))
        return
    if a.sha:
        print(ENGINE_SHA)
        return
    if not a.app_root:
        ap.error('--app-root is required')
    ROOT, MANIFEST = Path(a.app_root).resolve(), a.manifest
    m = json.loads((ROOT / MANIFEST).read_text(encoding='utf-8'))
    APP = m['application']
    stale_count = 0
    for b in m['bundles']:
        text_copy(ROOT / b['out'])
    for b in m['bundles']:
        out = ROOT / b['out']
        text = build(b)
        if a.check:
            stale_count += stale(out, text, ENGINE_RELEASE, b['out'])
            continue
        out.parent.mkdir(parents=True, exist_ok=True)
        print('BUILT %s bytes=%d files=%d steps=%d' % (b['out'], len(text), len(b['files']), len(b['steps'])))
        print(write(out, text, ENGINE_RELEASE))
        for line in text_lengths(b):
            print(line)
    if a.check:
        print('PASTE bundles=%d stale=%d' % (len(m['bundles']), stale_count))
        sys.exit(1 if stale_count else 0)


if __name__ == '__main__':
    main()
