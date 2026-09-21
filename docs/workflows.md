# Using this setup

These are optional workflows. The installer applies the three presets and shared defaults; it does not enable integrations, schedule work, or change permission settings.

## Start with a verifiable result

For substantial work, supply the outcome, relevant context, constraints, and completion checks. For example:

> Fix the retry bug described in this issue. Preserve the public API. Reproduce the failure, implement the fix, and run the affected tests. Use the explorer if the call path is unclear and the reviewer for an independent check of a substantial change.

Use `/plan` when requirements or the approach need discussion. Use `/goal` when you explicitly want persistent work toward a defined outcome. Keep related follow-ups in the same chat; use a new chat when the outcome changes. These are workflow choices rather than mandatory stages for every edit. See [best practices](https://learn.chatgpt.com/guides/best-practices) and [long-running work](https://learn.chatgpt.com/docs/long-running-work).

## Choose the amount of reasoning

The default is Astra with `xhigh`. To try less reasoning on well-scoped work, copy the quick profile into your Codex home. The review profile selects Sol with `high` for an explicit review session. Inspect the examples first; `cp -i` asks before replacing an existing file.

```sh
mkdir -p "${CODEX_HOME:-$HOME/.codex}"
cp -i examples/profiles/codex-setup-quick.config.toml "${CODEX_HOME:-$HOME/.codex}/"
cp -i examples/profiles/codex-setup-review.config.toml "${CODEX_HOME:-$HOME/.codex}/"

codex --profile codex-setup-quick
codex --profile codex-setup-review review --uncommitted
```

Run these from the checkout for copying, then start Codex from the repository you want it to work in. The examples preserve the configured models and efforts of named subagents. The review profile selects a model and effort; it does not activate the custom reviewer's instructions or permission requests.

Current CLI profiles are separate `$CODEX_HOME/<name>.config.toml` files. Since Codex 0.134.0, legacy `[profiles.<name>]` tables are not read. Project config and explicit command-line options can override a profile. See [profile format and precedence](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles).

Higher effort is a tradeoff to evaluate. Astra's model page includes `max`, but the Codex config reference's enum currently omits it; this repo keeps examples within their documented overlap. Use a client's supported model/effort selector for other levels and verify the effective choice. See the [Astra model page](https://developers.openai.com/api/docs/models/gpt-6-astra) and [Codex config reference](https://learn.chatgpt.com/docs/config-file/config-reference).

## Delegate with a useful handoff

Give a subagent a specific question or owned change, the necessary context, and a concrete deliverable. Reuse it for related follow-ups. The parent integrates results and handles work beyond a preset's scope. Ten concurrent threads is a capacity limit, not a performance recommendation. See [subagent workflows](https://learn.chatgpt.com/docs/agent-configuration/subagents).

For separate coding chats that may edit the same files, start each in a worktree (`codex --worktree`, or the app's worktree control). Within one shared checkout, assign disjoint files and serialize overlapping edits. Worktrees isolate files; sandbox permissions control access. See [Git worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees).

## Use current documentation when it matters

Consult official documentation for changing APIs, current model capabilities, configuration, and version-specific behavior. Keep ordinary code investigation focused on the repository rather than loading a documentation corpus on every task.

For frequent OpenAI work, the official Docs MCP is an optional public documentation connection:

```sh
codex mcp add openaiDeveloperDocs --url https://developers.openai.com/mcp
```

Review any existing server with that name before adding it. Pair it with the OpenAI Docs skill where available and start a new session. A suitable project instruction is: “For OpenAI API or Codex configuration questions, use official documentation and cite the relevant page; use the Docs MCP when it is available.” See [Docs MCP](https://developers.openai.com/learn/docs-mcp).

For other services, use a relevant authenticated connector, API, or CLI. Browser and computer-use capabilities depend on the client. Keep credentials and machine-specific commands out of this repository. See [MCP](https://learn.chatgpt.com/docs/extend/mcp).

## Keep reusable guidance small

Put personal working agreements in global `AGENTS.md`, repository commands and conventions in repository `AGENTS.md`, and a repeatable procedure in a focused skill. Skill descriptions should identify when they apply; detailed references should load as needed. Avoid stale, overlapping rules and unnecessary procedural scripts. See [Astra instruction guidance](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra).

Hooks, command rules, permission profiles, plugins, and memories solve different problems. Add one when a specific workflow needs it. Keep connector authorization and generated memory/session state local to its configured store. Stable skills can later be scheduled; the public installer does not create schedules. See [customization](https://learn.chatgpt.com/docs/customization/overview) and [scheduled tasks](https://learn.chatgpt.com/docs/automations).

## Measure improvements on your work

Documentation establishes supported behavior, not which configuration wins on your repositories. Compare the baseline with one change at a time on a small set of representative tasks:

| Task | What to measure |
| --- | --- |
| Known bug with a regression test | Correct fix, focused diff, passing relevant checks |
| Small feature with explicit acceptance criteria | Completed behavior, regressions, human corrections |
| Review of a change with known defects | Real defects found, false positives, evidence quality |
| API or configuration investigation | Correct version-specific answer and supporting primary sources |

Use the same starting commit, inputs, permissions, and tools. Record model/effort, elapsed time, usage when reported, and outcome quality. Repeat comparable tasks enough to account for variation. Keep any model-running benchmark opt-in because it uses account credits; installation tests and GitHub CI here make no model calls. See [model selection](https://developers.openai.com/api/docs/guides/model-selection).

For diagnostics, inspect `/status`, `/debug-config`, and `/agent` where available, and run `codex doctor`. Check the CLI and desktop versions separately. `--strict-config` is command-dependent and is not a complete schema validator in the inspected CLI build. See the [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli) and [troubleshooting](https://learn.chatgpt.com/docs/reference/troubleshooting).
