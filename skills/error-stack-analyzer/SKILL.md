---
name: error-stack-analyzer
description: Parse large logs and stack traces to find the exact line in OUR code that caused the failure and explain the root cause. Triggers on crashes, exceptions, stack traces, "разбери ошибку", "проанализируй лог", "stack trace", "traceback". Ignores framework/library internals (node_modules, site-packages, vendor).
---

# Error Stack Analyzer

A big stack trace is mostly noise. The real signal is the first frame that belongs to OUR code. Find it, explain it, fix it.

## When to activate

- A crash / exception / stack trace / traceback needs analysis
- User says: разбери ошибку, проанализируй лог, что за ошибка, analyze this stack trace
- A test/build fails with a multi-frame trace
- Output is too large to read top-to-bottom

## Step 1 - Capture the full log

Save the raw output to a file, then work from the file (do not scroll interactively):

```powershell
<command> *> error-log.txt; Write-Host "EXIT:$LASTEXITCODE"
```

## Step 2 - Identify the error type and message

- Read the TOP of the trace (the exception type + message) and the BOTTOM (often the entry point).
- Note the exception class and the verbatim message.

## Step 3 - Filter out library/framework noise

Ignore frames from third-party internals:

- `node_modules/`, `.../site-packages/`, `vendor/`, `.venv/`, `dist/`, framework bootstrap
- Known runtime internals (stdlib, built-ins)

Focus on frames that point to OUR source tree (e.g. `src/`, `app/`, `lib/`, the project package name).

## Step 4 - Find the first OUR-code frame

- The FIRST frame (top-down) that references our own source file is usually where the failure originated.
- Record `file:line` for it and the 1-2 frames above it (call chain).
- If ALL frames are library code, the bug is in how we CALL the library - find the last our-code frame that invoked it.

## Step 5 - Read and explain the root cause

- Read the code around the identified `file:line`.
- Determine: what value/state caused it, why it is invalid, which earlier assumption broke.
- Distinguish symptom (the throw) from root cause (the bad input/state upstream).

## Step 6 - Hand off

- Hand the `file:line` + root cause to `repair-loop` to apply and verify the fix.
- If 3 repair attempts fail -> `external-research`.

## Output format

```
STACK ANALYSIS
- Error: <ExceptionType>: <message>
- Failure origin: <file>:<line>  (our code)
- Call chain: <file:line> -> <file:line> -> <throw site>
- Root cause: <what value/state was invalid and why>
- Ignored noise: node_modules / site-packages / framework internals
- Proposed fix direction: <one-two sentences>
- Next: repair-loop (apply + verify)
```

## Rules

- Always point to a concrete `file:line` in OUR code, not a library frame.
- Separate the symptom (where it threw) from the root cause (why the bad state existed).
- Do not propose a fix until the root cause is identified - no guessing.
- If the trace is truncated, ask for the full log or the frames around the throw.