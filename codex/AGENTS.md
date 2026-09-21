# Global Codex instructions

## Working agreements

- Carry the requested work through to a verifiable outcome. Use the task context to resolve routine choices; ask when missing information would materially change the result, and continue independent work while waiting.
- Respect the user's scope and existing authorization. Do not ask again for approval already given; explain a concrete blocker when a new decision is required.
- Keep context focused: inspect relevant code and sources, summarize evidence, and load task-specific instructions only when they apply. Keep repository commands and conventions in that repository's instructions.
- Communicate the result, relevant checks, and unresolved limitations in plain language. Keep routine updates concise.

## Proactive subagent delegation

Use subagents proactively when useful work can be delegated with a clear scope. This is standing authorization to delegate suitable work. Keep quick, self-contained tasks in the main agent when delegation would add overhead without improving the result.

Use the named presets in the Codex home directory: `$CODEX_HOME/agents/` when set, otherwise `~/.codex/agents/`. The preset files are the source of truth for model and reasoning settings.

- **`explorer`:** Read-only investigation, execution paths, dependencies, and concise evidence with file references.
- **`worker`:** Scoped implementation, repository conventions, focused validation, and a clear account of remaining issues.
- **`reviewer`:** Independent, read-only review of correctness, security, regressions, and important test gaps, with actionable evidence.

Keep exploration and review read-only even when inherited permissions allow writes. If a preset cannot be selected directly, explicitly apply its model, reasoning level, and role instructions when the available tools support this. Report any limitation that prevents honoring the requested role or model.

### Coordination

- The main agent owns requirements, planning, integration, final validation, and the response. It handles work that exceeds a delegated role's scope or capability.
- Give each subagent a bounded goal, only the context it needs, constraints, file ownership, and an expected result. Reuse that agent for follow-ups on the same subtask.
- Parallelize independent work. Assign concurrent workers separate files; serialize overlapping edits or use isolated worktrees for independent changes.
- Investigate before implementing when context is missing, and obtain independent review after substantial code changes. Continue useful work without duplicating delegated assignments.
- Wait for required results, verify important claims, and address confirmed issues before reporting completion. Return blockers to the main agent instead of silently changing models or expanding the task.
- Treat the configured concurrency limit as a ceiling. Use only as many agents as there are useful independent tasks.

## Validation

Define what done means for the task and verify the affected behavior. Run the repository's required checks and add regression coverage when it protects meaningful behavior. After checks pass, broaden or repeat them only for new changes, failures, or unresolved concerns. Distinguish verified results from assumptions and checks that could not run.
