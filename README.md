# cmux-sidecar

cmux 안에서 에이전트와 함께 일할 때 옆에 두는 VSCode 사이드카 패널 — code-server를 cmux split에 띄워주는 어댑터.

## 사전 요구사항

- [`code-server`](https://coder.com/docs/code-server/install) (`brew install code-server`)
- `cmux` (browser open-split 지원)
- `curl`, `python3`, `zsh`

자동 설치는 하지 않는다. 의존성이 없으면 사용 시점에 안내 메시지만 출력된다.

## 설치

```sh
./install.sh                                     # 대화형 (scope/tool 질문)
./install.sh --scope=global --tool=all
./install.sh --scope=project --project=$(pwd) --tool=claude-code
./install.sh --dry-run --scope=global            # 미리보기
```

플래그:
- `--bin-prefix=PATH` — 바이너리 prefix (기본 `$HOME/.local`, 결과: `<prefix>/bin/cmux-sidecar`)
- `--scope=global|project` — 어댑터 설치 범위
- `--project=PATH` — `--scope=project`일 때 대상 디렉터리 (기본 `$PWD`)
- `--tool=claude-code,codex,all` — 설치할 어댑터
- `--force` / `--no-clobber` — 덮어쓰기 정책
- `--dry-run` — 실행하지 않고 출력만

## 사용

- Claude Code: `/cmux-sidecar:sidecar [path]`
- Codex CLI: `/prompts:sidecar [path]`

`path`는 파일/디렉터리 모두 가능. 파일이면 부모 폴더를 열고 해당 파일을 띄운다. 비우면 현재 워크스페이스(`$PWD`)를 연다.

## 환경변수

| 이름 | 기본값 | 용도 |
|---|---|---|
| `CMUX_SIDECAR_URL` | `http://127.0.0.1:8765` | code-server URL |
| `CMUX_SIDECAR_USER_DATA` | `$HOME/.local/share/code-server` | code-server `--user-data-dir` |
| `CMUX_SIDECAR_LOG` | `/tmp/code-server.log` | lazy-start 시 로그 경로 |
| `CMUX_SIDECAR_LOCK` | `/tmp/code-server.start.lockdir` | 시작 락 디렉터리 |
| `CMUX_SIDECAR_START_TIMEOUT` | `15` | code-server 기동 대기 (초) |

구버전 `CMUX_CODE_VIEWER_*` 환경변수도 fallback으로 인식한다.

## 마이그레이션 (구버전 사용자)

기존 `cmux-code-viewer`를 쓰던 사용자는 새 설치 후 다음 파일을 수동 제거하면 된다:

```sh
rm -f ~/.local/bin/cmux-code-viewer
rm -f ~/.claude/commands/code-viewer.md
```

## 제거

```sh
./uninstall.sh --scope=global
./uninstall.sh --scope=project --project=/path/to/project
```

설치 시 기록한 manifest(`~/.local/share/cmux-sidecar/installed-*.txt`)에 적힌 파일만 정확히 지운다.

## 트러블슈팅

```sh
./doctor.sh
```
