# Claude Configuration Backup & Deployment System

<p align="center">
  <a href="https://github.com/kcenon/claude-config/releases"><img src="https://img.shields.io/badge/version-1.10.0-blue.svg" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-green.svg" alt="License"></a>
  <a href="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml"><img src="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>여러 시스템 간에 CLAUDE.md 설정을 쉽게 공유하고 동기화하는 도구</strong>
</p>

<p align="center">
  <a href="#빠른-시작">빠른 시작</a> •
  <a href="#설치하면-무엇이-달라지나요">설치 효과</a> •
  <a href="#원라인-설치">설치</a> •
  <a href="#토큰-최적화">토큰 최적화</a> •
  <a href="#구조">구조</a> •
  <a href="#사용-시나리오">시나리오</a> •
  <a href="#faq">FAQ</a> •
  <a href="README.md">English</a>
</p>

---

## 빠른 시작

3분 만에 설정 완료:

```bash
# 1. 원라인 설치
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash

# 2. Git identity 개인화 (필수!)
vi ~/.claude/git-identity.md

# 3. Claude Code 재시작 - 완료!
```

**주요 명령어:**

| 작업 | macOS/Linux | Windows (PowerShell) |
|------|-------------|----------------------|
| 설정 설치 | `./scripts/install.sh` | `.\scripts\install.ps1` |
| 설정 백업 | `./scripts/backup.sh` | `.\scripts\backup.ps1` |
| 설정 동기화 | `./scripts/sync.sh` | `.\scripts\sync.ps1` |
| 백업 검증 | `./scripts/verify.sh` | `.\scripts\verify.ps1` |

상세 시나리오는 [사용 시나리오](#사용-시나리오)를 참조하세요.

---

## 설치하면 무엇이 달라지나요

claude-config을 설치하면 Claude Code에 다음 기능이 즉시 적용됩니다:

**보안** — `.env`, `.pem`, 인증 정보 파일이 자동으로 읽기/쓰기 차단됩니다. `rm -rf /` 같은 위험한 명령도 실행 전에 차단됩니다.

**자동 포맷팅** — 코드 저장 시 자동 포맷: Python (black), TypeScript (prettier), Go (gofmt), Rust (rustfmt), C++ (clang-format), Kotlin (ktlint).

**워크플로우 자동화** — `/issue-work`로 GitHub 이슈를 선택해서 PR 생성까지 한 번에 처리합니다. `/release`는 변경 로그를 자동 생성하고, `/pr-work`는 CI 실패를 진단·수정합니다.

**커밋 품질 관리** — 깨진 마크다운 링크, AI 어트리뷰션, 비표준 커밋 메시지가 저장소에 들어가기 전에 자동으로 검출됩니다.

**컨텐츠 언어 정책 선택** — 설치 시점에 커밋 메시지·PR 본문·문서의 언어를 English (ASCII 전용) 또는 Korean (산출물 단위 엄격, 인라인 혼용 금지) 중에서 선택합니다. 두 옵션 UI는 `CLAUDE_CONTENT_LANGUAGE=english|exclusive_bilingual` 로 매핑되며, 레거시 값 (`korean_plus_english`, `any`) 은 settings.json 직접 편집을 통해서만 사용 가능합니다.

**주문형 코드 분석** — `/security-audit`, `/performance-review`, `/code-quality`, `/pr-review`로 필요할 때 전문 분석을 실행합니다.

**에이전트 팀 설계** — `/harness`로 프로젝트에 맞는 멀티 에이전트 아키텍처를 설계하고, 6가지 아키텍처 패턴과 오케스트레이터 템플릿을 활용합니다.

**크로스 플랫폼** — macOS, Linux, Windows (PowerShell) 모두 지원합니다.

---

## 원라인 설치

### Public Repository

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

> **bootstrap이 자동으로 처리하는 것.** Claude Code CLI 미설치 시 사용자 동의 후 Anthropic 공식 native installer(`https://claude.ai/install.sh`)를 실행해 `claude` 바이너리를 `~/.local/bin/`에 배치하고 백그라운드 자동 업데이트를 활성화합니다. npm 패키지 `@anthropic-ai/claude-code`는 더 이상 사용되지 않습니다. PowerShell은 `claude.ai/install.ps1`로 동일하게 동작합니다. 자세한 내용은 [PREREQUISITES.md → Auto-installed by bootstrap](PREREQUISITES.md#auto-installed-by-bootstrap).

### Private Repository

```bash
# GitHub Personal Access Token 사용
curl -sSL -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

### Git Clone 방식

```bash
# 1. 저장소 클론
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup

# 2. 설치 스크립트 실행
cd ~/claude_config_backup
./scripts/install.sh

# 3. Git identity 개인화 (필수!)
vi ~/.claude/git-identity.md
```

### Plugin 설치 (Beta)

Claude Code Plugin으로 설치하여 쉽게 배포하고 업데이트할 수 있습니다:

```bash
# 마켓플레이스 추가
/plugin marketplace add kcenon/claude-config

# 플러그인 설치
/plugin install claude-config@kcenon/claude-config
```

또는 로컬에서 테스트:

```bash
# 플러그인 직접 로드 (개발/테스트용)
claude --plugin-dir ./plugin
```

자세한 내용은 [plugin/README.md](plugin/README.md)를 참조하세요.

### Windows (PowerShell)

```powershell
# 1. 저장소 클론
git clone https://github.com/kcenon/claude-config.git ~\claude_config_backup

# 2. 설치 스크립트 실행 (PowerShell 7+ 권장)
cd ~\claude_config_backup
.\scripts\install.ps1
```

> **참고**: PowerShell 7+ (`pwsh`)가 필요합니다. `winget install Microsoft.PowerShell`로 설치하세요.
> 실행 정책 오류 시: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

### 경량 Plugin (Behavioral Guardrails Only)

전체 구성 없이 핵심 동작 교정만 원하시나요?

```bash
# lite plugin 설치
claude plugins add kcenon/claude-config-lite

# 또는 로컬 테스트
claude --plugin-dir ./plugin-lite
```

| 방식 | 포함 내용 | 크기 |
|------|----------|------|
| Full plugin | 모든 스킬, 에이전트, 훅을 포함한 전체 설정 | ~384KB |
| **Lite plugin** | LLM 코딩 실수를 위한 핵심 동작 가드레일 | ~5KB |
| Bootstrap 스크립트 | ~/.claude/에 배포되는 전체 시스템 설정 | 전체 repo |

자세한 내용은 [plugin-lite/README.md](plugin-lite/README.md)를 참조하세요.

---

## 토큰 최적화

규칙과 스킬은 필요할 때만 로드됩니다 — 현재 작업에 관련된 것만 컨텍스트에 로드됩니다. 별도 설정이 필요 없습니다.

### 레퍼런스 문서 로드

일부 상세 레퍼런스 문서는 효율성을 위해 초기 컨텍스트에서 제외됩니다. 필요할 때 로드하세요:

```markdown
# 특정 레퍼런스 로드 요청
@load: reference/agent-teams

# 또는 파일을 직접 참조
rules/workflow/reference/label-definitions.md를 검토해주세요.
```

고급 커스터마이징은 [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md)를 참조하세요.

---

## 구조

<details>
<summary>디렉토리 구조 펼치기</summary>

```
claude_config_backup/
├── enterprise/                  # Enterprise 설정 (시스템 전체)
│   ├── CLAUDE.md               # 조직 전체 정책
│   └── rules/                  # Enterprise 규칙
│       ├── security.md         # 보안 규칙 템플릿
│       └── compliance.md       # 컴플라이언스 규칙 템플릿
│
├── global/                      # 글로벌 설정 백업 (~/.claude/)
│   ├── CLAUDE.md               # 메인 설정 파일
│   ├── settings.json           # Hook 설정 (macOS/Linux)
│   ├── settings.windows.json   # Hook 설정 (Windows PowerShell)
│   ├── commit-settings.md      # 커밋/PR 정책 (Claude 정보 비활성화)
│   ├── tmux.conf               # tmux 자동 로깅 설정
│   ├── ccstatusline/           # 상태줄 설정
│   ├── commands/               # 글로벌 명령어 정책
│   │   └── _policy.md         # 모든 명령어 공통 정책
│   ├── hooks/                  # Hook 스크립트 (macOS + Windows)
│   │   ├── sensitive-file-guard.sh/.ps1
│   │   ├── dangerous-command-guard.sh/.ps1
│   │   ├── github-api-preflight.sh/.ps1
│   │   ├── markdown-anchor-validator.sh/.ps1
│   │   ├── prompt-validator.sh/.ps1
│   │   ├── session-logger.sh/.ps1
│   │   ├── tool-failure-logger.sh/.ps1
│   │   ├── subagent-logger.sh/.ps1
│   │   ├── task-completed-logger.sh/.ps1
│   │   ├── config-change-logger.sh/.ps1
│   │   ├── pre-compact-snapshot.sh/.ps1
│   │   ├── worktree-create.sh/.ps1
│   │   ├── worktree-remove.sh/.ps1
│   │   ├── team-limit-guard.sh/.ps1
│   │   ├── commit-message-guard.sh/.ps1
│   │   ├── conflict-guard.sh/.ps1
│   │   ├── pr-target-guard.sh/.ps1
│   │   ├── version-check.sh/.ps1
│   │   └── cleanup.sh/.ps1
│   ├── scripts/                # 유틸리티 스크립트
│   │   ├── statusline-command.sh/.ps1
│   │   └── weekly-usage.sh
│   └── skills/                 # 글로벌 Skills (사용자 호출형)
│       ├── branch-cleanup/     # 병합/오래된 브랜치 정리
│       ├── doc-index/          # 문서 인덱스 파일 생성
│       ├── doc-review/         # 마크다운 문서 리뷰
│       ├── implement-all-levels/ # 완전 구현 강제
│       ├── issue-create/       # GitHub 이슈 생성 (5W1H)
│       ├── issue-work/         # GitHub 이슈 워크플로우
│       ├── pr-work/            # PR CI/CD 실패 수정
│       ├── release/            # 자동 릴리스 생성
│       └── harness/            # Agent team & skill 아키텍처 설계
│
├── project/                     # 프로젝트 설정 백업
│   ├── CLAUDE.md               # 프로젝트 메인 설정
│   ├── CLAUDE.local.md.template # 로컬 설정 템플릿 (커밋 제외)
│   ├── .mcp.json               # MCP 서버 설정 템플릿
│   ├── .mcp.json.example       # MCP 설정 예시
│   ├── claude-guidelines/      # 독립형 가이드라인 (.claude 비의존)
│   └── .claude/
│       ├── settings.json       # Hook 설정 (자동 포맷팅)
│       ├── settings.local.json.template  # 로컬 설정 템플릿
│       ├── rules/              # 통합 가이드라인 모듈 (자동 로드)
│       │   ├── coding/         # 코딩 표준
│       │   │   ├── standards.md
│       │   │   ├── implementation-standards.md
│       │   │   ├── error-handling.md
│       │   │   ├── safety.md
│       │   │   ├── performance.md
│       │   │   ├── cpp-specifics.md
│       │   │   └── reference/anti-patterns.md
│       │   ├── api/            # API 및 아키텍처
│       │   │   ├── api-design.md
│       │   │   ├── architecture.md
│       │   │   ├── observability.md
│       │   │   └── rest-api.md
│       │   ├── workflow/       # 워크플로우 및 GitHub 가이드라인
│       │   │   ├── git-commit-format.md
│       │   │   ├── github-issue-5w1h.md
│       │   │   ├── github-pr-5w1h.md
│       │   │   ├── build-verification.md
│       │   │   ├── ci-resilience.md
│       │   │   ├── performance-analysis.md
│       │   │   ├── session-resume.md
│       │   │   └── reference/  # 레이블, 자동화, Agent Teams
│       │   ├── core/           # 핵심 설정
│       │   │   ├── environment.md
│       │   │   ├── communication.md
│       │   │   └── principles.md
│       │   ├── project-management/
│       │   │   ├── build.md
│       │   │   ├── testing.md
│       │   │   └── documentation.md
│       │   ├── operations/
│       │   │   └── ops.md
│       │   ├── tools/
│       │   │   └── gh-cli-scripts.md
│       │   └── security.md     # 보안 가이드라인
│       ├── commands/           # 사용자 정의 슬래시 명령어
│       │   ├── _policy.md
│       │   ├── pr-review.md
│       │   ├── code-quality.md
│       │   └── git-status.md
│       ├── agents/             # 특화 에이전트 설정
│       │   ├── code-reviewer.md
│       │   ├── codebase-analyzer.md
│       │   ├── documentation-writer.md
│       │   ├── qa-reviewer.md
│       │   ├── refactor-assistant.md
│       │   └── structure-explorer.md
│       └── skills/             # Claude Code Skills
│           ├── coding-guidelines/
│           ├── security-audit/
│           ├── performance-review/
│           ├── api-design/
│           ├── project-workflow/
│           ├── documentation/
│           ├── ci-debugging/
│           ├── code-quality/   # 사용자 호출형
│           ├── git-status/     # 사용자 호출형
│           └── pr-review/      # 사용자 호출형
│
├── scripts/                     # 자동화 스크립트
│   ├── install.sh              # 새 시스템에 설치 (macOS/Linux)
│   ├── install.ps1             # 새 시스템에 설치 (Windows PowerShell)
│   ├── backup.sh               # 현재 설정 백업
│   ├── sync.sh                 # 설정 동기화
│   ├── verify.sh               # 백업 무결성 검증
│   ├── validate_skills.sh      # SKILL.md 파일 검증
│   └── gh/                     # GitHub CLI 헬퍼 스크립트
│
├── hooks/                       # Git hooks
│   ├── pre-commit              # 커밋 전 스킬 검증
│   ├── pre-push                # 보호 브랜치 직접 푸시 차단
│   ├── pre-push.ps1            # Pre-push (PowerShell)
│   ├── commit-msg              # 커밋 메시지 형식 검증
│   ├── install-hooks.sh/.ps1   # Hook 설치 스크립트
│   └── lib/
│       └── validate-commit-message.sh  # 공유 검증 라이브러리
│
├── .github/
│   └── workflows/
│       ├── validate-skills.yml     # CI 스킬 검증 (main 대상 PR만)
│       ├── validate-hooks.yml      # CI 훅 검증 (main 대상 PR만)
│       └── validate-pr-target.yml  # develop 외 브랜치의 main 머지 차단
│
├── docs/                        # 설계 문서 및 가이드
│   ├── branching-strategy.md   # 브랜치 모델, CI 정책, 릴리스 워크플로우
│   ├── CLAUDE_DOCKER_CONTRACT.md  # claude-docker와의 통합 계약 (SSOT)
│   ├── install.md              # 설치 흐름, 매니페스트, 사후 검증
│   ├── SANDBOX_TLS.md          # 샌드박스/TLS 트러블슈팅 (gh, curl)
│   ├── TOKEN_OPTIMIZATION.md
│   ├── SKILL_TOKEN_REPORT.md
│   ├── CUSTOM_EXTENSIONS.md
│   ├── ad-sdlc-integration.md
│   ├── plugin-vs-global.md
│   ├── hooks-ownership.md
│   └── design/                 # 아키텍처 설계 문서
│       ├── optimization-discoveries.md
│       ├── optimization-phases.md
│       └── command-optimization.md
│
├── plugin/                      # Claude Code Plugin (Beta)
│   ├── .claude-plugin/
│   │   └── plugin.json         # 플러그인 매니페스트
│   ├── agents/                 # 번들 에이전트 정의
│   ├── skills/                 # 독립형 스킬 (심볼릭 링크 없음)
│   └── hooks/                  # 플러그인 후크
│
├── plugin-lite/                 # 경량 Plugin (Guardrails Only)
│   ├── .claude-plugin/
│   │   └── plugin.json
│   └── skills/
│       └── behavioral-guardrails/
│           └── SKILL.md        # 단일 행동 가드레일 스킬
│
├── tests/                       # Hook + skill 골든 코퍼스, 회귀 러너
├── bootstrap.sh/.ps1            # 원라인 설치 스크립트 (Claude Code CLI 자동 설치 포함)
├── VERSION_MAP.yml              # 컴포넌트 SemVer SSOT (아래 "버전 관리" 섹션 참조)
├── COMPATIBILITY.md             # Claude Code 릴리스 대비 settings.json 필드 안정성 매트릭스
├── ENFORCEMENT.md               # 어트리뷰션/커밋 가드 3-레이어 강제 모델
├── PREREQUISITES.md             # 도구 목록과 플랫폼별 설치 명령
├── THIRD_PARTY_NOTICES.md       # 외부 출처 코드 스니펫 어트리뷰션
├── README.md                    # 상세 가이드 (영문)
├── README.ko.md                 # 상세 가이드 (한글)
├── QUICKSTART.md                # 빠른 시작 가이드
└── HOOKS.md                     # Hook 설정 가이드
```

</details>

---

## 버전 관리

claude-config는 **저장소 단일 버전을 사용하지 않습니다**. 출하되는 각 산출물이 독립된 SemVer 라인을 가지며 `VERSION_MAP.yml`에 한 곳으로 모여 있습니다:

| 필드 | 추적 산출물 | Consumer 파일 |
|------|------------|---------------|
| `suite` | README 뱃지에 노출되는 사용자용 "릴리스" 식별자 | `README.md`, `README.ko.md` shields URL |
| `plugin` | 마켓플레이스 플러그인 버전 | `plugin/.claude-plugin/plugin.json` |
| `plugin-lite` | 경량 플러그인 (행동 가드레일) | `plugin-lite/.claude-plugin/plugin.json` |
| `settings-schema` | 훅 발사 `settings.json` 스키마 | `global/settings.json`, `global/settings.windows.json` |
| `hooks` | 출하 훅 번들 (롤아웃마다 bump) | `HOOKS.md`, `ENFORCEMENT.md`로 운영자에게 노출 |

`scripts/check_versions.sh`가 각 Consumer 파일이 `VERSION_MAP.yml`에 선언된 필드와 일치하는지 검증합니다. 한 번에 한 필드만 bump하려면 `/release <field> <new-version>` (또는 `scripts/sync_versions.sh`)을 사용하세요. 다섯 필드를 한꺼번에 동기화하면 의도된 "독립 진화" 설계를 무력화하고, 무관한 이유로 변경되는 "X.Y와 호환" 뱃지를 양산하게 됩니다. `suite` 필드와 claude-docker 태그 라인의 결합 관계는 [`docs/CLAUDE_DOCKER_CONTRACT.md`](docs/CLAUDE_DOCKER_CONTRACT.md)에 정의됩니다.

---

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

> 전체 Hook 설정 세부사항 및 커스터마이징은 [HOOKS.md](HOOKS.md)를 참조하세요.

### 컨텐츠 언어 정책

두 installer (`install.sh`, `install.ps1`)는 설치 타입 선택 후에 컨텐츠 언어 정책을 묻습니다. 단순화된 UI는 두 가지 선택지만 제공하며, 산출물 단위 언어 고정 보장으로 매핑됩니다:

| UI 선택 | `CLAUDE_CONTENT_LANGUAGE` 값 | 검증자가 수용하는 범위 | 규칙 문서 phrase |
|---------|------------------------------|----------------------|-----------------|
| English (기본) | `english` | ASCII printable + whitespace | `English` |
| Korean | `exclusive_bilingual` | 산출물 단위로 영어 전용 또는 한국어 전용 (제한된 ASCII container 허용), 인라인 혼용 금지 | `English or Korean (document-exclusive)` |

검증자는 UI에 노출되지 **않는** 두 레거시 값도 추가로 수용합니다 — 필요 시 `settings.json` 직접 편집으로 설정합니다:

| 레거시 값 | 사용 시점 | 검증자가 수용하는 범위 |
|-----------|-----------|----------------------|
| `korean_plus_english` | issue #447 이전 설치 호환 (인라인 혼용 의존 시) | ASCII + 한글 음절 / 자모 / 호환 자모 |
| `any` | 모든 언어 기여를 받는 OSS 저장소 | 언어 검증 전체 생략 |

Installer는 선택된 phrase를 세 규칙 문서 템플릿 (`global/commit-settings.md.tmpl`, `project/.claude/rules/core/communication.md.tmpl`, `project/.claude/rules/workflow/git-commit-format.md.tmpl`)에 치환합니다. 규칙 문서의 표현과 검증자의 실제 동작이 일치하도록 유지합니다.

**스코프 경계**: AI/Claude 어트리뷰션 차단은 이 env var의 영향을 **받지 않습니다** — `attribution-guard`와 `commit-message-guard` 내부의 attribution 검사는 모든 정책에서 그대로 작동합니다.

**Enterprise 충돌 감지**: 배포된 enterprise `CLAUDE.md`가 영어를 강제하는데 운영자가 더 허용적인 정책을 선택하면, installer가 경고를 출력하고 진행 전에 확인을 요청합니다.

자세한 설계 배경, phrase 테이블, 드리프트 검증 불변식은 [`docs/content-language-policy.md`](docs/content-language-policy.md)를 참조하세요.

---

## Enterprise 설정

Enterprise 설정은 조직의 모든 개발자에게 적용되는 조직 전체 정책을 제공합니다. Claude Code의 메모리 계층에서 **가장 높은 우선순위**를 가집니다.

### 메모리 계층

| 레벨 | 위치 | 범위 | 우선순위 |
|------|------|------|----------|
| **Enterprise Policy** | 시스템 전체 | 조직 | **최고** |
| Project Memory | `./CLAUDE.md` | 팀 | 높음 |
| Project Rules | `./.claude/rules/*.md` | 팀 | 높음 |
| User Memory | `~/.claude/CLAUDE.md` | 개인 | 중간 |
| Project Local | `./CLAUDE.local.md` | 개인 | 낮음 |

### OS별 Enterprise 경로

| OS | 경로 |
|----|------|
| **macOS** | `/Library/Application Support/ClaudeCode/CLAUDE.md` |
| **Linux** | `/etc/claude-code/CLAUDE.md` |
| **Windows** | `C:\Program Files\ClaudeCode\CLAUDE.md` |

### Enterprise 설정 설치

```bash
./scripts/install.sh

# 옵션 선택:
#   4) Enterprise 설정만 설치 (관리자 권한 필요)
#   5) 전체 설치 (Enterprise + Global + Project)
```

**참고**: Enterprise 설치는 관리자 권한이 필요합니다 (macOS/Linux에서 `sudo`).

### Enterprise 템플릿 내용

기본 enterprise 템플릿에는 다음이 포함됩니다:
- **보안 요구사항**: 커밋 서명, 비밀 정보 보호, 접근 제어
- **컴플라이언스**: 데이터 처리, 감사 요구사항, 규정 준수
- **승인된 도구**: 패키지 레지스트리, 컨테이너 이미지, 의존성
- **코드 표준**: 품질 게이트, 리뷰 요구사항, 브랜치 보호

배포 전에 조직의 정책에 맞게 `enterprise/CLAUDE.md`를 커스터마이즈하세요.

---

## 개인 설정 (CLAUDE.local.md)

버전 관리에 포함되지 않아야 하는 머신별 설정은 프로젝트 루트에 `CLAUDE.local.md`를 생성하세요.

```bash
# 템플릿 복사
cp project/CLAUDE.local.md.template CLAUDE.local.md
```

로컬 서버 URL, 머신별 경로, 개인 워크플로우 선호도에 사용하세요. 자격 증명이나 API 키는 여기에 넣지 **마세요** — 환경 변수를 사용하세요.

이 파일은 gitignore되며 Claude Code의 메모리 계층에서 가장 낮은 우선순위를 가집니다.

---

## Rules

Rules는 `.claude/rules/`에 있는 모듈형 설정 파일로, 파일 경로에 따라 조건부로 로드됩니다.

### 사용 가능한 Rules

| Rule | 자동 로드 대상 | 설명 |
|------|---------------|------|
| `coding.md` | `**/*.ts`, `**/*.py`, `**/*.go` 등 | 일반 코딩 표준 |
| `testing.md` | `**/*.test.ts`, `**/test_*.py` 등 | 테스트 관례 |
| `security.md` | 모든 코드 파일 | 보안 모범 사례 |
| `documentation.md` | `**/*.md`, `**/docs/**` | 문서화 표준 |
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

---

## 스킬 — 무엇을 할 수 있나요

스킬 호출 방식은 두 가지입니다.

1. **슬래시 카탈로그 스킬** (`/code-quality`, `/security-audit`, `/performance-review`, `/pr-review`, `/git-status` 및 아래의 `plugin/` 스킬들) — `~/.claude/skills/<name>/SKILL.md` 1단계 폴더로 위치하며 Claude Code의 `/` 자동완성 카탈로그에 노출됩니다. 명령어를 입력하면 하네스가 디스패치합니다.
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
| `/pr-review` | 품질, 보안, 성능, 테스트를 포함한 종합 PR 분석 |

### 설계 및 문서화

`/git-status`는 슬래시 카탈로그 스킬, 나머지는 키워드 별칭입니다.

| 명령어 | 모드 | 기능 |
|--------|------|------|
| `/harness` | keyword | Agent team 설계 및 모든 도메인에 대한 스킬 생성 |
| `/doc-index` | keyword | 문서 인덱스 파일 생성 (manifest, bundles, graph, router) |
| `/doc-review` | keyword | 정확성, 앵커, 상호 참조에 대한 마크다운 문서 리뷰 |
| `/git-status` | slash | 실행 가능한 인사이트가 포함된 저장소 상태 |
| `/implement-all-levels` | keyword | 계층형 기능의 모든 티어에 대한 완전한 구현 강제 |

---

## Agents

`.claude/agents/`에 있는 특수 에이전트가 특정 작업에 집중된 지원을 제공합니다.

### 사용 가능한 Agents

| Agent | 설명 | Model |
|-------|------|-------|
| `code-reviewer` | 종합 코드 리뷰 | sonnet |
| `documentation-writer` | 기술 문서 작성 | sonnet |
| `refactor-assistant` | 안전한 코드 리팩토링 | sonnet |
| `codebase-analyzer` | 코드베이스 아키텍처 및 패턴 분석 | sonnet |
| `qa-reviewer` | 통합 일관성 검증 | sonnet |
| `structure-explorer` | 프로젝트 디렉토리 구조 매핑 | haiku |

### Agent 설정

Agents는 YAML frontmatter로 동작을 정의합니다:

```yaml
---
name: agent-name
description: 에이전트의 역할
model: sonnet
tools: Read, Edit
temperature: 0.3
---
```

---

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

### 주요 조작법

| 동작 | 방법 |
|------|------|
| 팀원 간 순환 | `Shift+Down` |
| 공유 작업 목록 | `Ctrl+T` |
| 메시지 전송 | `Enter` (포커스된 팀원에게) |
| 리드로 복귀 | `Escape` |

최적의 조정을 위해 팀을 2-3명으로 유지하세요. 파일 충돌을 피하기 위해 각 팀원에게 별도의 파일 세트를 할당하세요.

아키텍처 패턴, 표시 모드, 훅, 고급 설정은 `rules/workflow/reference/agent-teams.md`를 참조하세요.

---

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

---

## 스크립트 설명

| 스크립트 | 목적 | 사용법 |
|----------|------|--------|
| `install.sh` / `.ps1` | 새 시스템에 설정 설치 | `./scripts/install.sh` |
| `backup.sh` / `.ps1` | 현재 설정을 백업에 저장 | `./scripts/backup.sh` |
| `sync.sh` / `.ps1` | 시스템과 백업 간 양방향 동기화 | `./scripts/sync.sh` |
| `verify.sh` / `.ps1` | 백업 무결성과 완전성 확인 | `./scripts/verify.sh` |
| `validate_skills.sh` / `.ps1` | SKILL.md 형식 준수 여부 검증 | `./scripts/validate_skills.sh` |

설치 후, 반드시 `~/.claude/git-identity.md`를 개인 정보로 수정**해야** 합니다.
기존 파일은 `.backup_YYYYMMDD_HHMMSS` 형식으로 자동 백업됩니다.

---

## Pre-commit Hook

SKILL.md 파일을 커밋 전 자동으로 검증하려면 pre-commit hook을 설치하세요:

```bash
./hooks/install-hooks.sh
```

Hook이 수행하는 작업:
- SKILL.md 파일 변경 감지
- `validate_skills.sh` 자동 실행
- 유효하지 않은 SKILL.md 파일이 있으면 커밋 차단

---

## 사용 시나리오

### 시나리오 A: 회사 + 집 컴퓨터 동기화

```bash
# 회사에서 (초기 설정)
cd ~/claude_config_backup
./scripts/backup.sh
git add . && git commit -m "Update settings"
git push

# 집에서
cd ~/claude_config_backup
git pull
./scripts/sync.sh
# 선택: 1 (백업 → 시스템)
```

---

### 시나리오 B: 팀 프로젝트 설정 공유

```bash
# 프로젝트 리더
cd project_root
git clone https://github.com/kcenon/claude-config.git .claude-config
cd .claude-config
./scripts/install.sh
# 타입: 2 (프로젝트만)

# 팀 멤버
git clone https://github.com/your-org/project.git
cd project/.claude-config
./scripts/install.sh
# 타입: 2 (프로젝트만)
```

---

### 시나리오 C: 새 개발 머신 설정

```bash
# 원라인 설치
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash

# 또는 수동 설치
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup
cd ~/claude_config_backup
./scripts/install.sh
# 타입: 3 (둘 다)

# Git identity 수정
vi ~/.claude/git-identity.md
```

---

<details>
<summary><strong>고급 사용법</strong> (GitHub Actions, 환경 변수)</summary>

## 고급 사용법

### GitHub Actions 자동 동기화

`.github/workflows/sync.yml` 파일 생성:

```yaml
name: Sync Claude Config

on:
  push:
    branches: [main]
  schedule:
    - cron: '0 0 * * 0'  # 매주 일요일

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify backup integrity
        run: ./scripts/verify.sh
```

### 특정 파일만 백업

```bash
# 글로벌 CLAUDE.md만 백업
cp ~/.claude/CLAUDE.md ~/claude_config_backup/global/

# 프로젝트 설정만 백업
cp -r ~/project/.claude ~/claude_config_backup/project/
```

### 환경 변수로 커스터마이즈

```bash
# bootstrap.sh 사용 시
GITHUB_USER=your-username \
GITHUB_REPO=your-repo \
INSTALL_DIR=~/my-claude-config \
bash -c "$(curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh)"
```

</details>

---

## FAQ

### Q1: Git identity를 왜 개인화해야 하나요?

**A:** `git-identity.md`는 개인 정보(이름, 이메일)를 포함하므로, 각 사용자가 자신의 정보로 수정해야 합니다.

```bash
vi ~/.claude/git-identity.md
# name과 email을 자신의 정보로 변경
```

---

### Q2: 백업을 여러 곳에서 관리하면?

**A:** Git으로 버전 관리하세요:

```bash
cd ~/claude_config_backup
git add .
git commit -m "Update settings"
git push
```

---

### Q3: 프로젝트마다 다른 설정을 쓰고 싶어요

**A:** 프로젝트별로 브랜치를 분리하거나, 별도 디렉토리를 사용하세요:

```bash
git checkout -b project-a
# 프로젝트 A 설정 수정
git commit -m "Settings for project A"

git checkout -b project-b
# 프로젝트 B 설정 수정
git commit -m "Settings for project B"
```

---

### Q4: 스크립트가 실행 안 돼요

**A:** 실행 권한을 확인하세요:

```bash
chmod +x scripts/*.sh bootstrap.sh

# 또는 직접 실행
bash scripts/install.sh
```

---

### Q5: Private repo로 사용하고 싶어요

**A:** 설치 시 Personal Access Token을 사용하세요:

```bash
# Token 생성: GitHub Settings > Developer settings > Personal access tokens

# 설치
curl -sSL -H "Authorization: token YOUR_TOKEN" \
  https://raw.githubusercontent.com/your-user/claude-config/main/bootstrap.sh | bash
```

---

## 추가 리소스

- **설정 예제**: `global/` 및 `project/` 디렉토리 참조
- **브랜칭 전략**: [docs/branching-strategy.md](docs/branching-strategy.md) - 브랜치 모델, CI 정책, 릴리스 워크플로우
- **커스텀 확장 가이드**: [docs/CUSTOM_EXTENSIONS.md](docs/CUSTOM_EXTENSIONS.md) - 공식 기능과 커스텀 기능 구분
- **토큰 최적화**: [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md) - 규칙 최적화 (86% 절감)
- **스킬 토큰 리포트**: [docs/SKILL_TOKEN_REPORT.md](docs/SKILL_TOKEN_REPORT.md) - 스킬별 토큰 소모 분석
- **AD-SDLC 통합**: [docs/ad-sdlc-integration.md](docs/ad-sdlc-integration.md) - AI 에이전트 기반 SDLC 통합
- **문제 해결**: 각 스크립트의 에러 메시지 확인

---

## 버전

**현재**: 1.7.0 (2026-04-06)

<details>
<summary>변경 이력</summary>

#### v1.7.0 (2026-04-06)
- **Windows PowerShell 완전 지원**: 모든 42개 bash 스크립트에 PowerShell (.ps1) 대응 파일 추가
  - 유틸리티 스크립트: `install`, `verify`, `sync`, `backup`, `validate_skills`, `bootstrap`
  - 16개 hook 스크립트 (fail-closed 보안 모델 동일하게 보존)
  - 8개 GitHub CLI 헬퍼 스크립트 (`scripts/gh/`)
  - 3개 글로벌 스크립트 (`statusline-command`, `team-report`, `weekly-usage`)
  - 7개 테스트 스크립트 (hook 검증용)
  - Git hooks 설치 스크립트 (`hooks/install-hooks.ps1`)
- **PowerShell 공유 모듈**: `CommonHelpers.psm1` 추가 (20개 함수 export)
  - 메시지 헬퍼, hook 응답 빌더, stdin JSON 리더
  - 플랫폼 감지, 버전 비교, 로그 로테이션
  - Windows에서 `jq` 의존성 제거 (네이티브 `ConvertFrom-Json` 사용)
  - .NET `GZipStream`으로 로그 압축 (외부 `gzip` 불필요)

#### v1.6.0 (2026-04-03)
- **Harness meta-skill**: Agent team 아키텍처 설계를 위한 `/harness` 추가
  - 6가지 아키텍처 패턴: Pipeline, Fan-out/Fan-in, Expert Pool, Producer-Reviewer, Supervisor, Hierarchical
  - `.claude/agents/` 및 `.claude/skills/` 자동 생성
  - 레퍼런스 문서: Agent 설계 패턴, 오케스트레이터 템플릿, Skill 작성/테스트 가이드, QA 에이전트 가이드
- **QA reviewer agent**: 통합 일관성 검증을 위한 `qa-reviewer` 에이전트 추가
- **Version check hook**: 알려진 Claude Code 캐시 버그 경고를 위한 SessionStart 훅 추가
- **배치 처리**: `/issue-work` 및 `/pr-work` 스킬에 배치 모드 추가 (단일 저장소, 크로스 저장소)
- **CI 검증**: Skill 검증에 description 품질 및 글로벌 Skills 검사 확장
- **Skill description**: 모든 스킬의 트리거 정확도 향상
- **Third-party notices**: Harness 콘텐츠 Attribution을 위한 `THIRD_PARTY_NOTICES.md` 추가 (Apache 2.0)

#### v1.5.0 (2026-03-21)
- **Skills 마이그레이션**: 모든 글로벌 명령어를 Skills 형식으로 마이그레이션
  - `/branch-cleanup`, `/release`, `/issue-create`, `/issue-work`, `/pr-work` 스킬화
  - 새 글로벌 Skills: `/doc-review`, `/implement-all-levels`
  - 새 프로젝트 Skills: `ci-debugging`, `code-quality`, `git-status`, `pr-review`
  - `argument-hint`, `model`, `tools`, adaptive execution frontmatter 지원
- **Agent Teams**: 실험적 멀티 에이전트 협업 프레임워크
  - 공유 작업 목록, 다이렉트 메시징, 팀 조정
  - 팀원 모드: `auto`, `in-process`, `tmux`
- **Windows PowerShell 지원**: 완전한 크로스 플랫폼 지원
  - `install.ps1` Windows 설치 스크립트
  - 모든 16개 hook에 `.ps1` 변형 제공
- **새 Hooks** (8개 신규):
  - `github-api-preflight`, `markdown-anchor-validator`, `prompt-validator`
  - `tool-failure-logger`, `subagent-logger`, `task-completed-logger`
  - `config-change-logger`, `pre-compact-snapshot`
  - `worktree-create`/`worktree-remove`
- **tmux 자동 로깅**: 세션 자동 기록을 위한 `tmux.conf` 추가
- **Plugin 강화**: 번들 에이전트 정의, 매니페스트 업데이트
- **GitHub 헬퍼 스크립트**: `scripts/gh/` 8개 헬퍼 추가
- **규칙 파일 재구성**: `coding/`, `core/`, `operations/`, `tools/` 규칙 현행화
- **컨텍스트 최적화**: SSOT 리팩토링으로 상시 로드 컨텍스트 77% 감소 (485 → 112줄)

#### v1.4.0 (2026-01-22)
- Import 구문 (`@path/to/file`) 도입으로 모듈 참조 방식 개선
- 모든 CLAUDE.md 및 SKILL.md에 Import 구문 적용

#### v1.3.0 (2026-01-15)
- 자동 changelog 생성을 위한 `/release` 명령어 추가
- 5W1H 프레임워크 기반 `/issue-create` 명령어 추가
- GitHub 워크플로우 자동화를 위한 `/issue-work`, `/pr-work` 명령어 추가
- 공통 정책 파일 (`_policy.md`) 추가

#### v1.2.0 (2026-01-15)
- CLAUDE.md 최적화 (project/CLAUDE.md: 212 → ~85줄)
- Progressive Disclosure 적용한 github-issue-5w1h.md 분리

#### v1.1.0 (2025-01-15)
- `.claude/rules/`, `.claude/commands/`, `.claude/agents/` 추가
- MCP 설정 템플릿, 로컬 설정 템플릿 추가
- Hook 이벤트 확장, `tools`/`model` 옵션 추가

#### v1.0.0 (2025-12-03)
- 글로벌 및 프로젝트 설정으로 초기 릴리스
- Progressive Disclosure 패턴의 Claude Code Skills
- 보안 및 자동 포매팅용 Hook 설정

</details>

---

## 기여

이 백업 시스템을 개선하고 싶으시다면:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

This project includes third-party content. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.

---

**Happy Coding with Claude!**
