# 기능과 설정

첫 화면을 짧게 두려고 [README](../../README.ko.md)에서 옮겼습니다. English: [FEATURES.md](FEATURES.md).

## 토큰 최적화

규칙과 스킬은 필요할 때만 로드됩니다 — 현재 작업에 관련된 것만 컨텍스트에 로드됩니다. 별도 설정이 필요 없습니다.

### 레퍼런스 문서 로드

상세 레퍼런스 문서는 자동 로드되는 `.claude/rules/` 트리 밖의 `.claude/reference/`에 위치하므로 초기 컨텍스트에 주입되지 않습니다. 필요할 때 로드하세요:

```markdown
# 특정 레퍼런스 로드 요청
@load: reference/agent-teams

# 또는 파일을 직접 참조
.claude/reference/workflow/label-definitions.md를 검토해주세요.
```

고급 커스터마이징은 [docs/TOKEN_OPTIMIZATION.md](../../docs/TOKEN_OPTIMIZATION.md)를 참조하세요.

## 자동으로 적용되는 동작

설치 직후 별도의 설정 없이 자동으로 활성화되는 동작입니다.

### 코드를 편집할 때
- 사용 중인 언어에 맞게 파일이 자동 포맷됩니다 (Python, TypeScript, Go, Rust, C++, Kotlin)
- 지원 포매터: `black`, `prettier`, `gofmt`, `rustfmt`, `clang-format`, `ktlint`

### 커밋할 때
- 마크다운 상호 참조 앵커가 검증됩니다 — 깨진 링크는 커밋을 차단합니다
- 커밋 메시지 형식이 확인됩니다 (Conventional Commits)
- AI/Claude 어트리뷰션이 자동으로 제거됩니다
- 커밋 / PR / 이슈 내용이 선택된 `CLAUDE_CONTENT_LANGUAGE` 정책으로 검증됩니다 (아래 [컨텐츠 언어 정책](#컨텐츠-언어-정책) 참조)

### Claude가 파일에 접근할 때
- `.env`, `.pem`, `.key` 및 `secrets/` 디렉토리 접근이 차단됩니다
- 위험한 명령어 (`rm -rf /`, `chmod 777`, 파이프 실행)가 차단됩니다
- GitHub API 호출 전 연결이 검증됩니다

### 세션이 실행될 때
- 세션 시작/종료 시간이 `~/.claude/session.log`에 기록됩니다
- 알려진 문제가 있는 Claude Code 버전에 대해 경고가 표시됩니다
- 세션 종료 시 오래된 임시 파일이 정리됩니다
- 자동 압축 전 컨텍스트가 스냅샷됩니다

### PR을 생성할 때
- `develop` 외 브랜치에서 `main`을 타겟하는 PR이 차단됩니다 (PreToolUse hook)
- 서버 측: GitHub Actions가 위반 PR을 자동으로 닫고 안내 코멘트를 남깁니다
- 릴리즈 PR (`develop` → `main`)은 `/release` 스킬을 통해 허용됩니다

### Agent Teams 사용 시
- 동시 팀 수가 제한됩니다 (`MAX_TEAMS`로 설정 가능)
- 팀원의 유휴 이벤트와 작업 완료가 기록됩니다
- Worktree 생성 및 정리가 자동으로 관리됩니다

> 전체 Hook 설정 세부사항 및 커스터마이징은 [HOOKS.md](../../HOOKS.md)를 참조하세요.

### 컨텐츠 언어 정책

두 installer (`install.sh`, `install.ps1`)는 설치 타입 선택 후에 세 옵션 Language Profile Preset을 묻습니다. 산출물 언어 정책은 아래 고정 언어로 매핑됩니다:

| UI 선택 | `CLAUDE_CONTENT_LANGUAGE` 값 | 검증자가 수용하는 범위 | 규칙 문서 phrase |
|---------|------------------------------|----------------------|-----------------|
| English (기본) | `english` | ASCII printable + whitespace 및 허용된 English typographic punctuation | `English` |
| Korean | `exclusive_bilingual` | 산출물 단위로 영어 전용 또는 한국어 전용 (제한된 ASCII container 허용), 인라인 혼용 금지 | `English or Korean (document-exclusive)` |

검증자는 UI에 노출되지 **않는** 두 레거시 값도 추가로 수용합니다 — 필요 시 `settings.json` 직접 편집으로 설정합니다:

| 레거시 값 | 사용 시점 | 검증자가 수용하는 범위 |
|-----------|-----------|----------------------|
| `korean_plus_english` | issue #447 이전 설치 호환 (인라인 혼용 의존 시) | ASCII + 한글 음절 / 자모 / 호환 자모 |
| `any` | 모든 언어 기여를 받는 OSS 저장소 | 언어 검증 전체 생략 |

Installer는 선택된 phrase를 세 규칙 문서 템플릿 (`global/commit-settings.md.tmpl`, `project/.claude/rules/core/communication.md.tmpl`, `project/.claude/rules/workflow/git-commit-format.md.tmpl`)에 치환합니다. 규칙 문서의 표현과 검증자의 실제 동작이 일치하도록 유지합니다.

재설치 시 prompt 기본값은 기존 `settings.json`에서 seed되어 이전 `.language`와 `CLAUDE_CONTENT_LANGUAGE` 선택을 유지합니다. 명시적인 `AGENT_LANGUAGE` 및 `CONTENT_LANGUAGE` 환경 변수 override가 있으면 그 값이 우선합니다.

**스코프 경계**: AI/Claude 어트리뷰션 차단은 이 env var의 영향을 **받지 않습니다** — `attribution-guard`와 `commit-message-guard` 내부의 attribution 검사는 모든 정책에서 그대로 작동합니다.

**Enterprise 충돌 감지**: 배포된 enterprise `CLAUDE.md`가 영어를 강제하는데 운영자가 더 허용적인 정책을 선택하면, installer가 경고를 출력하고 진행 전에 확인을 요청합니다.

자세한 설계 배경, phrase 테이블, 드리프트 검증 불변식은 [`docs/content-language-policy.md`](../../docs/content-language-policy.md)를 참조하세요.

## Rules

Rules는 `.claude/rules/`에 있는 모듈형 설정 파일로, 파일 경로에 따라 조건부로 로드됩니다.

### 사용 가능한 Rules

| Rule | 자동 로드 대상 | 설명 |
|------|---------------|------|
| `coding.md` | `**/*.ts`, `**/*.py`, `**/*.go` 등 | 일반 코딩 표준 |
| `testing.md` | `**/*.test.ts`, `**/test_*.py` 등 | 테스트 관례 |
| `security.md` | 모든 코드 파일 | 보안 모범 사례 |
| `documentation.md` | `**/docs/**`, `**/README*`, `**/CHANGELOG*` | 문서화 표준 |
| `api/rest-api.md` | `**/api/**`, `**/routes/**` | REST API 설계 패턴 |

### Rules 작동 방식

Rules는 YAML frontmatter에 `paths`를 사용하여 로드 시점을 정의합니다:

```yaml
---
alwaysApply: false
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# Rule 내용
```

이 패턴과 일치하는 파일을 작업할 때 해당 Rule이 자동으로 로드됩니다.

## 스킬 — 무엇을 할 수 있나요

스킬 호출 방식은 두 가지입니다.

1. **슬래시 카탈로그 스킬** (`/code-quality`, `/security-audit`, `/performance-review`, `/pr-review`, `/git-status` 및 아래의 `plugin/` 스킬들) — `~/.claude/skills/`의 1단계 폴더로 위치하며 Claude Code의 `/` 자동완성 카탈로그에 노출됩니다. 명령어를 입력하면 하네스가 디스패치합니다.
2. **키워드 별칭(alias) 스킬** (`/issue-work`, `/pr-work`, `/release`, `/issue-create`, `/branch-cleanup`, `/harness`, `/doc-index`, `/doc-review`, `/implement-all-levels`) — 의도적으로 `~/.claude/skills/_internal/` 하위에 격리되고 frontmatter에 `disable-model-invocation: true`가 적용되어 **`/` 자동완성 카탈로그에 노출되지 않습니다**. 메시지를 키워드로 시작하면 `global/CLAUDE.md`의 **Skill Aliases** 표가 매핑하여 실행합니다 (앞의 `/`는 선택사항). `issue-work`, `/issue-work` 둘 다 동작하지만 탭 자동완성은 제안되지 않습니다.

아래 표에 각 명령의 호출 모드를 표시합니다.

### 워크플로우 자동화

이 그룹의 모든 명령은 **키워드 별칭** 호출입니다 (슬래시 자동완성 없음, alias 표가 처리).

| 명령어 | 기능 |
|--------|------|
| `/issue-work` | GitHub 이슈 선택, 브랜치 생성, 구현, 테스트, PR 생성 |
| `/pr-work` | 실패한 CI 체크 진단, 수정, 재시도, 필요시 에스컬레이션 |
| `/release` | 커밋에서 변경 로그 생성, 태그된 릴리스 생성 |
| `/issue-create` | 5W1H 프레임워크를 사용한 체계적인 GitHub 이슈 생성 |
| `/branch-cleanup` | 로컬 및 원격에서 병합된 브랜치와 오래된 브랜치 제거 |

### 코드 분석

| 명령어 | 기능 |
|--------|------|
| `/code-quality` | 복잡도, 코드 스멜, SOLID 위반, 유지보수성 분석 |
| `/security-audit` | OWASP Top 10, 입력 검증, 인증, 의존성 취약점 |
| `/performance-review` | 프로파일링, 캐싱, 메모리 누수, 동시성 패턴 |
| `/pr-review` | 품질, 보안, 성능, 테스트를 다루는 PR 분석 |

### 설계 및 문서화

`/git-status`는 슬래시 카탈로그 스킬, 나머지는 키워드 별칭입니다.

| 명령어 | 모드 | 기능 |
|--------|------|------|
| `/harness` | keyword | Agent team 설계 및 모든 도메인에 대한 스킬 생성 |
| `/doc-index` | keyword | 문서 인덱스 파일 생성 (manifest, bundles, graph, router) |
| `/doc-review` | keyword | 정확성, 앵커, 상호 참조에 대한 마크다운 문서 리뷰 |
| `/git-status` | slash | 실행 가능한 인사이트가 포함된 저장소 상태 |
| `/implement-all-levels` | keyword | 계층형 기능의 모든 티어에 대한 완전한 구현 강제 |

## Agents

`.claude/agents/`에 있는 특수 에이전트가 특정 작업에 집중된 지원을 제공합니다.

### 사용 가능한 Agents

| Agent | 설명 | Model |
|-------|------|-------|
| `code-reviewer` | 품질, 보안, 성능, 유지보수성을 다루는 코드 리뷰 | sonnet |
| `documentation-writer` | 기술 문서 작성 | sonnet |
| `refactor-assistant` | 안전한 코드 리팩토링 | sonnet |
| `codebase-analyzer` | 코드베이스 아키텍처 및 패턴 분석 | sonnet |
| `qa-reviewer` | 통합 일관성 검증 | sonnet |
| `structure-explorer` | 프로젝트 디렉토리 구조 매핑 | haiku |
| `dependency-auditor` | 의존성 CVE 및 라이선스 감사 | sonnet |
| `test-strategist` | 테스트 커버리지 및 전략 분석 | sonnet |

### Agent 설정

Agents는 YAML frontmatter로 동작을 정의합니다:

```yaml
---
name: agent-name
description: 에이전트의 역할
model: sonnet
tools: Read, Edit
---
```

## Agent Teams

Agent Teams는 여러 Claude 인스턴스가 공유 작업 목록과 다이렉트 메시징을 통해 병렬로 작업할 수 있게 합니다.

> **상태**: 실험적. 이 설정에 이미 활성화되어 있습니다.

### 빠른 시작

자연어로 팀을 시작하세요:

```
Create a team to implement the notification system:
- Teammate "backend": API endpoints
- Teammate "frontend": UI components
- Teammate "tests": Integration tests
```

키 조작과 표시 방식은 이 저장소가 아니라 Claude Code가 정합니다. 공식 [agent teams 문서](https://code.claude.com/docs/en/agent-teams)를 참조하세요.

최적의 조정을 위해 팀을 2-3명으로 유지하세요. 파일 충돌을 피하기 위해 각 팀원에게 별도의 파일 세트를 할당하세요.

아키텍처 패턴, 표시 모드, 훅, 고급 설정은 `.claude/reference/workflow/agent-teams.md`를 참조하세요.

## MCP 설정

`.mcp.json` 템플릿은 일반적인 MCP 서버 설정을 제공합니다.

### 사용 가능한 서버

| 서버 | 설명 |
|------|------|
| `filesystem` | 파일 시스템 접근 |
| `github` | GitHub 연동 |
| `postgres` | PostgreSQL 데이터베이스 접근 |
| `slack` | Slack 메시징 |
| `memory` | 영구 메모리 저장소 |

### 설정 방법

1. `.mcp.json`을 프로젝트 루트에 복사
2. 토큰에 대한 환경 변수 설정
3. 사용하지 않는 서버 제거

## 스크립트 설명

| 스크립트 | 목적 | 사용법 |
|----------|------|--------|
| `install.sh` / `.ps1` | 새 시스템에 설정 설치 | `./scripts/install.sh` |
| `backup.sh` / `.ps1` | 현재 설정을 백업에 저장 | `./scripts/backup.sh` |
| `sync.sh` / `.ps1` | 시스템과 백업 간 양방향 동기화 | `./scripts/sync.sh` |
| `verify.sh` / `.ps1` | 백업 무결성과 완전성 확인 | `./scripts/verify.sh` |
| `validate_skills.sh` / `.ps1` | SKILL.md 형식 준수 여부 검증 | `./scripts/validate_skills.sh` |

설치 후 `~/.claude/git-identity.md`는 `git config --global user.name` 및 `git config --global user.email` 값이 모두 있으면 자동으로 채워집니다. 값이 누락되었거나 틀린 경우에만 수정하세요.
재설치 시에는 기존 `~/.claude/settings.json`의 언어 정책 기본값을 유지하며, `AGENT_LANGUAGE` 또는 `CONTENT_LANGUAGE`를 명시한 경우에만 그 값이 우선합니다.
기존 파일은 `.backup_YYYYMMDD_HHMMSS` 형식으로 자동 백업됩니다.

## Git Hooks

SKILL.md 파일을 커밋 전 자동으로 검증하려면 git hook을 설치하세요:

```bash
./hooks/install-hooks.sh
```

설치 스크립트는 `pre-commit`, `commit-msg`, `pre-push`를 `.git/hooks/`에 배포합니다.

### Pre-commit Hook
- SKILL.md 파일 변경 감지
- `validate_skills.sh` 자동 실행
- 유효하지 않은 SKILL.md 파일이 있으면 커밋 차단

### Commit-msg Hook
- Conventional Commits 형식 검증
- attribution trailer/prose 및 emoji 차단
- 공유 검증기 `hooks/lib/validate-commit-message.sh` 사용

### Pre-push Hook
- 보호 브랜치(`main`, `develop`)로의 직접 push 차단
- 보호 브랜치는 pull request 워크플로 필요
- `.git/hooks/pre-push`로 설치되며, `pre-push.ps1`은 PowerShell 동등 구현입니다
