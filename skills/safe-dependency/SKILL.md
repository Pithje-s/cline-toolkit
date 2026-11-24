---
name: safe-dependency
description: Safe package/library installation guard. Trigger when asked to install, add, or upgrade a dependency. Verifies the package really exists (anti-typosquatting), checks the latest stable version, and warns before heavy or system-config-changing installs.
---

# Safe Dependency

Installing a dependency is a supply-chain decision. A single wrong package name can run attacker code on the machine. Verify before you install.

## When to activate

- User asks to install / add / upgrade a package or library
- User says: установи, добавь библиотеку, поставь пакет, npm install X, pip install X
- A task requires a new import/dependency

## When NOT to activate

- Removing a dependency
- Purely reading/inspecting already-installed packages

## Safety gates (run in order)

### Gate 1 - Existence & typosquatting check

Before installing ANY package, confirm it is the real, intended package and not a typosquat or hallucinated name.

- If you are not certain the package exists, VERIFY it first (registry search / web fetch) before installing.
- Compare the name against popular packages. A near-miss of a well-known name is a red flag.
- Do not install a name you invented or are unsure about. Confirm, then install.

```powershell
# npm: confirm the package exists and inspect metadata (no install)
npm view <package> version description repository.url
# PyPI: confirm the package exists and who publishes it
pip index versions <package>
```

Treat as a STOP condition if:

- The package does not exist in the registry (possible hallucination)
- The name is a one-character variant of a popular package (possible typosquat)
- The publisher/maintainer looks unrelated or the download counts are implausibly low

On any STOP condition: do NOT install. Report the concern and ask the user to confirm the exact package.

### Gate 2 - Latest stable version

- Determine the current latest STABLE version (exclude alpha/beta/rc/pre-release).
- Prefer a pinned/exact version over a floating range for reproducibility.
- Note the version you will install in your report.

### Gate 3 - Weight & system impact warning

Warn the user BEFORE proceeding if any of these apply:

- The package is large or pulls a heavy dependency tree
- It requires changing system configuration (env vars, global installs, services, firewall, PATH)
- It needs elevated/administrator privileges
- It adds a native build step or system-level tools

## Procedure

1. Identify the exact package name and intended purpose.
2. Gate 1: run the existence/metadata check. STOP if suspicious.
3. Gate 2: find the latest stable version.
4. Gate 3: assess weight/system impact; warn if triggered.
5. Install with a pinned version and a non-interactive flag:
   ```powershell
   npm install <package>@<version>
   pip install "<package>==<version>"
   ```
6. Verify the install succeeded and capture output:
   ```powershell
   npm ls <package>; Write-Host "EXIT:$LASTEXITCODE"
   pip show <package>
   ```
7. Report: package, version, why it is safe, any warnings, verification result.

## Report format

```
DEPENDENCY: <name>@<version>
- Exists: yes (publisher/repo, downloads)
- Typosquat check: clear
- Latest stable: <version>
- Weight/system impact: <none | warning: ...>
- Installed & verified: <result / exit code>
```

## Hard rules

- Never install a package you have not confirmed exists.
- Never install without checking the latest stable version.
- Warn before heavy or system-changing installs - do not silently proceed.
- On doubt, stop and ask. A wrong dependency is a security incident, not a typo.