#!/usr/bin/env python3
"""Check RADE manifests against schemas/rade-manifest.schema.json, plus the cross-references a schema cannot express.
Usage: python3 scripts/check_manifest.py [manifest.json ...]   (default: schemas/examples/*.json)
Pass = last line "MANIFEST files=N fail=0". Needs jsonschema (PyPI) 4.x: pip install --require-hashes -r requirements.txt (hash-pinned).
"""
import json
import sys
from pathlib import Path
try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.exit('FAIL jsonschema is missing: pip install --require-hashes -r requirements.txt')

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = json.loads((ROOT / 'schemas/rade-manifest.schema.json').read_text())
Draft202012Validator.check_schema(SCHEMA)
VALIDATOR = Draft202012Validator(SCHEMA)


def _answer_ref_errors(r, s):
    """Return cross-reference error strings for a step's `answers` list.

    Args:
        r: round label string for error messages.
        s: step configuration dict from manifest.

    Returns:
        List of formatted error strings for invalid answer keys, choices, failOn, or showIf.
    """
    out = []
    qs = s.get('answers') if isinstance(s.get('answers'), list) else []
    keys = [a['key'] for a in qs if isinstance(a, dict) and isinstance(a.get('key'), str)]
    for k in sorted({k for k in keys if keys.count(k) > 1}):
        out.append('%s: step %r: answers: the key %r is used twice' % (r, s['name'], k))
    words = {}   # key -> the button words of each earlier yes/no or pick question (for failOn and showIf)
    for a in qs:
        cs = a.get('choices') if isinstance(a, dict) and isinstance(a.get('choices'), list) else []
        low = [c.strip().lower() for c in cs if isinstance(c, str)]
        if len(set(low)) != len(low):
            out.append('%s: step %r: answers: the choices of %r must differ (case and spaces ignored)' % (r, s['name'], a.get('key')))
        if not isinstance(a, dict):
            continue
        mine = ['Yes', 'No'] if a.get('kind') == 'yesno' else [c.strip() for c in cs if isinstance(c, str)] if a.get('kind') == 'pick' else []
        if 'failOn' in a and not s.get('answersOnly'):
            out.append('%s: step %r: answers: failOn of %r is only for a step with "answersOnly": true' % (r, s['name'], a.get('key')))
        if 'failOn' in a and not named(a['failOn'], mine):
            out.append('%s: step %r: answers: failOn of %r must name answers of this yes/no or pick question' % (r, s['name'], a.get('key')))
        dep = a.get('showIf') if isinstance(a.get('showIf'), dict) else None
        if dep is not None and not named(dep.get('in'), words.get(dep.get('key'), [])):
            out.append(
                '%s: step %r: answers: showIf of %r must name an earlier yes/no or pick question and answers of it'
                % (r, s['name'], a.get('key'))
            )
        if isinstance(a.get('key'), str):
            words[a['key']] = mine
    return out


def refs(m):
    """Errors the schema cannot find: step files, unique step names and answer keys, the answers that failOn and showIf
    name, app and collect step names."""
    out = []
    round_req = m.get('application', {}).get('capabilities', {}).get('round', True) is not False
    for b in m.get('bundles', []):
        r = b.get('round', '?')
        if round_req and 'round' not in b:
            out.append('%s: missing required property "round" (set application.capabilities.round: false to omit)' % r)
        have = {(f['dir'], Path(f['src']).name) for f in b.get('files', [])}
        names = [s['name'] for s in b.get('steps', [])]
        if len(names) != len(set(names)):
            out.append('%s: step names are not unique' % r)
        for s in b.get('steps', []):
            if not s['file'] and s.get('kind') != 'guide':
                out.append('%s: step %r: only a guide step may have no file' % (r, s['name']))
            elif s['file'] and (s['dir'], s['file']) not in have:
                out.append('%s: step %r: %s/%s is not in files' % (r, s['name'], s['dir'], s['file']))
            if 'answers' in s and s.get('kind') != 'guide':
                out.append('%s: step %r: answers: only a guide step (kind "guide") can ask questions' % (r, s['name']))
            if isinstance(s.get('hide'), list) and 'done' in s['hide'] and s.get('answers'):
                out.append('%s: step %r: hide: a step with answers cannot hide done (its questions come after Done)' % (r, s['name']))
            out += _answer_ref_errors(r, s)
        for a in b.get('apps', []):
            for n in a['steps']:
                if n not in names:
                    out.append('%s: app %r: unknown step %r' % (r, a['name'], n))
        for c in b.get('collect', []):
            if c.get('step') and c['step'] not in names:
                out.append('%s: collect %r: unknown step %r' % (r, c['name'], c['step']))
    return out


def named(value, allowed):
    """Say whether `value` is a list of 1 or more words that are all in `allowed` (spaces at the ends ignored).

    Args:
        value: the manifest value (failOn, or the "in" of showIf).
        allowed: the button words of the question it refers to.

    Returns:
        True when the list is valid.
    """
    return isinstance(value, list) and bool(value) and all(isinstance(w, str) and w.strip() in allowed for w in value)


def main(paths):
    paths = paths or sorted(str(p) for p in (ROOT / 'schemas/examples').glob('*.json'))
    fail = 0
    for p in paths:
        m = json.loads(Path(p).read_text())
        errs = ['%s: %s' % ('/'.join(str(x) for x in e.absolute_path) or '(root)', e.message)
                for e in sorted(VALIDATOR.iter_errors(m), key=lambda e: list(map(str, e.absolute_path)))]
        errs += refs(m)
        print(('PASS ' if not errs else 'FAIL ') + p)
        for e in errs:
            print('  ' + e)
        fail += bool(errs)
    print('MANIFEST files=%d fail=%d' % (len(paths), fail))
    return 1 if fail else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
