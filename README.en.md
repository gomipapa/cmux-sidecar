# cmux-sidecar

[한국어](README.md) · **English**

A sidecar VSCode panel for cmux — drop a code-server pane next to your AI agent (Claude Code, Codex) so you can read and edit the same workspace while the agent works.

It's not just a viewer; it's a real VSCode instance, so you can edit too. The project is essentially *an IDE-panel adapter for cmux + slash-command adapters for several AI coding tools (Claude Code, Codex, and more later)*.

## Requirements

- [`code-server`](https://coder.com/docs/code-server/install) — `install.sh` will offer a brew install if missing (with your consent)
- `cmux` (with `browser open-split` support) — install separately
- `curl`, `python3`, `zsh` — system tools (typically pre-installed)

`install.sh` only auto-installs `code-server` (and only with consent). Other dependencies are reported but not installed for you.

## Install

```sh
./install.sh                                     # interactive wizard
./install.sh --scope=global --tool=all
./install.sh --scope=project --project=$(pwd) --tool=claude-code
./install.sh --dry-run --scope=global            # preview
```

Flags:
- `--bin-prefix=PATH` — binary prefix (default `$HOME/.local`, resulting in `<prefix>/bin/cmux-sidecar`)
- `--scope=global|project` — adapter install scope
- `--project=PATH` — target project dir when `--scope=project` (default `$PWD`)
- `--tool=claude-code,codex,all` — adapters to install
- `--install-deps` / `--no-install-deps` — brew-install code-server when missing (interactive mode prompts; non-interactive skips by default)
- `--force` / `--no-clobber` — overwrite policy
- `--dry-run` — print actions without writing
- `-y, --yes` — skip the final confirmation prompt
- `--no-color` — disable ANSI colors

The interactive wizard supports arrow-key navigation (↑/↓ to move, Enter to select, 1-9 for quick select, q/ESC to abort). It falls back to a numbered menu when no TTY is available.

## Usage

- Claude Code: `/cmux-sidecar:sidecar [path]`
- Codex CLI: `/prompts:sidecar [path]`

`path` can be a file or directory. If a file, the parent folder is opened and the file is focused. If empty, the current workspace (`$PWD`) is opened.

## Environment variables

| Name | Default | Purpose |
|---|---|---|
| `CMUX_SIDECAR_URL` | `http://127.0.0.1:8765` | code-server URL |
| `CMUX_SIDECAR_USER_DATA` | `$HOME/.local/share/code-server` | code-server `--user-data-dir` |
| `CMUX_SIDECAR_LOG` | `/tmp/code-server.log` | lazy-start log path |
| `CMUX_SIDECAR_LOCK` | `/tmp/code-server.start.lockdir` | start lock directory |
| `CMUX_SIDECAR_START_TIMEOUT` | `15` | code-server boot wait (seconds) |

Legacy `CMUX_CODE_VIEWER_*` environment variables are also recognized as fallbacks.

## Migration (legacy users)

Users of the old `cmux-code-viewer` can manually remove the legacy assets after installing cmux-sidecar:

```sh
rm -f ~/.local/bin/cmux-code-viewer
rm -f ~/.claude/commands/code-viewer.md
```

## Uninstall

```sh
./uninstall.sh --scope=global
./uninstall.sh --scope=project --project=/path/to/project
```

Removes only the exact paths recorded in the install manifest at `~/.local/share/cmux-sidecar/installed-*.txt`.

## Troubleshooting

```sh
./doctor.sh
```

## License

MIT — see [LICENSE](LICENSE).
