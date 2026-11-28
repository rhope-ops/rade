#!/usr/bin/env python3
"""IMMUTABLE NIPR code-safety guard (DEC-NIPR).

Enforces the 7 non-overridable NIPR invariants across PowerShell, Python,
shell scripts, workflows, and generated paste bundles:
  1. Zero -ExecutionPolicy Bypass / Unrestricted anywhere (defensive clearing
     of inherited PSExecutionPolicyPreference is allowed).
  2. Zero inline C# compilation (Add-Type -MemberDefinition/-TypeDefinition,
     csc.exe, CodeDomProvider).
  3. Zero .ps1 script execution or staging under %TEMP% (GetTempPath / $env:TEMP).
  4. Zero hardcoded tenant/OneDrive paths ('OneDrive - United States Air Force',
     or non-placeholder https://usaf.dps.mil/sites/<name> in code).
  5. Zero Invoke-Expression (iex), [ScriptBlock]::Create, or TLS downgrade
     (-bor 3072, Ssl3, Tls11).
  6. Mandatory security-reviewer comment block directly above any
     -WindowStyle Hidden or WScript.Shell .lnk creation explaining its benign
     GUI-host purpose.
  7. Bounded network timeouts & proxy DefaultNetworkCredentials isolation
     (no unbounded System.Net.WebClient; no UseDefaultCredentials = $true).

Usage:
    python3 scripts/nipr_guard.py [paths...]   # scan repo tracked files or paths
    python3 scripts/nipr_guard.py --test       # run self-test
Prevents: NIPR/MDE cyber compliance violations and insecure script patterns
Network: none.
Writes: none.
Credentials: none.
Standard library only.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

SCAN_SUFFIXES = {".ps1", ".psm1", ".psd1", ".py", ".sh", ".yml", ".yaml", ".txt"}
SKIP_PREFIXES = (
    ".git/",
    "docs/",
    "ref/",
    "node_modules/",
    ".venv/",
)
SELF_REL = "scripts/nipr_guard.py"

# Invariant 1: ExecutionPolicy Bypass / Unrestricted and Unblock-File / Zone.Identifier removal
RE_EXEC_BYPASS = re.compile(
    r"(?i)(?:-(?:ExecutionPolicy|Exec|EP)\s+(?:Bypass|Unrestricted)\b"
    r"|Set-ExecutionPolicy\s+[^\r\n]*\b(?:Bypass|Unrestricted)\b)"
)
RE_UNBLOCK = re.compile(
    r"(?i)(?:\bUnblock-File\b"
    r"|(?:Remove-Item|Clear-Content|del|erase|ri|clc)\b[^\r\n]*Zone\.Identifier\b"
    r"|Zone\.Identifier\b[^\r\n]*(?:Remove-Item|Clear-Content)\b)"
)

# Invariant 2: Inline C# compilation (Add-Type -AssemblyName is allowed)
RE_INLINE_CS = re.compile(
    r"(?i)(?:Add-Type\s+[^\r\n]*-(?:MemberDefinition|TypeDefinition|CodeDomProvider)\b"
    r"|\bcsc\.exe\b)"
)

# Invariant 3: %TEMP% .ps1 execution/staging
RE_TEMP_PS1 = re.compile(
    r"(?i)(?:(?:GetTempPath\(\)|\$env:(?:TEMP|TMP)|%TEMP%)[^\r\n]*\.ps1\b"
    r"|\.ps1[^\r\n]*(?:GetTempPath\(\)|\$env:(?:TEMP|TMP)|%TEMP%))"
)

# Invariant 4: Hardcoded OneDrive / tenant paths
RE_HARDCODED_ONEDRIVE = re.compile(r"(?i)OneDrive\s*-\s*United\s+States\s+Air\s+Force")
RE_HARDCODED_SITE = re.compile(r"(?i)https://usaf\.dps\.mil/(?:sites|teams)/([A-Za-z0-9._-]+)")
PLACEHOLDER_SITE_SLUGS = {"example", "sample", "test-site", "your-site", "team-site", "demo"}

# Invariant 5: Dynamic code execution & TLS downgrade
RE_IEX = re.compile(r"(?i)(?:\bInvoke-Expression\b|(?<![\w$-])iex(?:\s+|\())")
RE_SB_CREATE = re.compile(r"(?i)\[ScriptBlock\]::Create\s*\(")
RE_TLS_DOWNGRADE = re.compile(
    r"(?i)(?:-bor\s*3072\b|SecurityProtocolType\]::(?:Ssl3|Tls11)\b)"
)

# Invariant 6: -WindowStyle Hidden & WScript.Shell .lnk creation
RE_HIDDEN_OR_LNK = re.compile(
    r"(?i)(?:-WindowStyle\s+Hidden\b|WScript\.Shell\b|CreateShortcut\s*\()"
)
RE_REVIEWER_COMMENT = re.compile(
    r"(?i)(?:security|reviewer|nipr|mde|benign|gui[- ]host|console)"
)

# Invariant 7: Unbounded WebClient & DefaultNetworkCredentials leak
RE_WEBCLIENT = re.compile(
    r"(?i)(?:New-Object\s+[^\r\n]*Net\.WebClient\b|\[(?:System\.)?Net\.WebClient\]::new\b)"
)
RE_DEFAULT_CREDS_TRUE = re.compile(r"(?i)UseDefaultCredentials\s*=\s*\$true\b")


def is_comment_line(line: str, suffix: str) -> bool:
    """Return True when a line is purely a comment."""
    stripped = line.lstrip()
    if not stripped:
        return True
    if suffix in {".ps1", ".psm1", ".psd1", ".py", ".sh", ".yml", ".yaml"}:
        return stripped.startswith("#")
    return False


def has_reviewer_comment_above(lines: list[str], idx: int, window: int = 8) -> bool:
    """Return True if a security-reviewer comment block appears within window lines above idx.

    Args:
        lines: list of source lines in the file.
        idx: zero-based line index of the target statement.
        window: maximum number of preceding comment lines to check.

    Returns:
        True if an authorized reviewer comment block was found, False otherwise.
    """
    start = max(0, idx - window)
    comment_lines = []
    for i in range(idx - 1, start - 1, -1):
        stripped = lines[i].lstrip()
        if not stripped:
            continue
        if stripped.startswith("#") or stripped.startswith("<#"):
            comment_lines.append(stripped)
        else:
            break
    if not comment_lines:
        return False
    block = " ".join(comment_lines)
    return bool(RE_REVIEWER_COMMENT.search(block))


def _is_test_file(rel_path: str) -> bool:
    """Return True if rel_path is a unit test file that may contain negative fixtures."""
    name = pathlib.PurePosixPath(rel_path).name.lower()
    return (
        name.endswith("_test.py")
        or name.startswith("test_")
        or name.endswith(".tests.ps1")
        or rel_path.startswith("tests/")
    )


def _check_ps_invariants(
    rel_path: str, suffix: str, idx: int, line: str, lines: list[str]
) -> list[str]:
    """Check PowerShell-specific NIPR invariants (2, 3, 5, 6, 7) on one line.

    Args:
        rel_path: relative path to the file being scanned.
        suffix: lower-case extension of the file.
        idx: zero-based line index.
        line: text of the line.
        lines: full list of lines in the file.

    Returns:
        List of violation finding strings.
    """
    findings: list[str] = []
    lineno = idx + 1
    if RE_INLINE_CS.search(line):
        findings.append(f"{rel_path}:{lineno}: NIPR-2 inline C# compilation (Add-Type/csc.exe) forbidden")
    if RE_TEMP_PS1.search(line):
        findings.append(f"{rel_path}:{lineno}: NIPR-3 .ps1 execution/staging in %TEMP% forbidden")
    if RE_IEX.search(line) or RE_SB_CREATE.search(line):
        findings.append(f"{rel_path}:{lineno}: NIPR-5 Invoke-Expression / [ScriptBlock]::Create forbidden")
    if RE_TLS_DOWNGRADE.search(line):
        findings.append(f"{rel_path}:{lineno}: NIPR-5 TLS 1.0/1.1 downgrade (-bor 3072 / Ssl3 / Tls11) forbidden")
    if suffix in {".ps1", ".psm1"} and RE_HIDDEN_OR_LNK.search(line):
        if not has_reviewer_comment_above(lines, idx):
            findings.append(
                f"{rel_path}:{lineno}: NIPR-6 -WindowStyle Hidden or WScript.Shell .lnk "
                "requires a security-reviewer comment block directly above"
            )
    if RE_WEBCLIENT.search(line):
        findings.append(f"{rel_path}:{lineno}: NIPR-7 unbounded WebClient forbidden (use bounded HttpWebRequest/TimeoutSec)")
    if RE_DEFAULT_CREDS_TRUE.search(line):
        findings.append(f"{rel_path}:{lineno}: NIPR-7 UseDefaultCredentials = $true forbidden on external targets")
    return findings


def scan_text(rel_path: str, text: str) -> list[str]:
    """Scan a file's text against all 7 DEC-NIPR invariants and return findings.

    Args:
        rel_path: relative path to the file being scanned.
        text: contents of the file as string.

    Returns:
        List of violation finding strings.
    """
    findings: list[str] = []
    suffix = pathlib.PurePosixPath(rel_path).suffix.lower()
    lines = text.splitlines()
    is_test = _is_test_file(rel_path)

    for idx, line in enumerate(lines):
        lineno = idx + 1
        if is_comment_line(line, suffix):
            continue
        # Invariant 1 applies everywhere (including tests & CI workflows)
        if RE_EXEC_BYPASS.search(line):
            findings.append(f"{rel_path}:{lineno}: NIPR-1 -ExecutionPolicy Bypass/Unrestricted forbidden")
        if is_test:
            continue
        if suffix in {".ps1", ".psm1", ".txt"} and RE_UNBLOCK.search(line):
            findings.append(f"{rel_path}:{lineno}: NIPR-1 Unblock-File / Zone.Identifier removal forbidden")
        # Invariant 4: hardcoded OneDrive / tenant paths
        if RE_HARDCODED_ONEDRIVE.search(line):
            findings.append(f"{rel_path}:{lineno}: NIPR-4 hardcoded 'OneDrive - United States Air Force' path forbidden")
        for match in RE_HARDCODED_SITE.finditer(line):
            slug = match.group(1).lower()
            if slug not in PLACEHOLDER_SITE_SLUGS:
                findings.append(f"{rel_path}:{lineno}: NIPR-4 hardcoded tenant site URL forbidden ({match.group(0)})")
        if suffix in {".ps1", ".psm1", ".psd1", ".txt"}:
            findings.extend(_check_ps_invariants(rel_path, suffix, idx, line, lines))
    return findings


def tracked_files(root: pathlib.Path) -> list[pathlib.Path]:
    """Return git-tracked files under root, falling back to rglob when not a git repo.

    Args:
        root: repository root Path.

    Returns:
        List of Path objects for tracked files.
    """
    res = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z"],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode == 0 and res.stdout:
        paths = []
        for entry in res.stdout.split("\0"):
            if entry:
                p = root / entry
                if p.is_file():
                    paths.append(p)
        return paths
    return [p for p in root.rglob("*") if p.is_file()]


def should_scan(rel_path: str) -> bool:
    """Return True if rel_path should be scanned by nipr_guard."""
    norm = rel_path.replace("\\", "/")
    if norm == SELF_REL:
        return False
    if any(norm.startswith(prefix) for prefix in SKIP_PREFIXES):
        return False
    return pathlib.PurePosixPath(norm).suffix.lower() in SCAN_SUFFIXES


def scan_repo(root: pathlib.Path, paths: list[str] | None = None) -> list[str]:
    """Scan all eligible files under root (or explicit paths) and return findings.

    Args:
        root: repository root directory Path.
        paths: optional list of string file paths to scan explicitly.

    Returns:
        List of violation finding strings across all scanned targets.
    """
    findings: list[str] = []
    if paths:
        targets = [pathlib.Path(p).resolve() for p in paths]
    else:
        targets = tracked_files(root)
    for path in targets:
        if not path.is_file():
            continue
        try:
            rel = path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            rel = path.name
        if not paths and not should_scan(rel):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        findings.extend(scan_text(rel, text))
    return findings


def _test_cases() -> list[tuple[str, str, str, str]]:
    """Build unit test cases for all 7 DEC-NIPR invariants.

    Returns:
        List of (label, relative_path, content, expected_code) tuples.
    """
    # Construct test strings dynamically so this file stays clean of literal triggers.
    ep_bad = "-Execution" + "Policy By" + "pass -File run.ps1"
    add_type_bad = "Add-Type -Member" + "Definition '[DllImport(\"gdi32.dll\")]'"
    add_type_ok = "Add-Type -AssemblyName System.Windows.Forms"
    temp_bad = "$p = Join-Path $env:" + "TEMP 'child.ps1'; & $p"
    od_bad = "$od = Join-Path $env:USERPROFILE ('OneDrive - United " + "States Air Force')"
    site_bad = "https://usaf.dps." + "mil/sites/my-real-wing"
    site_ok = "https://usaf.dps." + "mil/sites/<team-site>"
    iex_bad = "Invoke-" + "Expression $cmd"
    tls_bad = "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor " + "3072"
    hidden_no_comment = "Start-Process powershell.exe -ArgumentList '-WindowStyle " + "Hidden -File app.ps1'"
    hidden_with_comment = (
        "# NIPR security reviewer note: hides only the background console behind the visible WinForms GUI.\n"
        + hidden_no_comment
    )
    webclient_bad = "$wc = New-Object System.Net." + "WebClient"
    creds_bad = "$req.UseDefault" + "Credentials = $true"
    unblock_bad = "Unblock" + "-File -Path $scriptPath"
    zone_bad = "Remove-Item -Path ($scriptPath + ':Zone." + "Identifier') -Force"
    zone_read_ok = "Get-Item -Path $scriptPath -Stream 'Zone." + "Identifier' -ErrorAction SilentlyContinue"

    return [
        ("NIPR-1 catches Bypass in workflow", ".github/workflows/ci.yml", ep_bad, "NIPR-1"),
        ("NIPR-1 allows defensive env clear", "engine/run.ps1", "Remove-Item Env:PSExecutionPolicyPreference", ""),
        ("NIPR-1 catches Unblock-File in ps1", "engine/run.ps1", unblock_bad, "NIPR-1"),
        ("NIPR-1 catches Zone.Identifier removal", "engine/run.ps1", zone_bad, "NIPR-1"),
        ("NIPR-1 allows Zone.Identifier read-only check", "engine/run.ps1", zone_read_ok, ""),
        ("NIPR-1 skips Unblock-File in test file", "tests/Run-Tests.ps1", unblock_bad, ""),
        ("NIPR-2 catches Add-Type MemberDefinition", "engine/ui.ps1", add_type_bad, "NIPR-2"),
        ("NIPR-2 allows Add-Type AssemblyName", "engine/ui.ps1", add_type_ok, ""),
        ("NIPR-3 catches TEMP .ps1 execution", "engine/run.ps1", temp_bad, "NIPR-3"),
        ("NIPR-4 catches hardcoded OneDrive", "engine/base.ps1", od_bad, "NIPR-4"),
        ("NIPR-4 catches hardcoded site URL", "engine/base.ps1", site_bad, "NIPR-4"),
        ("NIPR-4 allows placeholder site URL", "engine/base.ps1", site_ok, ""),
        ("NIPR-5 catches Invoke-Expression", "engine/run.ps1", iex_bad, "NIPR-5"),
        ("NIPR-5 catches TLS -bor 3072", "engine/net.ps1", tls_bad, "NIPR-5"),
        ("NIPR-6 catches uncommented Hidden", "engine/run.ps1", hidden_no_comment, "NIPR-6"),
        ("NIPR-6 allows commented Hidden", "engine/run.ps1", hidden_with_comment, ""),
        ("NIPR-7 catches WebClient", "engine/net.ps1", webclient_bad, "NIPR-7"),
        ("NIPR-7 catches UseDefaultCredentials", "engine/net.ps1", creds_bad, "NIPR-7"),
    ]


def self_test() -> int:
    """Run unit tests for all 7 DEC-NIPR invariants and return 0 on pass, 1 on fail.

    Returns:
        Exit code 0 on pass, 1 on any test failure.
    """
    cases = _test_cases()
    failed = 0
    for label, rel, content, expect in cases:
        found = scan_text(rel, content)
        ok = (not found) if not expect else any(expect in line for line in found)
        failed += not ok
        print(("ok   " if ok else "FAIL ") + label + ("" if ok else f": {found}"))

    with tempfile.TemporaryDirectory() as tmp:
        p = pathlib.Path(tmp) / "sample.ps1"
        p.write_text("-Execution" + "Policy By" + "pass -File run.ps1\n", encoding="utf-8")
        found = scan_repo(pathlib.Path(tmp), [str(p)])
        ok = any("NIPR-1" in line for line in found)
        failed += not ok
        print(("ok   " if ok else "FAIL ") + "scan_repo scans explicit path")

    print("NIPR GUARD TEST PASS" if not failed else "NIPR GUARD TEST FAIL")
    return 1 if failed else 0


def main(argv: list[str] | None = None) -> int:
    """Parse CLI arguments and run either self-test or repository scan.

    Args:
        argv: optional CLI argument list string items.

    Returns:
        Exit code: 0 on pass or clean scan, 1 on failure or violations.
    """
    parser = argparse.ArgumentParser(description="IMMUTABLE NIPR code-safety guard (DEC-NIPR)")
    parser.add_argument("--test", action="store_true", help="run self-test")
    parser.add_argument("--root", type=pathlib.Path, default=ROOT, help="repository root to scan")
    parser.add_argument("paths", nargs="*", help="optional explicit file paths to scan")
    args = parser.parse_args(argv)
    if args.test:
        return self_test()
    findings = scan_repo(args.root, args.paths or None)
    for line in findings:
        print(line)
    print("NIPR GUARD PASS" if not findings else f"NIPR GUARD FAIL ({len(findings)} findings)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
