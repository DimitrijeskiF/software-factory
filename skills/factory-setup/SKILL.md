---
name: factory-setup
description: Sets up the Software Factory in the current project - detects the language and the commands for tests, lint, type check and build, and saves them in .factory/config.yml. Use when the user types /factory-setup, asks to set up or re-detect the factory for a project, or when /factory finds no config.
---

# Software Factory setup

Run this once per project. It writes `.factory/config.yml`, which every factory run reads,
so one factory works in any language.

1. Run `git rev-parse --show-toplevel`. If this isn't a git repo, tell the user the
   factory needs one (`git init` and a first commit) and stop.
2. If `.factory/config.yml` already exists, ask with AskUserQuestion:
   **Detect again** (keeps the current `models`, `review`, `limits` and `git` settings) /
   **Keep the current config** (stop here).
3. Dispatch the `software-factory:scout` agent with `model: sonnet`, and give it:
   - `REPO`: the repo root (absolute path)
   - `TEMPLATE`: `${CLAUDE_PLUGIN_ROOT}/skills/factory-setup/config-template.yml`
   - `OUTPUT`: `<repo>/.factory/config.yml`
   - `KEEP`: when detecting again, the current `models`, `review`, `limits` and `git` sections to copy over unchanged
4. Show the user what it found: the stack, each command with whether it ran cleanly,
   the test file patterns, and any notes. Then ask: **Looks right** /
   **I'll edit the file myself**. For the second option, give them the path and stop.
5. Make sure run folders stay out of git. If `.gitignore` doesn't already contain
   `.factory/*/`, append:

   ```
   # Software Factory run folders (config.yml and lessons.md stay tracked)
   .factory/*/
   ```
6. If `.factory/lessons.md` doesn't exist, create it:

   ```markdown
   # Factory lessons
   Read by every factory run in this project. Newest first. Keep it under 40 lines.
   ```
7. Tell the user setup is done, that `.factory/config.yml`, `.factory/lessons.md` and
   `.gitignore` are changed but not committed, and that they can now run `/factory <ticket>`.
