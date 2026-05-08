---
description: cmux 옆에 code-server(VSCode) split 패널을 띄워 현재 워크스페이스(또는 지정 경로)를 연다.
argument-hint: "[path]"
---

cmux split에 code-server 패널을 여는 `cmux-sidecar` 래퍼를 호출하라.

사용자 인자는 `$ARGUMENTS`로 전달된다. 단일 path(또는 빈 문자열)로 취급한다.

쉘 호출 규칙:
- `$ARGUMENTS`가 비어 있으면 정확히 `cmux-sidecar`를 실행한다.
- 아니면 `cmux-sidecar`에 `$ARGUMENTS`를 **단일 인자**로 전달한다. 작은따옴표로 감싸고 내부 작은따옴표는 `'\''`로 이스케이프한다. word-split 금지. `;`, 백틱, `$(...)`, `&&`가 인자 안에 있어도 셸에 노출되지 않게 한다.

래퍼가 반환한 surface ref 또는 에러 메시지를 그대로 보고하라. 그 외 부연 설명 금지.
