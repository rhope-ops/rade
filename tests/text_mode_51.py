#!/usr/bin/env python3
"""Run the sample bundle in TEXT mode in a child PowerShell and check its key result lines (the job text51 in .github/workflows/window.yml).

What it does: builds the sample app (schemas/examples/sample-manifest.json + tests/fixture-app, with the answers of
tests/fixture-app/answers.json, as tests/engine_test.sh does) into a temporary folder, makes a test copy of the bundle
(local file addresses, a users root in the temporary folder, the NIPR-guard name, the check gate off, as engine_test.sh
"swap" does, and no window: the engine has no switch for text mode, so the copy sets its $gui to $false), then runs
the deploy application with the answers "2", Enter, "S" (skip the hand step), Enter on standard input, as engine_test.sh
does for its first deploy run ("round 2 S", line 298). The run has a time limit: it never waits for a person.
On Windows the child is powershell.exe (Windows PowerShell 5.1); elsewhere pwsh (PowerShell 7). Run target: Windows
PowerShell 5.1 and PowerShell 7.

How to run: python tests/text_mode_51.py   (Python 3, standard library only)
Pass = last line "TEXT51 pass=N fail=0" and exit code 0; any FAIL line gives exit code 1.
Network: none. Every address in the test copy of the bundle is a local file address (no host is reached).
Writes: a temporary folder (removed at the end); nothing else, the user folder of the run is inside it.
Credentials: none. The run uses a fake user ID folder and asks for nothing.
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
WINDOWS = os.name == "nt"
# Windows PowerShell 5.1 on Windows (the floor on every NIPR computer, AGENTS.md "Project rules"); PowerShell 7 elsewhere.
POWERSHELL = ["powershell.exe", "-NoProfile"] if WINDOWS else ["pwsh", "-NoProfile"]
TIME_LIMIT = 120   # seconds for the whole run: a run that waits for input is a failure, not a hang (a decision of this task)
# The answers, as tests/engine_test.sh line 48 ("round") feeds them: 2 = the deploy application, Enter, S = skip the hand step, Enter.
ANSWERS = "2\n\nS\n\n"
APP_NAME = "Sample app (deploy)"
BUNDLE = "scripts/gov/paste/SAMPLE-R01-round-r1.ps1"
NIPR_NAME = "pc01.area52.example.invalid"   # a computer name with the NIPR label (the engine's guard reads it; tests/engine_test.sh "swap")
FAKE_USER = "test1234"                      # a fake user ID folder
ONEDRIVE = "OneDrive - United States Air Force"


def file_url(p):
    """The file address (file://) of a local path."""
    return pathlib.Path(p).resolve().as_uri()


def build_app(t):
    """Build the sample app into folder t/app and return the path of its bundle.

    Args:
        t: the temporary folder (pathlib.Path).

    Returns:
        The path of the built bundle (pathlib.Path); the process ends with FAIL if the build fails.
    """
    app = t / "app"
    shutil.copytree(ROOT / "tests" / "fixture-app", app)
    m = json.loads((ROOT / "schemas" / "examples" / "sample-manifest.json").read_text(encoding="utf-8"))
    qa = json.loads((ROOT / "tests" / "fixture-app" / "answers.json").read_text(encoding="utf-8"))   # as engine_test.sh "ans"
    for st in m["bundles"][0]["steps"]:
        if st["name"] in qa["titles"]:
            st["title"] = qa["titles"][st["name"]]
        if st["name"] == qa["step"]:
            st["answers"] = qa["answers"]
            st.update(qa["set"])
    (app / "scripts").mkdir(exist_ok=True)
    (app / "scripts" / "paste_bundles.json").write_text(json.dumps(m), encoding="utf-8")
    r = subprocess.run([sys.executable, str(ROOT / "engine" / "rade_build.py"), "--app-root", str(app)], capture_output=True, text=True)
    if r.returncode:
        sys.exit("FAIL build of the sample bundle\n" + r.stdout + r.stderr)
    return app / BUNDLE


def make_test_copy(t, bundle, users):
    """Write t/b.ps1, the test copy of the bundle, and return its path.

    Args:
        t: the temporary folder (pathlib.Path).
        bundle: the built bundle (pathlib.Path).
        users: the users root of the run (pathlib.Path), inside t.

    Returns:
        The path of the test copy (pathlib.Path); the process ends with FAIL if a line to swap is missing.
    """
    go, rel, app = file_url(t / "go.md"), file_url(t / "rel.json"), file_url(t / "app")
    s = bundle.read_text(encoding="utf-8")
    swaps = [
        (r"(?m)^function Get-OwnFqdn .*", "function Get-OwnFqdn { return '%s' }" % NIPR_NAME),   # the NIPR guard (the engine has no switch)
        (r"(?m)^\$usersRoot = .*", "$usersRoot = '%s'" % users),                          # the user folder stays in t
        (r"(?m)^\$goUrl = '.*'", "$goUrl = '%s'" % go),                                         # no network address
        (r"(?m)^\$releaseUrl = '.*'", "$releaseUrl = '%s'" % rel),
        (r"\$checkGate = \$true", "$checkGate = $false"),
        (r"(?m)^\$gui = \$true$", "$gui = $false"),                                             # text mode, also where Windows Forms exist
    ]
    for pat, new in swaps:
        s, n = re.subn(pat, lambda m, new=new: new, s)
        if not n:
            sys.exit("FAIL the bundle has no line for " + pat)
    for old, new in (("https://raw.githubusercontent.com/example-org/sample-app/v1.0.0/", app + "/"), ("https://example.invalid/import", go)):
        if old not in s:
            sys.exit("FAIL the bundle has no address " + old + " (the run must not reach a real address)")
        s = s.replace(old, new)
    out = t / "b.ps1"
    out.write_text(s, encoding="utf-8-sig")   # a byte order mark: Windows PowerShell 5.1 reads the file as UTF-8
    return out


def prepare(t):
    """Build the app, make its test copy and the user folder; return (test copy, users root)."""
    (t / "go.md").write_text("", encoding="utf-8")
    (t / "rel.json").write_text(json.dumps({"apps": {APP_NAME: "9.0.0", "Sample app": "9.0.0"}}), encoding="utf-8")
    users = t / "u"
    od = users / FAKE_USER / ONEDRIVE
    (od / "RADE" / "SampleApp" / "Config").mkdir(parents=True)
    (od / "RADE" / "SampleApp" / "Config" / "SAMPLE-site.txt").write_text("https://usaf.dps.mil/sites/fake\n", encoding="utf-8")
    return make_test_copy(t, build_app(t), users), users


def run_text(script, users):
    """Run the test copy in text mode with the answers on standard input; return (exit code, output lines).

    Args:
        script: the test copy of the bundle (pathlib.Path).
        users: the users root (pathlib.Path); USERPROFILE points to the fake user inside it.

    Returns:
        The exit code of the child, its output lines (the error stream last), and the lines of its error stream alone.
        On a timeout the last 30 lines are printed and the process ends with FAIL (the child is stopped by subprocess.run).
    """
    env = dict(os.environ, USERPROFILE=str(users / FAKE_USER))
    try:
        r = subprocess.run(POWERSHELL + ["-File", str(script)], env=env, input=ANSWERS.encode("ascii"), capture_output=True, timeout=TIME_LIMIT)
    except subprocess.TimeoutExpired as e:
        lines = ((e.stdout or b"") + (e.stderr or b"")).decode("utf-8", "replace").splitlines()
        print("\n".join(lines[-30:]))
        sys.exit("FAIL the run did not end in %d seconds (the last 30 lines are above)" % TIME_LIMIT)
    def text(b):
        """Decode UTF-8 bytes with replacement and split into lines."""
        return b.decode("utf-8", "replace").splitlines()
    return r.returncode, text(r.stdout + r.stderr), [line for line in text(r.stderr) if line.strip()]


def read_record(users):
    """What the run left in its install record: (state, installed version, version of the last run), or the error text."""
    files = list((users / FAKE_USER / ONEDRIVE / "RADE" / "Config" / "installed").glob("*.json"))
    if len(files) != 1:
        return "%d record files" % len(files)
    a = json.loads(files[0].read_text(encoding="utf-8-sig"))
    return (a["lastRun"]["state"], (a.get("installed") or {}).get("version"), a["lastRun"]["version"])


# What a PowerShell error looks like in the output, anywhere in a line: the lines both engines print under an error
# (its position, its category, its id), the usual words, and "<command> : <message>" as Windows PowerShell 5.1 starts one.
ERROR_TEXT = re.compile(r"FullyQualifiedErrorId|CategoryInfo\s*:|\bAt .+:\d+ char:\d+|\bAt line:\d+|Exception|\bERROR\b|Unhandled"
                        r"|^\S+ : (The term|Cannot|You cannot|Unable|Method invocation|Property|A parameter|Access)|is not recognized as")


def starts(lines, prefix):
    """True when one of the output lines starts with prefix."""
    return any(line.startswith(prefix) for line in lines)


def checks(code, lines, record, errors):
    """The checks, as (name, passed) pairs; each is a line that tests/engine_test.sh asserts for its first deploy run (298-345).

    Args:
        code: the exit code of the child.
        lines: the output lines of the child.
        record: what read_record gave.
        errors: the lines of the child's error stream (a PowerShell error that does not stop the run goes there).

    Returns:
        A list of (name, passed) pairs.
    """
    bad = [line for line in lines if ERROR_TEXT.search(line)]
    return [
        ("exit code 0 (got %s)" % code, code == 0),
        ("nothing on the error stream (%d lines%s)" % (len(errors), ": " + errors[0][:120] if errors else ""), not errors),
        ("the NIPR guard let the run start", not starts(lines, "This application cannot be installed in your environment")),
        (
            "skipped step: version not recorded as installed",
            starts(lines, "Note: some steps were off or skipped, so version 1.0.0 is not recorded as installed"),
        ),
        ("a file downloaded from the (local) release", starts(lines, "  Downloaded   T02\\SAMPLE-data-r1.txt")),
        ("newer-version notice of a deploy", starts(lines, "A newer version, 9.0.0, of Sample app (deploy) is on the repository page")),
        ("the step that needs the skipped step is skipped", starts(lines, "  Result: SKIPPED (it needs ")),
        ("the finished line says nothing was sent", any(re.match(r"DONE in .*Nothing was sent\.$", line) for line in lines)),
        ("install record: PASSED, not installed, last version 1.0.0 (got %s)" % (record,), record == ("PASSED", None, "1.0.0")),
        ("no ERROR or exception text (%s)" % (bad[:1],), not bad),
    ]


def powershell_version():
    """Windows only: the PowerShell version the child reports, as text (a tiny separate call)."""
    r = subprocess.run(
        POWERSHELL + ["-Command", "$PSVersionTable.PSVersion.ToString()"],
        capture_output=True, text=True, timeout=TIME_LIMIT, stdin=subprocess.DEVNULL,
    )
    return r.stdout.strip()


def main():
    """Run everything and print one PASS or FAIL line for each check, then the TEXT51 line.

    Returns:
        The exit code: 0 when every check passed, else 1.
    """
    t = pathlib.Path(tempfile.mkdtemp())
    results = []
    try:
        if WINDOWS:
            v = powershell_version()
            print("PowerShell version of the child: " + v)
            results.append(("Windows PowerShell major version is 5 (got %s)" % v, v.split(".")[0] == "5"))
        script, users = prepare(t)
        code, lines, errors = run_text(script, users)
        results += checks(code, lines, read_record(users), errors)
        if not all(ok for _, ok in results):
            print("--- last 30 lines of the run ---\n" + "\n".join(lines[-30:]) + "\n---")
    finally:
        shutil.rmtree(t, ignore_errors=True)
    for name, ok in results:
        print(("PASS " if ok else "FAIL ") + name)
    bad = sum(1 for _, ok in results if not ok)
    print("TEXT51 pass=%d fail=%d" % (len(results) - bad, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
