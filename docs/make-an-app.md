# How to make an app for RADE

What an application repository must hold so that RADE can test and deploy it. RADE owns the computer and the run; the app owns the product and the site ([engine.md](engine.md) "RADE and the app"). Working example: rhope-ops/90-161.Z. Small sample: [../schemas/examples/sample-manifest.json](../schemas/examples/sample-manifest.json) with [../tests/fixture-app](../tests/fixture-app).

## What the app repo holds

| # | Item | What it is | Example in rhope-ops/90-161.Z |
|---|---|---|---|
| 1 | Manifest | One JSON file: an `application` block and a list of `bundles`. Contract: [../schemas/rade-manifest.schema.json](../schemas/rade-manifest.schema.json). Default path `scripts/paste_bundles.json`. | `scripts/paste_bundles.json` |
| 2 | Step scripts | PowerShell files (Windows PowerShell 5.1) that a bundle writes to the computer and runs. They follow the step contract ([engine.md](engine.md) "Step contract"). | `scripts/gov/*.ps1` |
| 3 | Lock | The RADE commit and every engine file with its SHA-256 ([engine.md](engine.md) "How an app gets the engine"). Copy it from a RADE release (`rade-engine.lock.json`). | `scripts/rade.lock.json` |
| 4 | Build script | Downloads the locked engine files, checks each SHA-256 and runs `engine/rade_build.py --app-root <repo>`. Copy the example; it uses the Python standard library only. | `scripts/build_paste_bundles.py` |
| 5 | Built bundle | The engine's output: one `.ps1` text for each bundle and, from engine-v21, its stored hash `<bundle>.ps1.sha256.json` (the RADE page compares with it) and, from engine-v34, the same text as `<bundle>.txt` (the file a link opens), all committed to the repo. Never edit them by hand. | `scripts/gov/paste/*.ps1`, `*.ps1.sha256.json`, `*.txt` |
| 6 | `go.md` on main | The task page. The window reads it to tell the user that a newer round exists. | `go.md` |
| 7 | `rade-release.json` on main | The current version of each app in the manifest, for the newer-version notice in a deploy. | `rade-release.json` |

## The manifest

- `application` (all required): `name` (shown in the window), `folder` (the app's folder under `OneDrive\RADE`), `prefix` (starts file names and the e-mail subject), `repo` (`owner/name` on GitHub), `home` (the app's page), `own` (file patterns the app owns; clean-up may recycle only these), `knownDirs`.
- `application.displayName` (optional, engine-v42): the name a person sees for your installed app, for example `90-161.Z - Kanon` (letters, digits, spaces, `.`, `_` and `-`; at most 60 characters). It is in the shortcut tooltip and the Done line ("It opens RADE for <displayName>"); the shortcut name and the Maintenance card use `productName` (engine-v46). The app name stays the install key, the folder name and the Uninstall confirm text.
- `application.productName` (optional, engine-v45; name spot L3, engine-v46): the product's own name, for example `Kanon`. The application row shows it in capitals ("KANON"); under the line the window shows `<name> • <subtitle>`. It names the shortcut ("Kanon", no version) and the Maintenance card ("Kanon • 0.1.0"). Without it, the app name.
- `application.subtitle` (optional, engine-v43): the line under the word in the RADE window's logo block, for example `Publications and Forms Management` (at most 80 characters; no quotes, no `$`). Without it, the window shows the word only.
- `application.logo` (optional): the path in your repo of your app's logo, a PNG (128 px square is enough for the window; give 256 px for a sharp shortcut icon: from engine-v42 RADE makes the icon of your app's shortcut from it at 16, 32, 48 and 256 px). Once the user chooses your app, the window shows it at 64 px in the RADE logo's place, with your app's word beside it (engine-v46). The build stops if the file is missing or is not a PNG. Until the run-time logo (docs/specs/run-time-logo.md) is built, the PNG travels in the bundle as text (the Administrator, 2026-11-18).
- Each bundle (required: `out`, `round`, `title`, `files`, `steps`, `collect`): one round. `files` are written to the computer, `steps` run in order, `collect` names the result files for the e-mail draft. A collect name never matches a script file: end a pattern with the result file's own extension (`*.pdf`, not `feedback-*`); the build fails one that can match a script extension (docs/engine.md "Results"). Optional: `app`, `fetch`, `cleanup`, `apps`, `release`.
- Each entry of `apps` (required: `name`, `summary`, `steps`): optional `mode`, `version` (required for a deploy), `marker`, `start` and `backup` (from engine-v30: the titles of the app's own lists that the Maintenance tool Back up saves, plain names; RADE never finds lists itself, and with none named Back up says so and saves nothing; from engine-v31 a title may hold parentheses) and `restore` (from engine-v31; needs `backup`): `testSites`, the site names (the part after the site prefix) where the Maintenance tool Restore may write, and optional `pause`: `list`, `title`, `field` and `on`, the app's pause-switch row that Restore sets to `on` before it writes and puts back after; the app's flows read it and skip while it is on. Restore puts back missing rows only (docs/engine.md "Maintenance run types"). From engine-v40, `uninstall` (needs mode deploy and `restore`): the names of the app's own Uninstall steps, in run order. They are steps of the bundle that are not in the app's `steps` (a script that does not read `RADE_MODE` would install again), of kind script or guide, with no `after` or `ask`. Each script gets `RADE_MODE=uninstall` and `RADE_MADE` (a JSON file with the made list) and removes the app's own lists, flows and settings; it prints `SKIP` when there is nothing to remove, so a second run is safe. Flows in Power Automate are a hand step. Uninstall runs only on a test site, after a fresh backup and the typed app name. `start` is a script in the app's local install folder, as a path with `/` between folders (for example `App/Start-App.ps1`, plain names only, ending `.ps1`; the schema checks it). After the checks pass, the Ready screen of an installed app shows a Start button that runs it in its own `powershell.exe` process, with the folder as its working folder, and then RADE closes. Nothing is downloaded: the script is a bundle file or one an install step puts there. Without `start` there is no button. The button is the main one when the installed version is the bundle's version; when the bundle is newer, Install stays the main one.
- Each step (required: `name`, `dir`, `file`): a script step, or `kind: guide` for a step the user does by hand. `needs` names the RADE checks the step depends on.
- Hand steps (R31): show only the buttons that lead to a different result (`hide`), let a step that only asks questions show them at once (`answersOnly`, with `failOn` for an answer that means a failure), and ask a question only after the answer it depends on (`showIf`): [engine.md "Step contract"](engine.md#step-contract). A script step can say what it does now (`doing`, and `NOW <text>` lines).
- Text lengths: the window has a limit for each text it shows (name, version, summary, step name, step `title`, note, guide line, the number of numbered guide lines, `doneText`, `doing`, `help`): [window-design.md "Text lengths"](window-design.md#text-lengths). The build prints a WARNING line for a longer text.
- The schema is the authority for every field. Check a manifest with `python3 scripts/check_manifest.py <file>` in a RADE checkout.

## Steps

1. Write the manifest and the step scripts. Start from the sample manifest.
2. Copy the lock and the build script from the example and set the lock from the newest RADE release.
3. Run the build script. It writes the bundle; commit the bundle with the manifest.
4. Test the bundle in the app repo: run it in PowerShell 7 text mode with the users folder swapped for a temporary one (the example's `tests/run.sh` shows how). Engine behavior is tested in RADE ([../tests/engine_test.sh](../tests/engine_test.sh)); an app tests only its own bundle and files.
5. Ask the Administrator to add the app to [../apps.json](../apps.json) (`repo` and `manifest`). The RADE page then offers the last bundle in the manifest.

## Adopt the UI standard

UI standard v1 ([ui-standard.md](ui-standard.md); the Administrator, 2026-11-20) holds for every window an app shows, also its own (for example a step's own form). For a bundle the engine does it all: a lock on an engine release from engine-v29 is enough. For an app's own window:

1. Copy `engine/rade_ui.ps1` of the locked commit into the window as it is (the token block comes with it); build every button with `$ui.Btn` (`'action'` or `'compact'`) and every link with `$ui.LinkBtn`, and take colors only from `$ui.C` and sizes only from `$ui.Z`.
2. Put the primary button last in the action row, one at most, at most 3 others; Back is a compact "Back (Esc)" at the left end.
3. Hook `$ui.Recolor` on the form's `SystemColorsChanged`, as the engine does (engine/ps/window/ui-runner.ps1), so a contrast theme takes effect while the window is open.
4. Run `$ui.Check` on each card in a test round and fix every `LAYOUT` line; set `RADE_INVENTORY` to keep a JSON line per control.
5. Set `"ui": "v1"` for the app in [../apps.json](../apps.json) when its windows follow the standard (the Administrator's change, as in step 5 above).

## Rules

- A RADE session never edits an app repo, and an app session never edits RADE: an engine change is a RADE pull request, then a release, then a lock change in the app.
- No app data, site address, person or ID in a manifest, a script or a result that leaves the computer ([engine.md](engine.md) "Guardrails").
- RADE may know a platform (SharePoint, Power Automate, Word, Outlook), never an app's objects. If an app needs a new check, propose it for RADE; do not build it into a step that other apps then copy.
