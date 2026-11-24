---
name: external-research
description: Research escalation when local knowledge is exhausted. Triggers after 3 failed repair-loop attempts, or when the user asks to research/look up an unfamiliar error, API, or library. Builds precise English queries, requests fresh online data if the model supports :online, otherwise produces ready-to-open links (GitHub Issues, StackOverflow, official docs). Never invents APIs.
---

# External Research

Local knowledge is exhausted. Stop guessing at code - go get ground truth. This skill activates automatically after 3 failed `repair-loop` iterations, or on explicit request.

## When to activate

- After 3 failed repair attempts (rule of 3 attempts -> mandatory escalation)
- User says: research, find out, погугли, поищи, не знаю как решить, research this error
- An unfamiliar API, library behavior, or error message you cannot resolve with certainty
- You are about to invent a method/flag/parameter to make something work

## When NOT to activate

- You can fix it locally within the attempt budget (use `repair-loop`)
- The answer is already known with 100% certainty

## Core rule

> Never invent an API, method, parameter, or behavior. If you are not 100% sure, research it. A hallucinated API is worse than saying "I need to check".

## Step 1 - Build a precise problem statement

Summarize before searching:

- Exact error message (verbatim, full stack trace tail)
- Library/package + exact version
- Minimal code snippet that triggers it
- Environment (OS, runtime version)
- What you already tried and why it failed

## Step 2 - Online path (model supports `:online`)

If the current model supports the `:online` suffix:

1. Tell the user to switch to a `:online` model (e.g. `anthropic/claude-3.5-sonnet:online`) for fresh data.
2. Then formulate precise ENGLISH queries and run the web search.

Query template (English, high signal):

```
"<exact error message>" <library> <version> <language/runtime> (site:github.com OR site:stackoverflow.com)
```

- Use the verbatim error string in quotes
- Add library + version + runtime
- Add `site:` filters for GitHub / StackOverflow / official docs

## Step 3 - Offline path (no `:online`): generate ready links

Produce clickable, pre-filled links the user can open and paste context back:

```
GitHub Issues:
  https://github.com/<owner>/<repo>/issues?q=<url-encoded error + version>
Stack Overflow:
  https://stackoverflow.com/search?q=<url-encoded error + library>
Official docs:
  https://<known-docs-domain>/  (only if certain; otherwise omit)
Package registry:
  https://www.npmjs.com/package/<pkg>  /  https://pypi.org/project/<pkg>/
```

Ask the user to open the most relevant link and paste the top result / issue body back.

## Step 4 - Apply findings

- Extract the root cause and the concrete fix from authoritative sources.
- Cite the source (link) for the fix in your report.
- Return to `repair-loop` to apply and verify, OR apply directly if trivial.

## Output format

```
EXTERNAL RESEARCH
- Problem: <one line>
- Online available: <yes -> ran queries | no -> generated links>
- Queries / Links:
  - <query or link>
- Most relevant finding: <summary + source link>
- Proposed fix: <concrete change>
- Confidence: <high/medium/low + why>
```

## Hard rules

- No invented APIs. Certainty or research - no third option.
- Prefer official docs > maintained GitHub issues > Stack Overflow > blogs.
- Always cite the source link for any fix derived from research.
- If research is inconclusive, say so and propose a safe diagnostic step instead of guessing.