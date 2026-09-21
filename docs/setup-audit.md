# Setup audit — 2026-09-20

The existing model selection and standalone agent format are current. The useful changes are more precise working instructions and optional workflows. We found no documentation basis for replacing every agent with the largest model, increasing concurrency, or enabling every experimental feature.

## Coverage and limits

The audit used the current consolidated official Codex manual: **40,644 lines, 179 source sections, 176 unique source URLs**. Topic-specific research agents covered the entire manual, including the security, plugin, automation, platform, and enterprise sections. The model review covered the catalog, the four selected models, current model guidance, reasoning/model-selection guidance, and the Astra skills article. The [source inventory](documentation-sources.md) records the pages and the manual snapshot hash.

This is a documentation and local compatibility audit. It is not a performance benchmark, proof of model access on every account, or a review of every specialized or historical OpenAI API model guide. The exact client, account, tools, permissions, and task still determine effective behavior.

## Model and configuration decisions

| Item | Decision | Reason |
| --- | --- | --- |
| Main: Astra / `xhigh` | Keep | Current flagship; preserves the existing preference for demanding work |
| Explorer: Luna / `medium` | Keep | Bounded evidence gathering fits the smaller tier |
| Worker: Terra / `high` | Keep | Fits scoped implementation with the parent available for harder work |
| Reviewer: Sol / `high` | Keep | Preserves the existing stronger independent review tier |
| Ten subagent threads | Keep as ceiling | Spawn according to independent work, not available slots |
| Context and compaction limits | Set to 1,000,000 and 900,000 tokens | Explicit user preference; both documented settings, within Astra's published context window |
| Generic subagent fallback | Leave unset | Named presets already pin model and effort |

The tiering is our engineering judgment based on the [current model catalog](https://developers.openai.com/api/docs/models), the [Astra](https://developers.openai.com/api/docs/models/gpt-6-astra), [Luna](https://developers.openai.com/api/docs/models/gpt-5.6-luna), [Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra), and [Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) pages. It has not been shown optimal by a controlled comparison. Inheritance and the concurrency limit are documented under [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents); compaction controls are in the [config reference](https://learn.chatgpt.com/docs/config-file/config-reference).

The context decision was updated after the initial audit at the user's request: `model_context_window = 1000000` and `model_auto_compact_token_limit = 900000`. The config reference defines both numeric settings; Astra publishes a 1,050,000-token context window. These overrides do not increase provider limits and should be revisited when changing models. The compaction threshold is a trigger for automatic history compaction, not a promise of exactly that many usable input tokens. See the [config reference](https://learn.chatgpt.com/docs/config-file/config-reference) and [Astra model page](https://developers.openai.com/api/docs/models/gpt-6-astra).

## Changes made

- Made the preset directory reference honor `CODEX_HOME`, and made preset files the source of truth for model choices.
- Preserved the user's explicit preference for proactive delegation while improving scoped handoffs, follow-up reuse, and escalation to the parent.
- Added concise completion and validation guidance, including when to stop repeating checks.
- Tightened explorer, worker, and reviewer instructions around evidence, assigned ownership, and useful findings.
- Added optional separate-file CLI profiles for Astra/high and Sol/high review sessions, plus a workflow and evaluation guide.
- Replaced the Python installer and package dependencies with a Bash 3.2 installer and Bash tests for macOS and Linux.

These changes address the documented Astra behavior around persistence, instruction sensitivity, delegation, and excessive testing. They preserve intentional user preferences while keeping the instructions focused. See [current model guidance](https://developers.openai.com/api/docs/guides/latest-model), [Astra skills and prompts](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra), and [profile configuration](https://learn.chatgpt.com/docs/config-file/config-advanced#profiles).

## Important distinctions

**Built-in review and the reviewer preset are separate.** `/review` uses the current session model unless `review_model` changes it. It does not load the custom preset's instructions or sandbox. The optional review profile changes the built-in review model; naming the reviewer subagent activates the preset. See [code review](https://learn.chatgpt.com/docs/code-review).

**Agent sandbox settings are defaults, not an absolute boundary against parent overrides.** Live parent permission choices can be reapplied to children. The role instructions still require read-only investigation and review. The public setup does not change global approval or sandbox policy. See [subagent permissions](https://learn.chatgpt.com/docs/agent-configuration/subagents) and [agent approvals](https://learn.chatgpt.com/docs/agent-approvals-security).

**The docs contain some inconsistent tables.** The config reference lists reasoning values through `xhigh`, while the current Astra API page includes `max`. Some general subagent prose still recommends `gpt-5.6`, while the current catalog identifies Astra as the flagship. We retained the valid existing model IDs and kept portable examples within the documented effort overlap. See [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference), [Astra](https://developers.openai.com/api/docs/models/gpt-6-astra), and [model catalog](https://developers.openai.com/api/docs/models).

**API features are not Codex TOML settings.** Async tools, cache options, Responses configuration updates, and API compaction require the appropriate API/runtime integration. They should not be pasted into this config. See [model guidance](https://developers.openai.com/api/docs/guides/latest-model).

## Useful options kept explicit

| Option | Appropriate use |
| --- | --- |
| OpenAI Docs MCP | Frequent OpenAI API/configuration work; see the [connection instructions](workflows.md#use-current-documentation-when-it-matters) |
| Fast mode | A deliberate latency/credit tradeoff using the client's supported control |
| Worktrees | Independent coding chats whose edits might overlap |
| Skills and plugins | Stable, repeated workflows with precise triggers |
| Hooks, rules, permission profiles | A concrete enforcement need after compatibility and trust review |
| Scheduled tasks / Codex in CI | A workflow already reliable manually, with explicit account usage and permissions |

Fast mode availability and billing depend on model and authentication; the shareable config does not opt everyone into it. Permission profiles are documented as beta and do not compose with legacy sandbox settings. See [speed](https://learn.chatgpt.com/docs/agent-configuration/speed) and [permissions](https://learn.chatgpt.com/docs/permissions).

The existing installer remains appropriate for sharing global configuration and agent TOMLs. Plugin packaging is useful for skills, tools, and integrations, but the documented plugin components do not replace global config installation. Enterprise policy, provider setup, generated memory, connector credentials, and local desktop state remain outside the public bundle. See [plugin structure](https://developers.openai.com/plugins/build/plugins#plugin-structure) and [managed configuration](https://learn.chatgpt.com/docs/enterprise/managed-configuration).

## Verification

Validation uses `/bin/bash tests/test_install.sh` in temporary directories, with GitHub CI running on macOS and Linux. The installer and test suite need no Python environment or package installation.

The inspected CLI is `0.155.1`. Its app-server `config/read` accepted the shared config in a temporary Codex home and returned `model_context_window: 1000000` and `model_auto_compact_token_limit: 900000`. This was a local configuration check with no model turn. Profile support is exposed by `--profile`, while `doctor` does not accept that flag. Config inspection commands alone do not establish that an effort value is supported by the active model. No paid model evaluations are part of the test suite. Use the [evaluation plan](workflows.md#measure-improvements-on-your-work) before claiming a configuration is faster, cheaper, or more accurate.
