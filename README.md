# cmux-sidecar

**한국어** · [English](README.en.md)

cmux 안에서 에이전트와 함께 일할 때 옆에 두는 VSCode 사이드카 패널 — code-server를 cmux split에 띄워주는 어댑터.

## 사전 요구사항

- [`code-server`](https://coder.com/docs/code-server/install) — `install.sh`가 부재 시 brew 설치 제안 (사용자 동의 필요)
- `cmux` (browser open-split 지원) — 별도 설치
- `curl`, `python3`, `zsh` — 시스템 기본 도구

`install.sh`는 code-server만 동의 시 brew로 자동 설치한다. 그 외 의존성은 안내 메시지만 출력하고 사용자가 직접 설치.

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
- `--install-deps` / `--no-install-deps` — 부재 시 code-server brew 설치 (대화형은 자동으로 묻고, 비대화형은 기본 skip)
- `--theme=NAME` — code-server 테마 (예: `"Default Dark Modern"`, `"Monokai"`)
- `--font-size=N` — 에디터 폰트 크기 (정수)
- `--no-config` — 외관(테마/폰트) 프롬프트 및 settings.json 변경 건너뜀
- `--force` / `--no-clobber` — 덮어쓰기 정책
- `--dry-run` — 실행하지 않고 출력만
- `-y, --yes` — 마지막 Proceed? 확인 건너뜀
- `--no-color` — ANSI 컬러 비활성화

대화형 마법사는 화살표 키 메뉴 (↑/↓ 이동, Enter 선택, 1-9 즉시 선택, q/ESC 취소). TTY 미사용 시 자동으로 번호 메뉴로 fallback.

테마/폰트를 지정하면 `<user-data-dir>/User/settings.json`에 머지되며, 기존 키는 보존된다 (해당 키만 덮어쓰기). 기본 user-data-dir은 `$HOME/.local/share/code-server` (`CMUX_SIDECAR_USER_DATA`로 변경 가능).

## 사용

- Claude Code: `/cmux-sidecar:sidecar [path]`
- Codex CLI: `/prompts:sidecar [path]`

`path`는 파일/디렉터리 모두 가능. 파일이면 부모 폴더를 열고 해당 파일을 띄운다. 비우면 현재 워크스페이스(`$PWD`)를 연다.

## 환경변수

| 이름 | 기본값 | 용도 |
|---|---|---|
| `CMUX_SIDECAR_URL` | `http://127.0.0.1:8080` | code-server URL (포트는 wrapper가 `--bind-addr`로 강제) |
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
./uninstall.sh --scope=global                            # 대화형
./uninstall.sh --scope=project --project=/path/to/project
./uninstall.sh --remove-code-server --remove-code-server-data  # 모두 제거
./uninstall.sh --keep-code-server --keep-code-server-data      # 어댑터만 제거
```

manifest(`~/.local/share/cmux-sidecar/installed-*.txt`)에 적힌 파일만 정확히 지운다. 그 다음 단계에서 code-server 자체(brew + 실행 프로세스)와 code-server 데이터 디렉터리(`~/.local/share/code-server`, `~/.config/code-server`, 로그·락)를 추가로 제거할지 묻는다.

플래그:
- `--remove-code-server` / `--keep-code-server` — code-server brew 제거 여부
- `--remove-code-server-data` / `--keep-code-server-data` — 데이터 디렉터리 제거 여부
- `--dry-run`, `-y, --yes`, `--no-color` — install.sh와 동일

## 트러블슈팅

```sh
./doctor.sh
```
