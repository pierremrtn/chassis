# Chassis Skills

LLM-targeted skills that guide an AI coding assistant to use Chassis correctly.

Each skill is a self-contained markdown file (`<skill-name>/SKILL.md`) with frontmatter (`name`, `description`) and prose covering core concepts, DO/DON'T rules, an actionable workflow checklist, and high-fidelity examples. The content distills `docs/coding_rules.md`, `docs/error_management.md`, and `docs/04_ui_integration.md` into form-factors an LLM picks up at the call site rather than browsing prose.

These skills are written to be loaded by AI assistants — Claude Code, Cursor, or any agent that reads markdown skill files keyed on a `description` trigger. They are not user-facing documentation; for that, see [`docs/`](../docs/).

## When each skill triggers

| Skill | Use when |
|---|---|
| [`chassis-bootstrap-app`](chassis-bootstrap-app/SKILL.md) | Wiring `main.dart` and the composition root (Repositories → `AppMediator` → `ViewModelProvider`s). |
| [`chassis-register-handler-with-codegen`](chassis-register-handler-with-codegen/SKILL.md) | Adding `@chassisHandler` and running `build_runner` to regenerate `AppMediator`. |
| [`chassis-create-command`](chassis-create-command/SKILL.md) | Adding a state-mutating operation (write, create, update, delete, submit). |
| [`chassis-create-read-query`](chassis-create-read-query/SKILL.md) | Adding a one-time data fetch (export, validation, pre-render bootstrap). |
| [`chassis-create-watch-query`](chassis-create-watch-query/SKILL.md) | Adding a reactive data subscription that the UI should stay in sync with. |
| [`chassis-write-handler-test`](chassis-write-handler-test/SKILL.md) | Unit-testing a handler with mocked repository interfaces. |
| [`chassis-create-view-model`](chassis-create-view-model/SKILL.md) | Adding a `ViewModel<State, Event>` with state, events, and Mediator dispatch. |
| [`chassis-render-async-state`](chassis-render-async-state/SKILL.md) | Rendering an `Async<T>` value with `AsyncBuilder`. |
| [`chassis-handle-view-model-events`](chassis-handle-view-model-events/SKILL.md) | Wiring one-time UI side effects (snackbars, navigation) with `ViewModelProvider.withEvents` or `ConsumerMixin`. |
| [`chassis-consume-view-model`](chassis-consume-view-model/SKILL.md) | Providing a ViewModel and reading it from descendants (`watch` vs `read`). |
| [`chassis-handle-errors`](chassis-handle-errors/SKILL.md) | Mapping infrastructure exceptions, recovering selectively in handlers, routing errors through state vs events, translating in the UI. |
| [`chassis-organize-feature`](chassis-organize-feature/SKILL.md) | Laying out the directory and file structure for a feature. |

## How to install in your agent

The skills are plain markdown files — every consumer reads them differently:

- **Claude Code**: copy or symlink each skill folder under `.claude/skills/` (project-scoped) or `~/.claude/skills/` (global). The `name` and `description` in the frontmatter drive triggering.
- **Cursor**: copy each `SKILL.md` into `.cursor/rules/`, optionally renaming to match Cursor's rule format.
- **Other agents**: most skill systems read frontmatter `name` + `description` and the markdown body. Copy the folders into wherever your agent expects skills to live.

The skills do not need to be installed at the package level. Drop them in once per repo (or globally) and the agent picks them up.

## Conventions

- **Voice**: principle-first, engineering-focused. The conventions follow [`doc_guidelines.md`](../doc_guidelines.md): no "easy", "magic", "simply", "just".
- **DO / DON'T format**: rules are written as imperative sentences, with a one-line rationale in italics after an em-dash. The shape is `**DO** declare … — *the Mediator's runtime type lookup depends on the extends chain.*`.
- **Examples are runnable**: every code block uses real Chassis API and matches the source documented in `chassis_flutter/` and `chassis/`.
- **Citations**: where a chassis doc passage is already well-formed, the skill quotes it verbatim with attribution rather than paraphrasing. Source is one of `docs/coding_rules.md`, `docs/error_management.md`, `docs/04_ui_integration.md`, `docs/02_business_logic.md`, `docs/03_code_generation.md`, or `golden_sample.md`.

## A rule that runs through every skill

The `@generateCommandHandler` and `@generateQueryHandler` annotations on repository methods are **reserved for human authors** and being phased out. Every skill that touches a handler explicitly forbids the LLM from emitting them. The path is always: write the Command / Query class by hand, write the `*Handler` class by hand, annotate the manual handler with `@chassisHandler`, run `build_runner`. See [`chassis-register-handler-with-codegen`](chassis-register-handler-with-codegen/SKILL.md).

## Maintenance

When `docs/coding_rules.md`, `docs/error_management.md`, or `docs/04_ui_integration.md` change, audit the skills that cite them:

- A new rule in the source → distill it as a `DO`/`DON'T` line in the matching skill.
- A retired rule → remove it from the skill and any examples that exercise it.
- An API rename or signature change in `chassis_flutter` → update the corresponding example.

Run the verification checks before opening a PR:

```bash
# Voice check — should return zero hits
grep -ri 'easy\|magic\|simply\|just' skills/

# Anti-`@generateHandler` check — every hit must be in a forbidding context
grep -ri 'generateHandler' skills/

# English-only check — eyeball-grep for stray French
grep -ri '[éèêàç]' skills/ | grep -v '/SKILL.md:.*  *—' # em-dashes are ok
```
