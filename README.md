# Codex setup

My shared Codex setup: a main agent that owns the work, three focused subagents, and global instructions to delegate useful work proactively.

| Role | Model | Reasoning | Job |
| --- | --- | --- | --- |
| Main | `gpt-6-astra` | `xhigh` | Requirements, coordination, integration, and final validation |
| Explorer | `gpt-5.6-luna` | `medium` | Read-only codebase investigation |
| Worker | `gpt-5.6-terra` | `high` | Implementation and focused checks |
| Reviewer | `gpt-5.6-sol` | `high` | Independent, read-only correctness and security review |

The config allows up to **10 concurrent subagent threads**, a ceiling rather than a target. The instructions keep small tasks with the main agent and give delegated work a clear scope, file ownership, and expected result.

The main config sets `model_context_window = 1000000` and `model_auto_compact_token_limit = 900000`. Both are documented Codex settings, and the window is within Astra's published 1,050,000-token context limit. Recheck these overrides when changing models; they do not expand a model's supported limits. See the [config reference](https://learn.chatgpt.com/docs/config-file/config-reference) and [Astra model page](https://developers.openai.com/api/docs/models/gpt-6-astra).

Reviewed against the official documentation on **2026-09-20**. See the [audit and decisions](docs/setup-audit.md), [source inventory](docs/documentation-sources.md), and [workflow guide](docs/workflows.md). Model defaults are intentional choices, not a guarantee of best performance on every task.

## Install

The installer runs with the Bash and standard filesystem utilities included with macOS and Linux. It requires Bash 3.2 or newer, with no additional packages or language runtimes. You need Git to clone the repository and a Codex client that supports custom agents in `~/.codex/agents/` to use the setup.

```sh
git clone https://github.com/aaronmgn/codex-setup.git
cd codex-setup
bash install.sh --dry-run
bash install.sh
```

Review the model choices above before installing. They reproduce this setup; choose models and reasoning levels available to your account if needed. Edit the files under `codex/` as described below.

Start a new Codex session after installing. Codex loads global guidance from its home directory and discovers personal agent definitions under its `agents/` directory. See the official [AGENTS.md documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md) and [custom agent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents).

## What the installer changes

The destination is `$CODEX_HOME`, or `~/.codex` when that variable is unset. You can select another destination with `--codex-home`:

```sh
bash install.sh --codex-home ./preview-codex
```

| Source in this repo | Destination | Behavior |
| --- | --- | --- |
| `codex/config.toml` | `config.toml` | Merge the main model, reasoning effort, context window, compaction threshold, and concurrency setting; preserve unrelated settings and comments |
| `codex/AGENTS.md` | `AGENTS.md` | Add or update a marked block; preserve instructions outside it |
| `codex/agents/*.toml` | `agents/*.toml` | Install or replace the three named presets; leave other presets alone |

Existing files that change are backed up under `<Codex home>/backups/codex-setup/<unique directory>/`, with their relative paths intact. The installer prints the backup location. Backup directories are private and files are readable and writable only by their owner. Repeating an install with the same inputs makes no further changes. `--dry-run` previews file changes without writing to the destination.

The Bash scanner handles common TOML forms, including quoted/dotted keys, comments, multiline strings, arrays, and arrays of tables. Managed values must fit on one line. Unsupported forms, such as escaped quoted keys, and incompatible managed table shapes are rejected before writing. The scanner checks string/container structure and managed keys; it is not a full TOML semantic validator. Codex still validates its configuration.

Conflicting managed-block markers, symlinks at or within the chosen Codex home, and incompatible file types are also rejected before writing. Ancestors outside the chosen home may be symlinks, such as macOS's `/var` alias. Each file is written atomically; the complete install is not a single filesystem transaction. If an I/O failure interrupts it, use the printed backup directory to recover changed files.

The shared config contains model, context, and concurrency preferences. Plugins, MCP servers, notification commands, desktop preferences, trusted project paths, credentials, and session history stay local. The installer preserves existing unrelated config, including any model-provider or agent-enable settings; reconcile those if they conflict with the bundled models or delegation behavior.

## Customize

- Change the main model, reasoning effort, context limits, or thread limit in [`codex/config.toml`](codex/config.toml).
- Change a subagent's model, reasoning, permissions, or instructions in its file under [`codex/agents/`](codex/agents/).
- Adjust working agreements, delegation, and validation in [`codex/AGENTS.md`](codex/AGENTS.md). Preset files own model settings; keep the README's model table aligned when changing them.
- Run the installer again to apply your edits. It copies files, so editing the clone alone does not change your active setup.

The instructions use the active Codex home, so a custom `CODEX_HOME` does not require editing them.

Explorer and reviewer request `read-only` sandboxes; worker requests `workspace-write`. Runtime and organization policies can affect effective permissions. The global instructions also require exploration and review to remain read-only.

To copy this manually, merge the values from `codex/config.toml` into your existing config, incorporate `codex/AGENTS.md` into your global instructions, and copy the three preset files to your Codex home's `agents/` directory.

## Optional workflows

The [workflow guide](docs/workflows.md) covers separate CLI profiles for quick work and explicit reviews, worktree isolation, current documentation lookup, and a small evaluation plan. The examples under [`examples/profiles/`](examples/profiles/) are installed manually; the default installer only manages the files listed above.

The built-in `/review` command uses the session model unless `review_model` overrides it. It does not load the custom `reviewer` preset's instructions or sandbox. Ask for that named subagent when you want its role-specific behavior. See [code review](https://learn.chatgpt.com/docs/code-review) and [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).

## Update or undo

Pull changes into your clone, review them, then rerun the installer. If you customize the templates, keep those edits in your own fork or commits.

To undo an installation, restore the affected files from the printed backup directory. If a destination file was newly created, it has no backup: remove only that installed file. For an `AGENTS.md` with other instructions, you can remove the marked `codex-setup` block. Compare backups with the current files before restoring if you have made subsequent edits.

## Verify

```sh
/bin/bash tests/test_install.sh
```

Tests use temporary directories and cover new installs, merging existing settings and instructions, backups, repeat installs, dry runs, and invalid destinations.

In a new Codex session, ask it to list its available agent presets and explain the global delegation instructions. A non-empty `AGENTS.override.md` in your Codex home takes precedence over `AGENTS.md`; more specific project instructions also take precedence. The combined project-instruction budget defaults to 32 KiB, so keep mandatory guidance short and put detailed workflows in focused references. See [instruction discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

The source setup was inspected with Codex CLI `0.155.1`. Local installer tests do not establish that every account has access to these models or that every client honors the same runtime permissions.

## License

[MIT](LICENSE). Fork it and adapt it to your workflow.
