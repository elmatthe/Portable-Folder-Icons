# Verification Gate

The manual for this project's optional verification gate: a deterministic test runner that agents start and supervise, then inspect its evidence. It needs no AI inference. Only projects created with the gate have this folder. The general rules for choosing and reporting checks are in `.ai/VERIFICATION.md`; this file adds what is specific to the gate. Load it when running the gate, adding tests to it or reporting its results.

**Status: legacy.** The gate is optional and off by default. Its runners and adapters were written before the current workspace layout, are no longer developed, and have not been validated again since. Use a gate result as supporting evidence, and check that the gate really covers what you changed. Everything the gate owns lives in this folder, `files/dev-work/verification-gate/`: its runner, configuration, helpers, tooling, fixtures, tests and adapter files. Nothing of the gate belongs in the repository root, `src/`, the root `tests/` or `scripts/`.

The gate is an addition to the standard layout, not a replacement. Application code lives in `src/` and ordinary tests in the root `tests/`, as in every project (`.ai/LAYOUT.md`). The gate runs only the tests in this folder's `tests/`. Its runners were written before the standard layout, so know what they cover:

- **Python:** the syntax check covers `src/` through `syntax_paths` in `verification.json`. Tests here get `scripts/` on the import path, not `src/`: run the application as a subprocess, or add `src/` to `sys.path` at the top of the test.
- **Node:** the static checks cover `scripts/` and this folder, not `src/`.
- **Generic:** it runs the commands in `checks.tsv`, wherever they point.

Feature Map test lines for gate checks use paths relative to this folder, and a `command` check is named by its `c-NNNN` ID below. Where this manual says `scripts/` holds application code, read it as the folder these runners check by themselves.

## Commands

The gate lives in `files/dev-work/verification-gate/`. `G` below means that folder.

| Profile | Run it | First-time tools |
|---|---|---|
| `python-cli`, `python-desktop` | `python G/verify.py` | `python G/verify.py --setup --yes` |
| `node-typescript`, `office-scripts` | `node G/verify.mjs --mode focused --select <id>` | `node G/verify.mjs --setup` |
| `generic` on Windows | `powershell -NoProfile -ExecutionPolicy Bypass -File G/verify.ps1 --mode focused --select <id>` | none |
| `generic` on macOS | `sh G/verify.sh --mode focused --select <id>` | none |

Every runner takes `--mode focused|changed|full`, `--select <id>`, `--platform-scope windows|macos|both`, `--status` and `--help`. `verify.py` takes `--mode dev|focused|changed|full` with `dev` as its default, plus `--allow-heavy`, `--setup --yes` and `--override-resource-limits <reason>`.

**For now, `verify.mjs`, `verify.ps1` and `verify.sh` still default to `full` and have none of the limits below,** so give them an explicit narrow selection during development. Their safety parity is a later phase.

| Mode | Use it for | What a PASS means |
|---|---|---|
| `dev` | The light default while developing | Static checks and fast tests passed. Full acceptance not established |
| `focused` | The test or check you are working on | Those checks passed. Full acceptance not established |
| `changed` | Tests mapped to changed files; broadens when impact is unclear | That selection passed. Full acceptance not established |
| `full` | Phase ends, plan completion, integration, release | Every required applicable check passed for the stated platform scope |

`--setup` lists what it would install; only `--setup --yes` installs, and a normal run never does. `--status` says whether the last full run still matches the working tree, and changes nothing.

## Execution Levels

| Level | Use it for | Commands | What it does |
|---|---|---|---|
| L1 Orientation | Understanding state | Documents, `git status`, `verify --status` | Reads only. Starts no test or app and creates no run folder |
| L2 Development | Feedback while working | `verify`, `--mode focused --select <id>`, `--mode changed` | Static checks and fast tests. Never browsers, GUIs, native input, media, installs or anything marked heavy |
| L3 Full | Checkpoints the user or an authorized plan asks for | `--mode full`, or `--allow-heavy` on a narrower run | Everything in scope, holding the heavy slot |

**Orientation is read-only: no tests, gates, apps or installs.** Run focused checks while developing. Start L3 only when specifically authorized, after checking for competing heavy work and memory pressure. If the user reports resource exhaustion, stop at once, inspect read-only, and do not resume until they say the machine is fine.

What L2 leaves out is `NOT RUN`, never PASS: tests marked `gui`, `native`, `native_windows`, `native_macos`, `qt`, `media`, `slow` or `heavy`, browser tests, and anything in `tiers.dev.exclude_paths` or `tiers.dev.exclude_markers`. A configured command needs `"tier": "dev"` to run at L2. With no tier it counts as `full`, because the runner cannot know what it does. L2 relies on this classification, so mark heavy tests: an unmarked one would still run. Children see `VERIFY_LEVEL`, and the gate's GUI and media helpers refuse at `dev`. A PASS speaks only for its scope. It does not erase a BLOCKED or NOT RUN requirement outside that scope, and it describes the source it ran against, not a later change. Report skipped and blocked checks as exactly that, and keep the evidence.

## Resource Limits

For `verify.py`. Raise a starting value under `resources` in `verification.json`, or for one machine with a `VERIFY_<NAME>` variable. Each run's `results.json` and `logs/resources.jsonl` record the limits in force, measurements and actions.

| Protection | Starting value | What it really is |
|---|---|---|
| Memory and process caps on each check's tree | 4096 MiB, 64 processes | Enforced by a Windows job, where the OS accepts it. Elsewhere, unavailable |
| Priority of each check's tree | Below normal | Enforced by a Windows job, otherwise inherited |
| Run budget, check timeout | 600 s and 300 s at L2, 3600 s and 900 s at L3 | Enforced. What is left is `NOT RUN`, and the run cannot pass |
| Preflight | Under 75% memory, at least 4 GB commit headroom | Enforced at the start of a run. Unknown memory refuses L3 |
| Pressure watchdog | 90% for 3 samples, 5 s apart | Advisory: sampled, so a fast spike can outrun it. Its stop acts on the owned tree only |
| Heavy slot | One heavy run per user account | Cooperative: it sees only gates that use it |
| Log cap | 100 MiB, diagnostics from the last 64 KiB | Polled: a log can pass the cap briefly |
| Input hashing | 512 MiB; files over 64 MiB by size and time | Over budget, freshness is unknown and a full run cannot pass |

`--override-resource-limits "<reason>"` starts despite the preflight. It needs the user's approval: agents may propose it, not grant it. The reason is recorded, and it never skips the slot or the watchdog. The slot is `heavy.lock` in `%LOCALAPPDATA%\vibe-verify\` (`~/Library/Caches/vibe-verify/` on macOS), or `VERIFY_SLOT_DIR` in tests. It is the one thing a gate writes outside its project, a named exception holding minimal ownership metadata and no project data. A held slot refuses at once, with no waiting. It is reclaimed only when its owner is proven gone: an expired budget proves nothing, and doubt fails closed. A gate may not start another gate beyond `max_nesting` (default 0), and a permitted descendant shares its ancestor's slot.

## Exit Codes and Statuses

Exit `0` PASS, `1` FAIL, `2` BLOCKED, `130` interrupted. Raw tool exits stay in the evidence; do not read them as gate results.

| Status | Meaning |
|---|---|
| PASS | Required applicable checks really ran and passed in this scope |
| FAIL | A required assertion or repository contract was violated |
| BLOCKED | A prerequisite or infrastructure problem prevents establishing the result |
| NOT RUN | Not executed in this run, such as another platform |
| NOT APPLICABLE | Outside this project's behaviour, with a stated reason |

Lifecycle (`COMPLETED`, `INTERRUPTED`, or `RUNNING` after a hard kill) is separate from the result. An incomplete or interrupted run is never PASS. A missing environment is BLOCKED; a healthy environment where the application misbehaves is FAIL. If the cause is unknown, say so.

A fresh scaffold is correctly `BLOCKED: application verification not configured`. Do not add fake tests or empty requirements to turn it green.

## Profiles and Adapters

Keep the primary profile, the application's stack and its platforms separate. A web application in Python is `python-cli` plus `web-playwright`, not a new profile.

| Profile | Deterministic checks |
|---|---|
| `python-cli` | Real subprocess runs: exit codes, output, files, state, failure paths. Tests written with the standard library's `unittest` need nothing installed: with `scripts/` on `PYTHONPATH`, as the gate sets it, `python -B -m unittest discover -s G/tests -p "test_x.py"` runs one file directly. The gate's pytest collects them too, so map them as `pytest`, not a `command` check. Use pytest's own features where they genuinely help, such as the markers L2 relies on |
| `python-desktop` | The above, plus Tk or Qt widget tests and separately labelled native window tests |
| `node-typescript` | Type checks, `node:test` or the project's runner, subprocess tests. No browser unless the adapter is added |
| `office-scripts` | Type checks and pure-logic tests. These never prove Excel behaviour; host acceptance stays separate |
| `generic` | The project's own commands in `checks.tsv`, with no Python or Node required. None configured means BLOCKED |

| Adapter | Tool | Status |
|---|---|---|
| `web-playwright` | Playwright Test in JS/TS, Chromium by default, real browser journeys | Python and Node profiles |
| `media` | ffmpeg and ffprobe against real files; provision them under `G/cache/ffmpeg` or `VERIFY_FFMPEG_DIR` | Python and Node profiles |
| `qt` | pytest-qt with the application's binding | `python-desktop` |
| `native-windows` | Standard-library window checks and real keyboard input to the verified foreground window | `python-desktop` on Windows |
| `native-macos` | Plan only until proven on a Mac; see `G/NATIVE-MACOS.md` | `python-desktop` on macOS |
| `office-host` | Real Excel host; BLOCKED until configured; see `G/OFFICE-HOST.md` | `office-scripts` |

Generic projects compose other tools through `checks.tsv`. Add a dependency only with a stated purpose, a pinned version and a reason existing tools are not enough. Pilot it first: a passing case, a deliberate failure, contained evidence, and a repeat run with no agent driving each step.

## Layout

| Path under `G/` | Holds | Git |
|---|---|---|
| `verify.*`, `helpers/`, `pytest.ini`, `playwright.config.mjs` | Runner and test plumbing | Tracked |
| `verification.json`, or `checks.tsv` for Generic | Profile, adapters, platforms, timeouts, commands as argument arrays | Tracked |
| `coverage.json`, or `coverage.tsv` for Generic | Required functionality mapped to tests | Tracked |
| `tests/`, `fixtures/`, `baselines/` | Tests, small real inputs, approved visual baselines | Tracked |
| `tooling/`, `package.json`, lockfiles | Test-only dependencies | Tracked |
| `cache/`, `node_modules/` | Rebuildable environments and tools | Ignored |
| `outputs/<run>/` | Everything a run produces | Ignored, disposable |

`scripts/` is for what the application needs at runtime. Test tools and verifiers never go there. Deleting all of `outputs/` must never break a later run: nothing required lives there, and a missing fixture is restored from version control, not from an old run.

Run IDs are `YYYYMMDDTHHMMSSZ-xxxxxx`. Each run holds `summary.md`, `results.json`, `coverage-report.md`, `failures.md`, and `logs/`, `reports/`, `artifacts/` and `temp/` when used. Children inherit `VERIFY_RUN_DIR`, `VERIFY_ARTIFACTS_DIR`, `VERIFY_TEMP_DIR`, `VERIFY_FIXTURES_DIR`, `VERIFY_GATE_DIR` and `VERIFY_PROJECT_ROOT`; send every generated file there. On Windows a run needs about 80 characters of path left below its folder, so keep project paths short; the gate reports BLOCKED otherwise.

## Feature Map and Functional Inventory

`md-instructions/Feature-Map.md` is the permanent register agents maintain. The map itself holds the schema and lifecycle, so this section does not repeat them. Three results stay separate: a passing test or check proves only itself; a feature's `Verification: PASS` proves the tests its entry lists, from a direct command or any gate mode, for the source, scope and platform its evidence names; and project acceptance needs a completed `--mode full` run and its review, recorded in `Handoff.md`.

In a gate project, map test lines with the gate's adapter names (`pytest`, `playwright`, `node-test`, `command`) and paths relative to this folder. A `command` check is named `c-NNNN`: lowercase, because the Python and Node runners reject capitals, numbered like features and never reused. It is the check's `id` in `verification.json` (`checks.tsv` for Generic) and counts as one test however many cases it runs. Python tests written with `unittest` are collected by the gate's pytest, so map them as `pytest` lines, never as a `command`. In Evidence, the scope is `gate` and the mode, such as `gate focused`, and what ran is the run ID.

The runners do not read the map yet. Until they do, `coverage.json` (`coverage.tsv` for Generic) is what the gate enforces, so reuse each feature ID as its requirement ID and change both, with any fixtures, in the same task. Recording evidence in the map also changes the gate's input digest, so `--status` reads the last full run as stale afterwards. That is a known limit, and no source changed. `coverage.json` lists required behaviour, not code:

```json
{"schema_version": 1, "requirements": [{
  "id": "EXPORT-001",
  "description": "Export valid records to a chosen file",
  "platforms": ["windows", "macos"], "paths": ["scripts/export.py"],
  "scenarios": ["valid", "bad-input", "existing-file"],
  "tests": [
    {"adapter": "pytest", "id": "tests/test_export.py::test_valid", "scenario": "valid"},
    {"adapter": "pytest", "id": "tests/test_export.py::test_bad_input", "scenario": "bad-input"},
    {"adapter": "playwright", "id": "tests/export.spec.mjs::overwrite is confirmed", "project": "chromium", "scenario": "existing-file"}
  ]
}]}
```

- Register controls, states, workflows, outputs and recovery: buttons, menus, inputs, enabled and disabled states, messages and dialogs, keyboard focus, resizing and overflow, startup and shutdown, persistence, import and export, calculations and complete journeys. One journey may satisfy several items if it asserts each outcome.
- `adapter` is `pytest`, `playwright`, `node-test` or `command`. A `command` test's `id` is a check's `id` in `verification.json`, named as the map says. An ID without a parameter covers every parameter instance, and a pytest class ID every test in it. `paths` drives `--mode changed`.
- Three separate results: **mapping** (each required item has real tests), **executed satisfaction** (those tests ran and passed in this run) and **code coverage** (optional, never a substitute). A skip, xfail or retry-recovered pass does not satisfy a requirement.
- A not-applicable item needs `"applicability": {"status": "not-applicable", "reason": "..."}`.
- An exception needs `"exception": {"id", "rationale", "approved_by", "approval_ref", "platforms", "modes", "expires"}`. **Agents may propose an exception; only the user can approve one.** An ordinary bug or an unavailable tool is not an exception.
- A skip that is correct on this OS goes in `allowed_skips` in `verification.json`, with its reason and platforms.

Build tests this way: read the code and run the application to list what a user actually does; register those items; write one real test for each outcome; break the behaviour on purpose to see the test fail; then wire it into the gate. When a test later fails, classify it before changing anything: **product defect** (fix the code), **test drift** (update the test, keeping its intent) or **harness gap** (fix the gate). Never rewrite an expectation just to get a pass.

## Writing Tests That Prove Something

- Assert the resulting state, file, calculation, message, navigation or recovery. A click, a launch or a screenshot proves nothing by itself.
- Calculate expected values independently of the code under test, and include boundary cases.
- Use tiny, synthetic, license-safe fixtures that are real for the workflow: a text file renamed `.m4b` is not an audiobook. Keep a recipe or manifest with them. Mocks may add failure paths but must not replace a required real path.
- Check media by meaning (streams, chapters, durations, decoding, content), with tolerances you can justify.
- Keep tests offline and isolated: explicit data roots, never real accounts, signed-in browser profiles or production services.
- Mark `gui`, `native`, `media`, `qt` and `slow` tests. A category never excuses a required check from a full run.
- **Browser:** role, label or test-ID selectors with outcome assertions, and a server the run owns; an occupied port is BLOCKED, never reused. Baselines change only by explicit review.
- **Tk or Qt:** widget tests prove widget logic only. Native focus, input and startup are separate tests, marked `native`.

## Platforms

Windows evidence is not macOS evidence. Portable tests run wherever they can, but each run proves only the machine it ran on. A Windows checkpoint reads `PASS — full Windows checkpoint; macOS native acceptance NOT RUN`, which supports that checkpoint and nothing wider. Declaring both platforms without narrowing the scope leaves the run BLOCKED until both are done. `--platform-scope` narrows one run visibly; never narrow it to hide a blocker. Git Bash on Windows is not macOS.

## Safety

The runner stops only processes it started, applies timeouts to every check and helper process, and records anything still running when a check ends. Never kill processes by name or attach to an application the user already has open. Do not automate unlocking, change machine settings, or install tools machine-wide. Native input tests need an unlocked, attended desktop and briefly take keyboard focus, so run them serially.

Evidence stays local and is never uploaded automatically. Capture only the window under test. Text redaction does not sanitize images or traces, so use synthetic data from the start.

## After a Full Run

After every **completed** full run, including FAIL and BLOCKED, inspect the evidence and write `agent-review.md` in that run's folder. The runner never writes it. It is not approval.

```markdown
# Verification Review: <run-id>

Project, version, branch, HEAD and input digest. Machine and OS. Timestamp and exact run path.

## Scope and Results
Mode, requested platforms, checks run, pass/fail/blocked/skip/exception counts, retries, interruptions.

## Coverage
Mapping and executed satisfaction totals, exclusions. UI or browser results. Real file and media results.

## Evidence
Links relative to the run folder: screenshots, traces, outputs, logs.

## Findings
Critical / High / Medium / Low / Suggestions. Say so when a level is empty. Each defect: expected versus actual, evidence or test ID, affected files, fix.

## Facts and Interpretation
What the evidence shows, kept separate from what you infer. Remaining risks and unverified behaviour.

## Recommendation
Readiness for the next checkpoint. Mechanical result, this review, independent review, native platform acceptance and user approval are separate gates.
```

Record the run ID, tested source, scope and result in `Handoff.md` under **Last verification**. Before deleting evidence a milestone relies on, keep a reviewed summary somewhere permanent.

## Distribution

`.gitattributes` marks development material `export-ignore`, so `git archive HEAD` produces an end-user package without the gate, docs or test tools, and a clone keeps everything. `.gitignore` does not control other ZIP tools. A runtime package must launch without anything from `files/dev-work/`.

## Attribution

The test-building method and failure triage above are written in our own words, adapted from the MIT-licensed [pstack](https://github.com/cursor/plugins/tree/main/pstack) `create-verification-skill` and `maintain-verification-skill` by Lauren Tan. The GUI availability check in `verify.py` follows the approach of CPython's `test.support`. No upstream workflow is installed or required.

## Portable Folder Icons adaptation

Established 2026-11-16 (Phase 0). The runner, this manual's sections above, and the table formats are the workspace's `generic` template (snapshot 2026-11-04); the template itself was not modified. Project-specific changes are marked `PFI:` in `verify.ps1`:

1. **Status index** in `outputs/verify-state.json`, so every generated file stays under the ignored `outputs/`.
2. **`scripts/verify.ps1` is allowed** in `scripts/`. It predates the gate, is the verifier named in `config.toml`, and the gate runs it as check `c-0006` instead of replacing it.
3. **Check exit codes:** `0` PASS, `1` FAIL, `2` BLOCKED, `3` BLOCKED (`BLOCKED_BY_ENDPOINT_SECURITY`), `4` NOT RUN (explicit opt-in absent), `5` FAIL labelled "test process crashed" (a crash is not an assertion verdict). None of 2–5 can produce a PASS.

### Run it

From the repository root, in Windows PowerShell 5.1:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\verify.ps1 --mode full
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\verify.ps1 --mode focused --select c-0003
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\verify.ps1 --status
```

| Check | Required | What it proves | Notes |
|---|---|---|---|
| `c-0001` | yes | Deterministic PowerShell suite (`files/tests/Invoke-Tests.ps1`) | Called with no native flag, so it exercises the suite's default: the C# harness launch is withheld (that result belongs to `c-0002`). FAIL if a harness launch is recorded without authorization |
| `c-0002` | yes | Compiled C# broker harness, x64 and x86 (`files/tests/Invoke-SelectionBrokerTests.ps1`) | Default: builds or reuses the cached harness and launches nothing, so `BLOCKED_BY_ENDPOINT_SECURITY` (withheld), or FAIL if it does not build. With the opt-in: PASS needs runner exit 0 and a PASS line with assertions for both x64 and x86 |
| `c-0003` | yes | Phase 0 diagnostics (`tests/Invoke-Phase0Diagnostics.ps1`): chooser plan/ordering/dispatch identity, Reset persisted state and fresh-process Shell resolution, Repair boundary and isolated concurrency, ordinary Uninstall | `[FINDING]` lines characterize defects and never change the exit code |
| `c-0004` | no | Installed x64 COM dispatch on fresh fixtures (`files/tests/Invoke-InstalledSelectionBrokerTests.ps1`) | Opt-in only: uses the live installation |
| `c-0005` | yes | Exactly ten tracked colour ICOs; no personal ICO staged | Untracked personal ICOs are listed, not failed |
| `c-0006` | yes | `scripts/verify.ps1`: suite again, required files, root layout, parsing, every ICO, docs (including the AGENTS.md housekeeping rules), security scan, `git diff --check` | Called with no native flag, like `c-0001`. `[FAIL]` lines labelled BASELINE (`known-baseline.tsv`) or NEW. No BASELINE rows remain (B-001/B-002 retired 2026-11-16) |
| `c-0007` | yes | Native verification infrastructure (`tests/Test-NativeHarnessInfrastructure.ps1`): outcome classification, real process capture, `c-0002`/`c-0004` wrappers end to end with stub runners, harness build cache in a disposable root, blocked-binary launch guard, default launch authorization of every entrypoint | Launches no compiled harness; only `csc.exe` and inbox `powershell.exe` run |
| `c-0008` | yes | Output housekeeping safeguards (`tests/Test-GateOutputHousekeeping.ps1`) for `helpers/Remove-GateOutputs.ps1` | Uses a disposable fake outputs tree; its dry run against the real `outputs/` must delete nothing |

Opt-ins are environment variables, set deliberately for one run and never by default:

- `PFI_GATE_NATIVE_HARNESS=allow` — launch the compiled C# harness. Only after an authorized security review (below).
- `PFI_GATE_INSTALLED_COM=allow` — run `c-0004` against the live installation (also needs the harness opt-in).
- `PFI_GATE_NATIVE_RECLASSIFIED=<sha256>[,<sha256>]` — only when the security owner has reclassified that exact blocked build. Without it, a build whose most recent launch was blocked is not launched again (see "Harness build cache").

Every entrypoint withholds compiled-harness launches unless explicitly authorized for that run: the gate wrappers and both runners (`files/tests/Invoke-SelectionBrokerTests.ps1`, `Invoke-InstalledSelectionBrokerTests.ps1`) need the opt-ins above; `scripts/verify.ps1` and `files/tests/Invoke-Tests.ps1` launch only with `-AllowNativeHarness` or `PFI_GATE_NATIVE_HARNESS=allow` (`-SkipNativeHarness` still forces the withhold). Without authorization the harness is built or reused, its launch is reported as `BLOCKED_BY_ENDPOINT_SECURITY (withheld, not launched)`, and the verifier ends `RESULT: BLOCKED`, never PASS (changed 2026-11-16; earlier, direct runs launched by default).

### Results that are not failures

- **BLOCKED_BY_ENDPOINT_SECURITY.** On 2026-11-16 WatchGuard Endpoint Security blocked the freshly compiled, unsigned `SelectionBrokerHarness.x64.exe` ("Untrusted program blocked"). The gate therefore does not compile-and-launch it unless opted in, and reports the harness as BLOCKED, never PASS. If a launch is attempted and Windows returns `Access is denied`, the suite and runners classify it the same way and keep the original exit code and message in the log. Never disable or bypass endpoint security, rename or relocate binaries, or re-run a known-blocked file to get a result.
- **BASELINE failures** are failures that already existed when the gate was established (`known-baseline.tsv`). They still fail their check; the label only separates them from NEW failures. Remove the row when it is fixed.
- **NOT RUN** marks an opt-in check that was not requested. A required NOT RUN makes a full run BLOCKED.

### Security review evidence for the C# harness

What a reviewer needs before `PFI_GATE_NATIVE_HARNESS=allow` is used:

- **Purpose:** a test-only console program that loads the project's selection broker assembly in-process and calls its COM interfaces with synthetic data: registration-derived `IInitializeCommand` contracts, more than 100 ordered selection occurrences, invalid identities and the native `VARIANT` layout. It writes nothing outside its own folder and opens no network connection.
- **Source:** `files/tests/SelectionBrokerHarness.cs`, compiled by the inbox `%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` (and `Framework` for x86) against `scripts/Windows/SelectionHandler/PortableFolderIcons.SelectionBroker.<x64|x86>.exe`, once per set of build inputs (see "Harness build cache").
- **Binaries to classify now (2026-11-16, never launched):** `cache/native-harness/x64/a8388e73a05fc596/SelectionBrokerHarness.x64.exe`, 10,752 bytes, SHA-256 `0a71577b45057f29cf7b200b96d30af0f7f0a402e72a119954c368d40108b910`; `cache/native-harness/x86/2f6ce4c60045bc1d/SelectionBrokerHarness.x86.exe`, SHA-256 `4f589ac4444370913cdc9707faf897b2a99d5444e949e6caa0f39a737c97935e`. They stay byte-stable while their inputs are unchanged, so a hash classification now persists across runs.
- **Earlier binaries (deleted in the post-checkpoint housekeeping; facts kept here):** `35482483f917106c82d485a0e360aa1846407adcbec162f52b19dd1103fd4bf5` (built 2026-11-16T15:16Z, MVID `ff6e5a4c…`; blocked, later classified trusted, never re-run) and `b2eaad08a8273255449098a2f49794b8fc9f13a8ab4fc46f29137758eb15efa6` (built 16:14Z, MVID `eb830435…`; blocked), both 10,752 bytes, x64. A read-only byte comparison found `35482483…` differs from the cached x64 build only in the PE TimeDateStamp (offset 0x88) and the MVID (offset 0x20F0), i.e. it was built from the same inputs. The user decided not to adopt it into the cache; it was deleted as a superseded build product.
- **Not affected so far:** the installed and repository broker executables started normally on 2026-11-16 (direct launch without `-Embedding` returns 64 by design). COM activation of the installed broker by Explorer is a separate, unproven path.

### Evidence layout

`outputs/<run-id>/` per the template (`summary.md`, `results.json`, `coverage-report.md`, `failures.md`, `logs/`, `artifacts/`, `temp/`). Fixtures live in that run's `temp/`. Nothing in `outputs/` is required by a later run. The Phase 0 snapshot, diagnostics and runs were removed after the checkpoint commit; their results are recorded in this file, the plan and Handoff.

### Output retention (housekeeping)

`outputs/` is temporary evidence storage, not an archive. The policy is "Repository development artifact housekeeping" in the root `AGENTS.md`; this is how it applies to the gate.

| Permanent (tracked) | Temporary (ignored; remove once recorded) |
|---|---|
| `verify.ps1`, `helpers/`, `checks.tsv`, `coverage.tsv`, `known-baseline.tsv`, `tests/`, maintained fixtures, `GATE.md`, `MANUAL-GATES.md` | Everything under `outputs/`: per-run logs, artifacts, disposable fixtures, diagnostics, screenshots and traces, temporary reports, earlier runs |

`cache/` is ignored but not routinely disposable: keep `cache/native-harness/` while it serves reproducible verification or an endpoint-security classification.

After each completed verification cycle or phase, record the results (Handoff **Last verification**, the essentials of `agent-review.md`), then clean:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\helpers\Remove-GateOutputs.ps1          # dry run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File files\dev-work\verification-gate\helpers\Remove-GateOutputs.ps1 -Apply   # delete
```

`-Name a,b` limits it to named folders. To keep evidence, put a `RETAIN.md` in its folder (why it is kept, when it can go) and mention it in Handoff. The helper removes only immediate child folders of this repository's ignored `outputs/`, and never loose files (such as the runner's `verify-state.json` status index), folders with `RETAIN.md`, an incomplete run written in the last hour, anything that is or contains a link, or anything outside `outputs/`. Check `c-0008` proves these safeguards.

### Update 2026-11-16 (afternoon): harness classification is per build

WatchGuard later classified the blocked harness (`35482483…`) as trusted. The next opt-in run of `c-0002`
rebuilt the harness (SHA-256 `b2eaad08a8273255449098a2f49794b8fc9f13a8ab4fc46f29137758eb15efa6`; binary since
deleted), which WatchGuard blocked again
(parent: Windows PowerShell 5.1). The two builds differ only in the PE timestamp and the assembly MVID: the inbox
compiler is not deterministic, and both runners (`Invoke-SelectionBrokerTests.ps1` and `Invoke-Tests.ps1`) rebuild
the harness on every run. So every run is a new, unclassified program, and opting in will keep producing
BLOCKED_BY_ENDPOINT_SECURITY until the harness is built once, kept at a stable path while its inputs are unchanged,
and that build is classified, or the security owner sets a rule. (The local evidence file was removed after the
checkpoint; its facts are in "Security review evidence" above.)

- That opt-in run (`20261116T161427Z-965594`) recorded `c-0002` as FAIL because of a wrapper defect (stderr under
  `-ErrorAction Stop`). Correct result: BLOCKED_BY_ENDPOINT_SECURITY (WatchGuard "Untrusted program blocked" for
  `b2eaad08…`; x86 not reached). The run folder and its `CORRECTION.md` were removed after the checkpoint; this
  paragraph is the durable correction record.
- Status of `c-0002`: **BLOCKED_BY_ENDPOINT_SECURITY** (re-recorded in `20261116T161816Z-fc7ff1`, nothing built).

### Harness build cache and launch classification (final Phase 0 reconciliation, 2026-11-16)

- **Cache.** `files/tests/NativeHarness.Common.ps1` builds each harness once into `cache/native-harness/<x64|x86>/<first
  16 hex of the input fingerprint>/` and reuses it while the inputs are unchanged. The fingerprint covers the harness
  source, the referenced broker (SHA-256, assembly full name, machine), the compiler (SHA-256, file version), its
  `csc.rsp`, `mscorlib.dll`, the switches and the target. Each entry holds the harness, the exact broker reference
  copy, the compiled source copy and `build-record.json`. Before reuse, the record, fingerprint, harness SHA-256,
  machine type, broker copy and source copy are all re-verified; any mismatch is a miss and the entry is rebuilt.
  Hits and misses are appended to `cache/native-harness/cache-events.jsonl`. Builds happen in a private staging
  folder and are published only when verified. The suite, the focused runner and the installed-COM runner share it.
  Nothing alters a binary after compilation.
- **Launch guard.** Every launch is appended to `cache/native-harness/launch-history.jsonl`. A binary whose most
  recent launch was `BLOCKED_BY_ENDPOINT_SECURITY` is not launched again until `PFI_GATE_NATIVE_RECLASSIFIED` names its
  SHA-256; this stops repeated attempts on a blocked file. A cached build is never treated as approved.
- **Classification.** Launches go through `Invoke-PfiNativeProcess` (direct process start, stdout/stderr captured to
  files, never turned into PowerShell errors). PASS needs exit 0 and the harness's pass line with a positive count.
  An unhandled `InvalidOperationException` (the harness's assertion) is FAIL; any other unhandled exception or an
  NTSTATUS exit is CRASH (exit 5); a launch refused with Win32 5, 225, 226, 1260 or 4551 is
  BLOCKED_BY_ENDPOINT_SECURITY; a missing executable (never launched) or a timeout is BLOCKED.
- **`c-0004` fixed.** `tests/Invoke-InstalledComCheck.ps1` had the same stderr capture defect. Reproduced first against
  the unmodified wrapper with a stub runner (a denied launch gave exit 1 instead of 3, through `NativeCommandError`),
  then fixed; `c-0007` covers both wrappers.
- **Packaging note.** This repository's `.gitattributes` has no `export-ignore` rules, so the template statement under
  "Distribution" does not hold here: `git archive` and GitHub ZIP downloads include every tracked file, including this
  gate. The application does not need it at runtime.

### Shell menu-builder probe (diagnostic, not yet a gate check)

`tests/Test-PfiStaticCascadeMenu.ps1 -OutputRoot <dir> -FixtureRoot <dir>` writes the product's registry plan (or a
candidate layout) under GUID-named HKCU test keys, replaces `DelegateExecute` with an unregistered CLSID and
commands with a non-existent path, builds the menu with `SHCreateDefaultContextMenu` from those keys only, prints
the resulting menu tree and deletes the keys. It launches nothing and loads no third-party shell extension. It
proves what the Shell's static-menu builder produces, not pixels. Phase 0B turns it into a required check.
