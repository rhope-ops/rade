#!/usr/bin/env python3
"""RADE engine: the UI tokens of UI standard v1 (the Administrator, 2026-11-20; docs/ui-standard.md).

engine/ui-tokens.json is the one home of the window's colors, sizes, gaps, field widths and type. This file checks it,
writes the block between the two marks below in engine/rade_ui.ps1 from it (python3 engine/rade_tokens.py --write), so
an app that copies engine/rade_ui.ps1 as it is gets the tokens too, and stops a build when that block differs from the
file. The fonts the file names go into each bundle as base64 ($fontTtf). engine/rade_build.py imports it; so does
scripts/ui_tokens.py (the contrast check and the CSS of index.html).
Run target: Python 3 (the build).
Network: none.
Writes: engine/rade_ui.ps1 (write_tokens only).
Credentials: none.
"""
import base64
import json
import re
import textwrap
from pathlib import Path

ENGINE_ROOT = Path(__file__).resolve().parent.parent
UI_FILE = ENGINE_ROOT / 'engine/rade_ui.ps1'
# The engine files this module adds (engine/rade_build.py puts them into the engine's hash, ENGINE_SHA).
FILES = ['engine/rade_tokens.py', 'engine/ui-tokens.json']


def q(s):
    """Return `s` as a PowerShell single-quoted string ('' for each quote inside)."""
    return "'" + s.replace("'", "''") + "'"


TOKENS_FILE = ENGINE_ROOT / 'engine/ui-tokens.json'
TOKENS_BEGIN = '# ---- UI tokens (UI standard v1, the Administrator, 2026-11-20; docs/ui-standard.md): written from engine/ui-tokens.json'
TOKENS_END = '# ---- End of the UI tokens'
# The properties of System.Drawing.SystemColors a token may name (it has no ButtonText: a button's text is ControlText).
SYSTEM_ROLES = {'Window', 'WindowText', 'GrayText', 'Highlight', 'HighlightText', 'HotTrack', 'ButtonFace', 'Control', 'ControlText'}
FONT_STYLES = {'', 'Bold', 'Italic', 'Underline'}


def ui_tokens():
    """Read engine/ui-tokens.json and check it. The build stops when a value is missing or of the wrong form.

    Returns:
        The tokens as a dict (the file's JSON).
    """
    t = json.loads(TOKENS_FILE.read_text(encoding='utf-8'))
    for name, c in t['colors'].items():
        assert re.fullmatch(r'[A-Za-z]+', name), 'engine/ui-tokens.json: color name %r: letters only' % name
        assert re.fullmatch(r'#[0-9A-Fa-f]{6}', c['hex']), 'engine/ui-tokens.json: color %s: hex must be #RRGGBB' % name
        assert c['system'] in SYSTEM_ROLES, 'engine/ui-tokens.json: color %s: system role %r is not one of %s' % (name, c['system'], sorted(SYSTEM_ROLES))
    dark = t['dark']['colors']   # the dark set (plan engine-v48 D6): the same names as the light set, each a #RRGGBB
    assert list(dark) == list(t['colors']), 'engine/ui-tokens.json: dark.colors must name the colors of "colors", in the same order'
    assert all(re.fullmatch(r'#[0-9A-Fa-f]{6}', h) for h in dark.values()), 'engine/ui-tokens.json: a dark color must be #RRGGBB'
    for p in t['pairs'] + t['dark']['pairs']:
        assert p['fg'] in t['colors'] and p['bg'] in t['colors'] and p['kind'] in ('text', 'non-text'), 'engine/ui-tokens.json: pair %r' % p
    for group in ('sizes', 'gaps', 'fields'):
        for k, v in t[group].items():
            assert re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', k) and isinstance(v, int) and 0 < v <= 2000, 'engine/ui-tokens.json: %s.%s' % (group, k)
    assert sorted(t['gaps'].values()) == [4, 8, 12, 16, 24], 'engine/ui-tokens.json: the gaps are 4, 8, 12, 16 and 24 (UI standard v1)'
    for name, f in t['faces'].items():
        assert f['family'] and f['fallback'], 'engine/ui-tokens.json: face %s needs a family and a fallback' % name
        assert not f['file'] or (ENGINE_ROOT / f['file']).is_file(), 'engine/ui-tokens.json: face %s: no file at %s' % (name, f['file'])
    for name, s in t['styles'].items():
        assert s['face'] in t['faces'] and 6 <= s['pt'] <= 40 and s['style'] in FONT_STYLES, 'engine/ui-tokens.json: style %s' % name
    return t


def ui_token_block(t):
    """Return the PowerShell lines of the UI tokens block of engine/rade_ui.ps1, marks included.

    Args:
        t: the tokens (ui_tokens()).

    Returns:
        A list of lines (no line ends).
    """
    def ints(group):
        """The 'Name = n' pairs of one group of whole numbers."""
        return '; '.join('%s = %d' % (k, v) for k, v in t[group].items())
    out = [TOKENS_BEGIN, '# by python3 engine/rade_tokens.py --write. Do not edit these lines: a build stops when they differ from that file.',
           "$ui.Standard = %s" % q(t['standard']),
           '# Colors: name = @(red, green, blue, the SystemColors role it takes while a Windows contrast theme is on); uses: the file.',
           '$ui.Tok = [ordered]@{}']
    cols = []
    for name, c in t['colors'].items():
        r, g, b = (int(c['hex'][i:i + 2], 16) for i in (1, 3, 5))
        cols.append('$ui.Tok.%s = @(%d, %d, %d, %s)' % (name, r, g, b, q(c['system'])))
    out += ['; '.join(cols[i:i + 3]) for i in range(0, len(cols), 3)]
    out += ['# The dark set (plan engine-v48 D6): name = @(red, green, blue); the system role is the light one.', '$ui.TokDark = [ordered]@{}']
    dk = ['$ui.TokDark.%s = @(%d, %d, %d)' % ((name,) + tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))) for name, h in t['dark']['colors'].items()]
    out += ['; '.join(dk[i:i + 4]) for i in range(0, len(dk), 4)]
    out += ['# Sizes, gaps and field widths, in pixels at 100 % (every size set after the form has scaled goes through $ui.Sc).',
            '$ui.Z = @{', '  %s' % ints('sizes'),
            '  %s' % ints('gaps'), '  %s }' % ints('fields'),
            "# Faces: name = @(family, the font file's name in the bundle ('' = none), the family used when the font cannot be loaded)."]
    faces = ['%s = @(%s, %s, %s)' % (n, q(f['family']), q(Path(f['file']).name if f['file'] else ''), q(f['fallback'])) for n, f in t['faces'].items()]
    out.append('$ui.Faces = @{ %s; %s' % (faces[0], faces[1]))
    out.append('  %s }' % '; '.join(faces[2:]))
    out += ["# Text styles: name = @(face, size in points at 100 %, font style ('' = regular)); uses: the file.", '$ui.Styles = [ordered]@{}']
    sty = ['$ui.Styles.%s = @(%s, %s, %s)' % (n, q(x['face']), repr(float(x['pt'])).rstrip('0').rstrip('.'), q(x['style'])) for n, x in t['styles'].items()]
    out += ['; '.join(sty[i:i + 4]) for i in range(0, len(sty), 4)]
    return out + [TOKENS_END]


def token_block_in(text):
    """Return (start, end) line indexes of the UI tokens block in a text (end = the index of its last line), or None."""
    lines = text.split('\n')
    try:
        a = next(i for i, x in enumerate(lines) if x.startswith(TOKENS_BEGIN))
        return a, next(i for i in range(a, len(lines)) if lines[i].startswith(TOKENS_END))
    except StopIteration:
        return None


def write_tokens():
    """Write the UI tokens block of engine/rade_ui.ps1 from engine/ui-tokens.json (--write). Prints one TOKENS line."""
    text = UI_FILE.read_text(encoding='utf-8')
    span = token_block_in(text)
    if not span:
        raise SystemExit('engine/rade_ui.ps1 has no UI tokens block (its first line starts with %r)' % TOKENS_BEGIN)
    lines = text.split('\n')
    lines[span[0]:span[1] + 1] = ui_token_block(ui_tokens())
    UI_FILE.write_text('\n'.join(lines), encoding='utf-8')
    print('TOKENS written: engine/rade_ui.ps1 from engine/ui-tokens.json')


def check_tokens(ui_text):
    """Stop the build when the UI tokens block of engine/rade_ui.ps1 differs from engine/ui-tokens.json.

    Args:
        ui_text: the text of engine/rade_ui.ps1.
    """
    span = token_block_in(ui_text)
    lines = ui_text.split('\n')
    if not span or lines[span[0]:span[1] + 1] != ui_token_block(ui_tokens()):
        raise SystemExit('engine/rade_ui.ps1: the UI tokens are old or missing: run python3 engine/rade_tokens.py --write')


def font_lines():
    """Return the bundle text that holds the fonts of engine/ui-tokens.json as base64, one here-string per file wrapped at
    100 characters as the other embedded files are (Convert.FromBase64String skips the line ends): $fontTtf = @{ ... }."""
    files = sorted({f['file'] for f in ui_tokens()['faces'].values() if f['file']})
    parts = [
        "%s = @'\n%s\n'@" % (q(Path(p).name), '\n'.join(textwrap.wrap(base64.b64encode((ENGINE_ROOT / p).read_bytes()).decode('ascii'), 100)))
        for p in files
    ]
    return '$fontTtf = @{\n' + '\n'.join(parts) + '\n}'


if __name__ == '__main__':
    import sys
    if sys.argv[1:] != ['--write']:
        sys.exit('usage: python3 engine/rade_tokens.py --write   (writes the UI tokens block of engine/rade_ui.ps1)')
    write_tokens()
