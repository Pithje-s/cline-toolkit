---
name: verify-changes
description: Mandatory verification that every change was actually applied and works. Use before completing ANY task that modifies files or produces output. Guarantees no change is reported as done without real evidence (file changed, build/test run, or output captured).
---

# Verify Changes

Any change is UNFINISHED until it is applied to the files and proven to work. No task ends with "apply these changes yourself" or "this should work" - the agent applies and verifies, then reports PASS with evidence.

## When to activate

- Before completing ANY task that created, edited, or was supposed to edit files
- Before reporting any task as "done"
- Whenever you are tempted to write "apply these changes" or "expected to pass"
- When resuming an interrupted task (verify actual state first)

## The non-negotiable rule

> If you described an edit but did not make it, the task is not done.
> If you made an edit but did not run it, the change is unverified.
> If verification failed and you did not retry, the task is not done.

## Protocol

### Step 1 - Confirm the change is real (not just proposed)

For every file you intended to change, prove it changed:

```powershell
# See what actually changed on disk
git --no-pager diff --stat
git --no-pager diff <file>

# For a brand-new file, confirm it exists and show head
Test-Path <path>; Get-Content <path> -Head 20
```

Expected: each intended file appears in the diff / exists with the expected content.
If an intended edit is missing -> re-apply it now. Do NOT report done.

### Step 1.5 - Placeholder scan (см. правило Zero Placeholders)

Определение заглушки — в `rules/01-core.md` (Zero Placeholders). Здесь только механика проверки:

```powershell
# Scan only the changes for placeholder markers
git --no-pager diff | Select-String -Pattern 'TODO','FIXME','XXX','rest of code','existing code','\.\.\.'
```

If ANY placeholder that you introduced is found -> verdict **FAIL**, cite the exact lines, and implement the real code (or ask for missing context - never leave a stub). Pre-existing markers unrelated to your change are noted, not failed.

### Step 1.55 - Comment Noise Check (см. правило «Комментарии»)

Scan the added/changed lines for redundant comments:

- Comments that restate what the code does or echo the function/variable name (e.g. `// Import the module`, `// Return true`, `// Loop over the array`, `// Increment i`)
- AI meta-comments (e.g. `// Changed code`, `// Here we add the function`, `// End of function`)

```powershell
# Review added comment lines in the diff
git --no-pager diff | Select-String -Pattern '^\+.*(//|#|/\*)'
```

Allowed: comments that explain WHY (tricky business logic, library bug workaround, non-obvious architecture). If a comment merely restates WHAT the code does or duplicates a name -> verdict **FAIL** with a requirement to delete the comment (and rewrite the code to be self-explanatory if needed).

### Step 1.6 - Fresh-read guard (no blind edits)

When modifying EXISTING code (not creating a new file):

- Confirm you have read the current version of the target file IN THIS SESSION before editing it.
- If you edited a file you did NOT read in the current session -> verdict **FAIL** (risk of breaking code due to stale content or wrong line/syntax). Read it now, then re-do the edit correctly.
- Navigation via `memory-bank/projectMap.md` is allowed, but every `replace_in_file` must be based on the freshly read, actual snippet - never on memory alone.

```powershell
# Confirm the file was read this session; if unsure, read it now:
Get-Content <file> | Select-Object -First 50
```

### Step 2 - Verify it works

Pick the strongest available evidence for the project type:

- **Automated**: build, tests, type-check, lint. Capture output to a file, then read it.
  ```powershell
  npm test *> test-out.txt; Write-Host "EXIT:$LASTEXITCODE"; Get-Content test-out.txt -Tail 30
  ```
- **Manual run**: launch the app/script and attach the log or a screenshot.
- **Static**: if nothing can run, do a focused read of the changed code path and quote the lines.

### Step 3 - Fix-verify-retry

If verification fails, diagnose, fix, and re-run. Loop until it passes or you hit the iteration limit (then report honestly). See skill `repair-loop`.

### Step 4 - Report with evidence

```
VERIFIED
- <file> changed: <what> (evidence: git diff / file shown)
- <command> run: <result> (evidence: exit code / output tail)
- Status: PASS
```
If something genuinely cannot be verified:
```
PARTIALLY VERIFIED
- <file> changed: <what>
- NOT verified: <what> because <reason>
- To verify: <command>
```

## Anti-patterns

| Anti-pattern | Instead |
|-------------|---------|
| "Apply these changes" | Apply them yourself, then verify |
| "This should work now" | Run it and show it works |
| "Tests not run this session" | Run them, or use repair-loop |
| Reporting success without checking file state | git diff / read the file first |
| Claiming a UI change works without a screenshot | Attach a screenshot or run log |

## Evidence types (strongest first)

1. Command output with exit code (build/test/type-check/lint)
2. `git diff` showing the exact change on disk
3. App log / runtime output from a manual launch
4. Screenshot of the working result
5. Direct quote of the changed lines after re-reading the file