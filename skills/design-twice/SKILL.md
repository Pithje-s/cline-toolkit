---
name: design-twice
description: Two-approaches design pass before implementing large features or refactors (Plan Mode). Trigger when planning a new significant feature, a refactor, or any change with meaningful architectural impact. Proposes two substantially different approaches, compares them, and waits for the user's choice before Act Mode.
---

# Design Twice

Before writing code for a significant change, produce TWO genuinely different designs, compare them on objective criteria, and wait for a decision. One obvious solution is not a design - it is a guess.

## When to activate

- Planning a new large feature
- Planning a refactor that touches architecture or many files
- Any change where the "how" is non-trivial and reversible only with effort
- User says: design, спланируй, как лучше сделать, варианты

## When NOT to activate

- Small, well-scoped changes with one obvious path (typo, config value, local bug fix)
- Act Mode execution of an already-approved plan
- When the user has already chosen an approach

## Rules

1. Stay in Plan Mode. Do not write code during this skill.
2. Produce exactly TWO substantively different approaches (not cosmetic variants).
3. The two approaches must differ in structure/strategy, not just naming or minor tweaks.
4. Compare them honestly on the criteria below.
5. Give a recommendation, but WAIT for the user's explicit choice before any Act Mode.

## The two approaches

### Approach A: {{short name}}
- **Core idea**: {{one paragraph}}
- **How it works**: {{key components / data flow}}
- **Pros**: {{...}}
- **Cons**: {{...}}

### Approach B: {{short name}}
- **Core idea**: {{one paragraph}}
- **How it works**: {{key components / data flow}}
- **Pros**: {{...}}
- **Cons**: {{...}}

## Comparison table

| Criterion | Approach A | Approach B |
|-----------|-----------|-----------|
| Maintainability (ease of future changes) | {{}} | {{}} |
| Scalability (growth, load, feature surface) | {{}} | {{}} |
| Impact on existing code (blast radius) | {{}} | {{}} |
| Implementation effort / time | {{}} | {{}} |
| Reversibility (cost to change later) | {{}} | {{}} |
| Risk (correctness, security, unknowns) | {{}} | {{}} |

## Recommendation

- **Recommend**: {{A or B}}
- **Because**: {{2-3 sentences tied to the criteria and the task's priorities}}
- **Trade-off I accept**: {{what we give up with the recommendation}}

## Then wait

End with an explicit question:

```
Какой подход выбираем - A или B? После выбора перейду к детальному плану и Act Mode.
```

Do NOT proceed to implementation until the user chooses. If the user asks to combine or modify, iterate on the design, do not jump to code.