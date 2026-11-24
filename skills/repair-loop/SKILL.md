---
name: repair-loop
description: Systematic fix-verify-retry loop. Use when a test fails, build breaks, type check fails, or any automated check is red - iterate until green. Also use when an agent is tempted to report failure and stop without exhausting repair attempts.
---

# Repair Loop

Automatic fix → re-test → repeat until all checks pass. Never report a check as "expected to pass" or "should work" - only as "verified passing" after an actual run.

## When to activate

Activate whenever ANY of these occur:

- A test fails during verification
- The build fails after a code change
- A type check reports errors
- A lint check fails
- A CI check is red
- The agent is about to report "tests not run" or "could not verify"
- You catch yourself about to say "this should fix it" without running the check
- User says: fix it, make it work, it's broken, repair, не работает, исправь, почини

## When NOT to activate

- During Plan mode (no edits allowed)
- When user explicitly asks to stop and report current state
- After 3 failed iterations -> hand off to `external-research` (do not keep looping blindly)

## The loop

1. Detect failure - run all checks, capture output, identify what failed
2. Diagnose root cause - read failing code + test, find why
3. Apply minimal fix - change only what is needed
4. Re-run the failed check (specific, not full suite)
5. PASS -> step 6, FAIL -> step 2
6. Run full suite to catch regressions
7. Report only when all checks pass, with evidence

## Steps

### 1. Detect failure

Run all available checks and identify what failed:

```powershell
npm test *> test-out.txt; Write-Host "TESTS_EXIT:$LASTEXITCODE"; Get-Content test-out.txt -Tail 40
npm run build *> build-out.txt; Write-Host "BUILD_EXIT:$LASTEXITCODE"; Get-Content build-out.txt -Tail 40
npx tsc --noEmit *> tsc-out.txt; Write-Host "TSC_EXIT:$LASTEXITCODE"; Get-Content tsc-out.txt
npm run lint *> lint-out.txt; Write-Host "LINT_EXIT:$LASTEXITCODE"; Get-Content lint-out.txt -Tail 40
```

Record: which check failed, error message, file, line number.

### 2. Diagnose root cause

Read the failing code and the test/error. Determine: what was expected, what happened, why they differ.

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `undefined is not a function` | Wrong import or missing method | Check export, fix import |
| `expected X, received Y` | Logic error or wrong test data | Fix logic or test data |
| `Cannot find module` | Missing install or wrong path | Run install, fix path |
| `timeout` | Slow operation or infinite loop | Optimize or fix loop condition |
| `type error` | Type mismatch | Fix type annotation or conversion |

### 3. Apply minimal fix

- Change only what is needed for the specific failure
- No unrelated refactoring, no new features
- Do not change test expectations (unless the test itself is wrong)
- Do not suppress warnings/errors

### 4. Re-run the failed check

```powershell
npm test -- --testPathPattern="auth" *> test-out.txt; Write-Host "EXIT:$LASTEXITCODE"; Get-Content test-out.txt -Tail 30
```

### 5. Check result

- PASS -> step 6
- FAIL -> step 2 (diagnose again with new error info)

### 6. Run full suite (catch regressions)

```powershell
npm test *> test-full.txt; Write-Host "EXIT:$LASTEXITCODE"; Get-Content test-full.txt -Tail 40
```

If any other check fails, go back to step 1.

### 7. Report (only when all checks pass)

```
REPAIR COMPLETE
- Fixed: <file>:<line> - <what was wrong> -> <what it is now>
- Root cause: <one sentence>
- Verification:
  - npm test -> ALL PASS
  - npm run build -> SUCCESS
  - npx tsc --noEmit -> NO ERRORS
- Files changed: <list>
```

If checks cannot be run:

```
REPAIR COMPLETE (unverified)
- Fixed: <file>:<line>
- NOT verified because: <reason>
- Commands to verify: <list>
```

## Iteration limits (rule of 3 attempts)

| Condition | Action |
|-----------|--------|
| 3 consecutive failed iterations (no progress on the same error) | STOP. Force hand-off to `external-research` with the diagnosis. Do NOT keep guessing. |
| New errors introduced by the fix | Revert the fix, change approach (not just tweak) |
| Clearly architectural root cause | Stop, escalate to `design-twice` / ask user |

> Blind trial-and-error is forbidden. Each iteration must be a real diagnosis -> minimal fix -> re-check. If 3 attempts fail, local knowledge is exhausted -> `external-research` (see rule 03-workflow-search).

## Anti-patterns

| Anti-pattern | Why bad | Instead |
|-------------|---------|---------|
| "Tests pass" without running them | Hallucinated verification | Run the tests |
| "Should work now" without checking | No evidence | Run and check |
| Changing test to make it pass | Hides bugs | Fix the code, not the test |
| Disabling lint rule to fix lint | Hides the problem | Fix the code |
| Adding `// @ts-ignore` to fix type error | Hides type bugs | Fix the type |
| Skipping a failing test | Hides regression | Fix or explain why test is wrong |
| Refactoring during repair | Introduces new bugs | Minimal fix only |

## Verification commands by project type

| Project type | Test | Build | Lint | Type check |
|-------------|------|-------|------|------------|
| Node.js (npm) | `npm test` | `npm run build` | `npm run lint` | `npx tsc --noEmit` |
| Python (pytest) | `pytest` | `python -m build` | `ruff check .` | `mypy .` |
| Rust | `cargo test` | `cargo build` | `cargo clippy` | `cargo check` |
| Go | `go test ./...` | `go build ./...` | `go vet ./...` | - |
| Java (Maven) | `mvn test` | `mvn package` | `mvn verify` | - |