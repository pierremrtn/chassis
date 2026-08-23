# Chassis Skills

LLM-targeted skills that guide an AI coding assistant to use Chassis correctly.

Each skill is a self-contained markdown file (`<skill-name>/SKILL.md`) with frontmatter (`name`, `description`) and prose covering core concepts, DO/DON'T rules, an actionable workflow checklist, and high-fidelity examples. The content distills `docs/coding_rules.md`, `docs/error_management.md`, and `docs/04_ui_integration.md` into form-factors an LLM picks up at the call site rather than browsing prose.

These skills are written to be loaded by AI assistants — Claude Code, Cursor, or any agent that reads markdown skill files keyed on a `description` trigger. They are not user-facing documentation; for that, see [`docs/`](https://github.com/pierremrtn/chassis/tree/main/docs).

## When each skill triggers

| Skill | Use when |
|---|---|
| [`chassis-bootstrap-app`](chassis-bootstrap-app/SKILL.md) | Wiring the composition root: `lib/mediator.dart` carrying `@ChassisApp()` (+ modules) → generated registration-only `AppMediator` → `Chassis.initialize(AppMediator(...))` in `main()` before `runApp`, with `LoggingMiddleware`/`CrashReportingMiddleware` wired via `..addMiddleware(...)`. No global mediator variable. |
| [`chassis-register-handler-with-codegen`](chassis-register-handler-with-codegen/SKILL.md) | Adding `@chassisHandler` (unnamed constructor; dependencies as parameters, named preferred) and running `build_runner` to regenerate the mediator's registration constructor; the missing-handler build check and `@unhandledMessage`; `@chassisModule` cross-package discovery; decoding chassis_builder build errors and warnings. |
| [`chassis-create-command`](chassis-create-command/SKILL.md) | Adding a state-mutating operation (write, create, update, delete, submit). |
| [`chassis-create-read-query`](chassis-create-read-query/SKILL.md) | Adding a one-time data fetch (export, validation, pre-render bootstrap). |
| [`chassis-create-watch-query`](chassis-create-watch-query/SKILL.md) | Adding a reactive data subscription that the UI should stay in sync with. |
| [`chassis-write-handler-test`](chassis-write-handler-test/SKILL.md) | Unit-testing a handler with mocked repository interfaces. |
| [`chassis-test-view-model`](chassis-test-view-model/SKILL.md) | Testing a ViewModel end-to-end through `TestMediator` (`package:chassis/testing.dart`): stubbing `whenRun`/`whenRead`/`whenWatch`, asserting states, events, and dispatched messages via structural equality. |
| [`chassis-create-view-model`](chassis-create-view-model/SKILL.md) | Adding a `ViewModel<State, Event>` with state, events, and message dispatch through `run`/`read`/`watch` — no mediator field, no generated methods. |
| [`chassis-render-async-state`](chassis-render-async-state/SKILL.md) | Rendering an `Async<T>` value — inline `switch` expression by default, `AsyncBuilder` for `maintainState` anti-flicker behavior. |
| [`chassis-handle-view-model-events`](chassis-handle-view-model-events/SKILL.md) | Wiring one-time UI side effects (snackbars, navigation) with `ViewModelProvider.withEventListener`, the `EventListener` widget, or `EventListenerMixin`. |
| [`chassis-consume-view-model`](chassis-consume-view-model/SKILL.md) | Providing a ViewModel and reading it from descendants (`watch` vs `read`). |
| [`chassis-handle-errors`](chassis-handle-errors/SKILL.md) | Mapping infrastructure exceptions, recovering selectively in handlers, routing errors through state vs events, translating in the UI. |
| [`chassis-organize-feature`](chassis-organize-feature/SKILL.md) | Laying out the directory and file structure for a feature, or extracting one into a shared `@chassisModule` package. |
| [`chassis-optimistic-update`](chassis-optimistic-update/SKILL.md) | Making a toggle/favorite/reorder feel instant: result-field optimism (`optimistic:`) vs repository-level optimism for watched projections, with the rollback contract and its traps. |
| [`chassis-paginate-list`](chassis-paginate-list/SKILL.md) | Infinite scroll / load-more: cursor in state, `RunPolicy.sequential`, accumulation, and loading-more rendered from `AsyncLoading(previous:)`. |

## How to install in your agent

The skills ship inside the `chassis` package, so any project that depends on chassis has them in its pub cache. The bundled installer symlinks each skill into the project:

```bash
dart run chassis:install_skills
```

By default this links every skill folder into `.claude/skills/` (Claude Code's project-scoped location). The symlinks target the *pinned* chassis version in the pub cache, so the skills always match the API the project actually uses — re-run the command after upgrading chassis. Pass a target directory to install elsewhere, and `--copy` to copy instead of symlinking (the automatic fallback on file systems without symlink support, e.g. Windows without Developer Mode):

```bash
dart run chassis:install_skills ai/skills --copy
```

For agents with other conventions, the skills are plain markdown:

- **Claude Code**: the default `dart run chassis:install_skills` — or copy/symlink each skill folder under `.claude/skills/` (project-scoped) or `~/.claude/skills/` (global) by hand. The `name` and `description` in the frontmatter drive triggering.
- **Cursor**: copy each `SKILL.md` into `.cursor/rules/`, optionally renaming to match Cursor's rule format.
- **Other agents**: most skill systems read frontmatter `name` + `description` and the markdown body. Copy the folders into wherever your agent expects skills to live.

The skills do not need to be installed at the package level. Drop them in once per repo (or globally) and the agent picks them up.

## Conventions

- **Voice**: principle-first, engineering-focused. The conventions follow [`doc_guidelines.md`](https://github.com/pierremrtn/chassis/blob/main/archive/doc_guidelines.md): no "easy", "magic", "simply", "just".
- **DO / DON'T format**: rules are written as imperative sentences, with a one-line rationale in italics after an em-dash. The shape is `**DO** declare … — *the Mediator's runtime type lookup depends on the extends chain.*`.
- **Examples are runnable**: every code block uses real Chassis API and matches the source documented in `chassis_flutter/` and `chassis/`.
- **Citations**: where a chassis doc passage is already well-formed, the skill quotes it verbatim with attribution rather than paraphrasing. Source is one of `docs/coding_rules.md`, `docs/error_management.md`, `docs/04_ui_integration.md`, `docs/02_business_logic.md`, `docs/03_code_generation.md`, or `golden_sample.md`.

## A rule that runs through every skill

The pre-1.0 repository-method generation annotations (the `@generate*Handler` family) were **removed in 1.0.0** — the symbols no longer exist, and any occurrence in code or docs is an error. The path is always: write the Command / Query class by hand, write the `*Handler` class by hand (unnamed constructor; prefer named dependency parameters), annotate it with `@chassisHandler`, run `build_runner`. See [`chassis-register-handler-with-codegen`](chassis-register-handler-with-codegen/SKILL.md).

## Maintenance

When `docs/coding_rules.md`, `docs/error_management.md`, or `docs/04_ui_integration.md` change, audit the skills that cite them:

- A new rule in the source → distill it as a `DO`/`DON'T` line in the matching skill.
- A retired rule → remove it from the skill and any examples that exercise it.
- An API rename or signature change in `chassis_flutter` → update the corresponding example.

Run the verification checks before opening a PR:

```bash
# Voice check — should return zero hits.
# --include=SKILL.md keeps this README (which must name the banned words)
# out of the results.
grep -rin 'easy\|magic\|simply\|just' --include=SKILL.md chassis/skills/

# Removed-API check — should return zero hits (symbols deleted in 1.0.0).
# The bracketed first letters keep this command from matching itself.
grep -rn 'generate[Q]ueryHandler\|generate[C]ommandHandler\|[R]epositoryGenerator\|repository[_]builder\|mediator[_]name\|output[_]name\|app[_]mediator\.dart' chassis/skills/

# English-only check — should return zero hits.
# --include keeps this command from matching its own character class.
grep -rin '[éèêàç]' --include=SKILL.md chassis/skills/
```
