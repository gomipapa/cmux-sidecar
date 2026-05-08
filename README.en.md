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
- `--theme=NAME` — code-server VSCode theme (e.g. `"Default Dark Modern"`, `"Monokai"`)
- `--font-size=N` — editor font size (integer)
- `--no-config` — skip the appearance prompt and settings.json write
- `--auth=none|password` — code-server auth mode (default `none`, since the wrapper binds to 127.0.0.1 only)
- `--force` / `--no-clobber` — overwrite policy
- `--dry-run` — print actions without writing
- `-y, --yes` — skip the final confirmation prompt
- `--no-color` — disable ANSI colors

The interactive wizard supports arrow-key navigation (↑/↓ to move, Enter to select, 1-9 for quick select, q/ESC to abort). It falls back to a numbered menu when no TTY is available.

If you set a theme or font size, the values are merged into `<user-data-dir>/User/settings.json` (existing keys are preserved; only the affected keys are overwritten). The default user-data-dir is `$HOME/.local/share/code-server` (override via `CMUX_SIDECAR_USER_DATA`).

## Usage

- Claude Code: `/cmux-sidecar:sidecar [path]`
- Codex CLI: `/prompts:sidecar [path]`

`path` can be a file or directory. If a file, the parent folder is opened and the file is focused. If empty, the current workspace (`$PWD`) is opened.

## Environment variables

| Name | Default | Purpose |
|---|---|---|
| `CMUX_SIDECAR_URL` | `http://127.0.0.1:8765` | code-server URL (the wrapper enforces this port via `--bind-addr`; chosen to avoid the crowded 8080 dev port) |
| `CMUX_SIDECAR_USER_DATA` | `$HOME/.local/share/code-server` | code-server `--user-data-dir` |
| `CMUX_SIDECAR_LOG` | `/tmp/code-server.log` | lazy-start log path |
| `CMUX_SIDECAR_LOCK` | `/tmp/code-server.start.lockdir` | start lock directory |
| `CMUX_SIDECAR_START_TIMEOUT` | `15` | code-server boot wait (seconds) |

Legacy `CMUX_CODE_VIEWER_*` environment variables are also recognized as fallbacks.

## Uninstall

```sh
./uninstall.sh --scope=global                                  # interactive
./uninstall.sh --scope=project --project=/path/to/project
./uninstall.sh --remove-code-server --remove-code-server-data  # nuke everything
./uninstall.sh --keep-code-server --keep-code-server-data      # adapters only
```

The uninstaller first removes only the exact paths recorded in the install manifest at `~/.local/share/cmux-sidecar/installed-*.txt`. It then asks (interactively) whether to also brew-uninstall code-server and remove its data dirs (`~/.local/share/code-server`, `~/.config/code-server`, logs, lock dirs).

Flags:
- `--remove-code-server` / `--keep-code-server` — brew-uninstall code-server
- `--remove-code-server-data` / `--keep-code-server-data` — wipe data dirs
- `--dry-run`, `-y, --yes`, `--no-color` — same as install.sh

## Troubleshooting

```sh
./doctor.sh
```

## License

MIT — see [LICENSE](LICENSE).
