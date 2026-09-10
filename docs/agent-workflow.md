# Working with Claude Code and Codex

Both tools use [AGENTS.md](../AGENTS.md) for this project's conventions.
Codex reads it directly; [CLAUDE.md](../CLAUDE.md) imports it with `@AGENTS.md`.
Change shared instructions in AGENTS.md so a correction reaches both tools.
The existing Haskell, geometry, documentation and PR rules apply to either.

## Start a session

Open the repository root in either tool, with the toolchain from
[usage.md](usage.md#building) available. Give the agent the issue, the desired
result and any constraints. Ask it to inspect the branch and working tree before
editing. Build and check commands are in [AGENTS.md](../AGENTS.md#commands).

After changing instruction files, start a fresh session. In Codex, ask it to
summarize the active project instructions. In Claude Code, use `/memory` to
inspect loaded files, then ask for the same summary. Both should identify
AGENTS.md, the Stack toolchain and the PR checks. This checks instruction
discovery; the normal code review and CI still check the work itself.

Keep personal preferences in each tool's user configuration. Claude Code's
`CLAUDE.local.md` and `.claude/settings.local.json` are ignored here. Keep local
Codex preferences in `~/.codex/config.toml` and `~/.codex/AGENTS.md`. A project
`AGENTS.override.md` takes precedence over AGENTS.md in that directory, so it
is unsuitable for ordinary personal additions to the shared rules.

## Switch tools on one task

Stop the first agent before letting the next edit the same checkout. Commit a
coherent checkpoint when possible, and give the next agent a handoff like this:

```text
Continue issue #<number> on branch <branch>, PR <URL if opened>.
Completed: <what changed and why>.
Working tree: <uncommitted files and who owns them, or clean>.
Verified: <exact commands and outcomes, including failures or skipped checks>.
Remaining: <next step and unresolved questions>.
Read the diff and relevant module headers before continuing.
```

Chat history and private agent memory do not travel with a Git branch. Put
lasting decisions in the module header or relevant documentation, following
[the documentation rules](../AGENTS.md#docs), and keep task progress in the
issue or PR. A handoff is a report of the current work, not another copy of the
project conventions.

## Work on two tasks at once

A Git worktree is a separate working directory backed by the same repository.
Use a different branch and worktree for each concurrent task: two agents in one
checkout can overwrite files or change the branch underneath each other.
For example, from the repository root, with these new branch and directory
names unused:

```bash
git fetch origin
git worktree add ../senbazuru-claude -b docs/claude-task origin/main
git worktree add ../senbazuru-codex -b codex/second-task origin/main
```

Open each tool in its corresponding directory. Each worktree has its own
uncommitted files and build output; allow Stack to build there before expecting
tests to run. Keep changes small and integrate through the existing PR workflow.
For a review of unfinished work, provide the diff or a committed checkpoint;
another worktree does not contain the first one's uncommitted edits.

## Why these entry points

[Codex discovers AGENTS.md automatically](https://developers.openai.com/codex/guides/agents-md),
and [Claude Code supports importing it](https://code.claude.com/docs/en/memory#agentsmd).
A small import file avoids duplicate rules and works without symlink support
or a per-user fallback filename setting. Keep the shared instructions focused:
Codex's default combined instruction limit is 32 KiB, and imported text also
uses Claude's context. Link to detailed explanations instead of copying them.
