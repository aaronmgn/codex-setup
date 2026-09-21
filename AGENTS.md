# Repository instructions

This repository shares portable Codex settings. `codex/` contains the templates installed for users; the root `AGENTS.md` describes maintenance of this repository.

- Keep the bundled agent definitions and the role descriptions in `codex/AGENTS.md` and `README.md` consistent.
- Preserve unrelated destination config and instructions when changing the installer.
- Validate changes with `/bin/bash tests/test_install.sh`, using temporary destinations. Keep the installer and tests compatible with Bash 3.2 on macOS and Bash on Linux, without additional runtime dependencies.
- Never test an actual install against the contributor's live Codex home.
- Do not commit credentials, sessions, local plugin paths, trusted project lists, or installer backups.
- Use bounded subagent tasks for independent work and a read-only review after substantial installer changes.
