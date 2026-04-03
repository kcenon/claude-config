# Claude Configuration Backup & Deployment System

<p align="center">
  <a href="https://github.com/kcenon/claude-config/releases"><img src="https://img.shields.io/badge/version-1.6.0-blue.svg" alt="Version"></a>
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
| 설정 백업 | `./scripts/backup.sh` | — |
| 설정 동기화 | `./scripts/sync.sh` | — |
| 백업 검증 | `./scripts/verify.sh` | — |

상세 시나리오는 [사용 시나리오](#사용-시나리오)를 참조하세요.

---

## 설치하면 무엇이 달라지나요

claude-config을 설치하면 Claude Code에 다음 기능이 즉시 적용됩니다:

**보안** — `.env`, `.pem`, 인증 정보 파일이 자동으로 읽기/쓰기 차단됩니다. `rm -rf /` 같은 위험한 명령도 실행 전에 차단됩니다.

**자동 포맷팅** — 코드 저장 시 자동 포맷: Python (black), TypeScript (prettier), Go (gofmt), Rust (rustfmt), C++ (clang-format), Kotlin (ktlint).

**워크플로우 자동화** — `/issue-work`로 GitHub 이슈를 선택해서 PR 생성까지 한 번에 처리합니다. `/release`는 변경 로그를 자동 생성하고, `/pr-work`는 CI 실패를 진단·수정합니다.

**커밋 품질 관리** — 깨진 마크다운 링크, AI 어트리뷰션, 비표준 커밋 메시지가 저장소에 들어가기 전에 자동으로 검출됩니다.

**주문형 코드 분석** — `/security-audit`, `/performance-review`, `/code-quality`, `/pr-review`로 필요할 때 전문 분석을 실행합니다.

**에이전트 팀 설계** — `/harness`로 프로젝트에 맞는 멀티 에이전트 아키텍처를 설계하고, 6가지 아키텍처 패턴과 오케스트레이터 템플릿을 활용합니다.

**크로스 플랫폼** — macOS, Linux, Windows (PowerShell) 모두 지원합니다.

---

## 원라인 설치

### Public Repository

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

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
| Full plugin | 9 skills, 6 agents, hooks, 종합 설정 | ~384KB |
| **Lite plugin** | Behavioral guardrails만 | ~5KB |
| Bootstrap 스크립트 | 전체 시스템 설정 | 전체 repo |

자세한 내용은 [plugin-lite/README.md](plugin-lite/README.md)를 참조하세요.

---

## 토큰 최적화

`alwaysApply` frontmatter와 `.claudeignore` 파일을 조합하여 초기 토큰 사용량을 줄입니다.

### 요약

| 지표 | 이전 | 이후 | 개선 |
|------|------|------|------|
| 초기 토큰 (rules + config) | ~30,500 | ~4,300 | **86% 감소** |
| 항상 로드되는 규칙 | 11개 파일 (105KB) | 5개 파일 (4KB) | **96% 감소** |
| 조건부 규칙 | 0개 파일 | 28개 파일 (208KB) | 필요 시만 로드 |

### 작동 원리

`alwaysApply: false` frontmatter에 `paths` 패턴을 지정하면 관련 파일 작업 시에만 규칙이 로드됩니다.
`.claudeignore` 파일은 참조 문서를 컨텍스트에서 제외합니다:
- 참조 문서 (필요 시 로드)
- 캐시 디렉토리 (중복)
- 플러그인 마켓플레이스 (거의 미사용)
- 세션 메모리 (이전 대화)

### 자동 설치

부트스트랩 스크립트 실행 시 `.claudeignore` 파일이 자동 설치됩니다:

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

### 수동 설치

기존 설치에 `.claudeignore`를 추가하려면:

```bash
# .claudeignore 파일 복사
cp global/.claudeignore ~/.claude/.claudeignore
cp project/.claudeignore <your-project>/.claude/.claudeignore

# 캐시 디렉토리 제거
rm -rf .npm-cache/

# Claude Code 세션 재시작
```

### 참조 문서 사용법

참조 문서는 기본적으로 제외되지만 필요 시 로드할 수 있습니다:

```markdown
# 방법 1: 명시적 파일 경로
rules/workflow/reference/label-definitions.md를 검토해주세요.

# 방법 2: @load 지시문
@load: reference/label-definitions
GitHub 라벨 관련 도움이 필요합니다.

# 방법 3: Claude에게 로드 요청
이슈 라벨링에 도움이 필요합니다. 관련 참조 문서를 로드해주세요.
```

### 상세 가이드

자세한 내용:
- [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md) — 규칙 최적화 및 `.claudeignore` 패턴
- [docs/SKILL_TOKEN_REPORT.md](docs/SKILL_TOKEN_REPORT.md) — 스킬별 토큰 소모 분석 및 런타임 오버헤드 리포트

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
│   │   ├── version-check.sh/.ps1
│   │   └── cleanup.sh/.ps1
│   ├── scripts/                # 유틸리티 스크립트
│   │   ├── statusline-command.sh/.ps1
│   │   └── weekly-usage.sh
│   └── skills/                 # 글로벌 Skills (사용자 호출형)
│       ├── branch-cleanup/     # 병합/오래된 브랜치 정리
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
│   └── install-hooks.sh        # Hook 설치 스크립트
│
├── docs/                        # 설계 문서 및 가이드
│   ├── TOKEN_OPTIMIZATION.md
│   ├── SKILL_TOKEN_REPORT.md
│   ├── OPTIMIZATION_DISCOVERIES.md
│   ├── CUSTOM_EXTENSIONS.md
│   ├── ad-sdlc-integration.md
│   └── design/                 # 아키텍처 설계 문서
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
├── bootstrap.sh                 # 원라인 설치 스크립트
├── README.md                    # 상세 가이드 (영문)
├── README.ko.md                 # 상세 가이드 (한글)
├── QUICKSTART.md               # 빠른 시작 가이드
└── HOOKS.md                    # Hook 설정 가이드
```

</details>

---

## Hook 설정

보안, 관찰성, 생산성을 위한 16개 hook 스크립트를 포함합니다 (각각 macOS `.sh`와 Windows `.ps1` 변형 제공).

### 보안 Hooks

| Hook | 이벤트 | 설명 |
|------|--------|------|
| **민감 파일 보호** | PreToolUse | `.env`, `.pem`, `.key`, `secrets/` 접근 차단 |
| **위험 명령어 차단** | PreToolUse | `rm -rf /`, `chmod 777`, 원격 스크립트 실행 차단 |
| **GitHub API 사전검증** | PreToolUse | GitHub API 호출 검증 |
| **프롬프트 검증** | UserPromptSubmit | 위험 작업 (delete all, drop database) 경고 |

### 관찰성 Hooks

| Hook | 이벤트 | 설명 |
|------|--------|------|
| **세션 로깅** | SessionStart/End | 세션 시작/종료 시간 기록 |
| **도구 실패 로거** | PostToolUse | 도구 실행 실패 디버깅용 기록 |
| **서브에이전트 로거** | SubagentStart/Stop | 서브에이전트 라이프사이클 추적 |
| **작업 완료 로거** | TaskCompleted | 팀원 작업 완료 기록 |
| **설정 변경 로거** | ConfigChange | 설정 변경 추적 |

### 워크플로우 Hooks

| Hook | 이벤트 | 설명 |
|------|--------|------|
| **마크다운 앵커 검증** | PostToolUse | 편집 후 마크다운 앵커 검증 |
| **사전 압축 스냅샷** | PreCompact | 자동 압축 전 컨텍스트 보존 |
| **Worktree 생성** | WorktreeCreate | Worktree 환경 설정 |
| **Worktree 제거** | WorktreeRemove | Worktree 환경 정리 |
| **임시 파일 정리** | SessionEnd | `/tmp/claude_*` 파일 제거 |
| **팀 제한 가드** | PreToolUse | `MAX_TEAMS` 동시 팀 수 제한 |
| **버전 체크** | SessionStart | 알려진 캐시 버그 버전 경고 |

### 프로젝트 Hooks

| Hook | 이벤트 | 설명 |
|------|--------|------|
| **자동 포맷팅** | PostToolUse | 파일 편집 후 언어별 포매터 실행 |

자세한 설정은 [HOOKS.md](HOOKS.md)를 참조하세요.

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

버전 관리에 포함되지 않아야 하는 머신별 또는 개인 설정은 `CLAUDE.local.md`를 사용하세요.

### CLAUDE.local.md란?

| 항목 | 설명 |
|------|------|
| **목적** | 개인 프로젝트별 설정 |
| **커밋 여부** | 아니오 (gitignore됨) |
| **우선순위** | 낮음 (프로젝트/팀 설정에 의해 오버라이드됨) |
| **위치** | 프로젝트 루트의 `./CLAUDE.local.md` |

### CLAUDE.local.md 생성하기

```bash
# 템플릿 복사
cp project/CLAUDE.local.md.template CLAUDE.local.md

# 또는 설치 시
./scripts/install.sh
# 프로젝트 설치를 선택하고 CLAUDE.local.md 생성에 'y' 응답
```

### CLAUDE.local.md에 포함할 내용

| 포함할 것 | 포함하지 말 것 |
|-----------|----------------|
| 로컬 서버 URL 및 포트 | 실제 자격 증명이나 비밀 정보 |
| 머신별 경로 | 팀원들에게 필요한 정보 |
| 개인 워크플로우 선호도 | 중요한 프로젝트 설정 |
| 디버그/개발 오버라이드 | API 키 또는 토큰 |

### 예시 내용

```markdown
# 개인 프로젝트 설정

## 로컬 환경
- API 서버: http://localhost:3000
- 데이터베이스: localhost:5432

## 개인 선호도
- 에디터: VSCode
- 테마: Dark+

## 임시 오버라이드
- 작업 중: feature/authentication
- 상세 로깅: 활성화
```

### .gitignore 확인하기

`CLAUDE.local.md`가 제대로 무시되는지 확인:

```bash
# gitignore 확인
git check-ignore CLAUDE.local.md

# 출력: CLAUDE.local.md
```

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

## Commands

`.claude/commands/`에 있는 커스텀 슬래시 명령어로 자주 사용하는 작업의 단축키를 제공합니다.

### 사용 가능한 Commands

| Command | 설명 |
|---------|------|
| `/pr-review [NUMBER]` | 보안, 성능, 품질 분석을 포함한 종합적 PR 리뷰 |
| `/code-quality [PATH]` | 코드 품질 분석 및 개선 제안 |
| `/git-status` | 실행 가능한 인사이트가 포함된 향상된 git status |

### 커스텀 Command 만들기

1. `.claude/commands/`에 마크다운 파일 생성
2. 사용법, 지침, 출력 형식 정의
3. `/command-name`으로 사용

---

## 글로벌 Skills

글로벌 Skills는 `~/.claude/skills/`에 설치되어 모든 프로젝트에서 사용 가능합니다.
v1.5.0에서 기존 명령어(commands)가 Skills 형식으로 마이그레이션되어 컨텍스트 격리와 모델 오버라이드를 지원합니다.

### 사용 가능한 글로벌 Skills

| Skill | 설명 | 예시 |
|-------|------|------|
| `/branch-cleanup` | 병합/오래된 브랜치 정리 | `/branch-cleanup [project] --dry-run` |
| `/release` | 자동 changelog 생성 릴리스 | `/release 1.2.0` |
| `/issue-create` | 5W1H 기반 GitHub 이슈 생성 | `/issue-create myproject --type bug` |
| `/issue-work` | GitHub 이슈 워크플로우 자동화 | `/issue-work myproject` |
| `/pr-work` | PR CI/CD 실패 분석 및 수정 | `/pr-work 42` |
| `/doc-review` | 마크다운 문서 리뷰 (앵커, 정확성, SSOT) | `/doc-review docs/` |
| `/implement-all-levels` | 모든 티어 완전 구현 강제 | `/implement-all-levels feature` |
| `/harness` | Agent team & skill 아키텍처 설계 | `/harness [domain-or-project-description]` |

### Skill 상세

#### `/branch-cleanup`
```bash
/branch-cleanup [<project-name>] [--dry-run] [--include-remote] [--stale-days <days>]
```
- `--dry-run`: 삭제 없이 미리보기
- `--include-remote`: 원격 추적 브랜치도 정리
- `--stale-days`: 오래된 것으로 간주할 일수 (기본: 90)

#### `/release`
```bash
/release <version> [--draft] [--prerelease] [--org <organization>]
```
- 마지막 릴리스 이후 커밋에서 changelog 자동 생성
- 시맨틱 버저닝 지원 (예: 1.2.0, 2.0.0-beta.1)

#### `/issue-create`
```bash
/issue-create <project-name> [--type <type>] [--priority <priority>]
```
- 타입: bug, feature, refactor, docs
- 우선순위: critical, high, medium, low
- 5W1H 프레임워크로 구조화된 이슈 생성

#### `/issue-work`
```bash
/issue-work <project-name> [--org <organization>]
```
- 열린 이슈 목록 및 워크플로우 가이드
- git remote에서 organization 자동 감지

#### `/pr-work`
```bash
/pr-work <pr-number> [--org <organization>]
```
- 실패한 CI/CD 워크플로우 분석
- 수정 제안 및 구현 지원

#### `/doc-review`
```bash
/doc-review [docs-directory] [--scope anchors|accuracy|ssot|all] [--fix]
```
- 마크다운 앵커, 정확성, SSOT 검증
- `--fix`: 감지된 문제 자동 수정

#### `/implement-all-levels`
```bash
/implement-all-levels <feature-description>
```
- 계층형 기능의 부분 구현 방지
- 모든 난이도/티어에 걸쳐 완전 구현 강제

#### `/harness`
```bash
/harness [domain-or-project-description]
```
- 도메인별 Agent team 아키텍처 설계
- 6가지 패턴: Pipeline, Fan-out/Fan-in, Expert Pool, Producer-Reviewer, Supervisor, Hierarchical
- `.claude/agents/` 정의 및 `.claude/skills/` 자동 생성
- 설계 패턴, 테스트, QA 레퍼런스 문서 포함

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
allowed-tools:
  - Read
  - Edit
temperature: 0.3
---
```

---

## Agent Teams

Agent Teams는 여러 Claude 인스턴스가 공유 작업 목록과 다이렉트 메시징을 통해 복잡한 작업을 병렬로 수행할 수 있게 합니다.

> **상태**: 실험적 기능. 기능 플래그 활성화가 필요합니다.

### 빠른 시작

1. 기능 플래그 활성화 (이 설정의 `settings.json`에 이미 포함):
   ```json
   {
     "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
     "teammateMode": "in-process"
   }
   ```

2. 자연어로 팀 시작:
   ```
   Create a team to implement the notification system:
   - Teammate "backend": API endpoints
   - Teammate "frontend": UI components
   - Teammate "tests": Integration tests
   ```

### 표시 모드

| 모드 | 동작 | CLI 플래그 |
|------|------|-----------|
| `auto` | tmux/iTerm2 가능 시 분할 패널, 그외 in-process | `--teammate-mode auto` |
| `in-process` | 모든 팀원이 같은 터미널에서 동작 | `--teammate-mode in-process` |
| `tmux` | tmux를 통한 분할 패널 표시 | `--teammate-mode tmux` |

### 키보드 단축키 (In-Process 모드)

| 단축키 | 동작 |
|--------|------|
| `Shift+Down` | 팀원 간 순환 |
| `Ctrl+T` | 공유 작업 목록 접근 |
| `Enter` | 포커스된 팀원에게 메시지 전송 |
| `Escape` | 리드 에이전트로 포커스 복귀 |

### 팀 제한

`MAX_TEAMS`를 통해 최대 동시 팀 수를 제어합니다 (기본값: `5`):

```json
{ "env": { "MAX_TEAMS": "5" } }
```

`TeamCreate`에 대한 `PreToolUse` hook이 `~/.claude/teams/`의 디렉토리 수를 확인하고 제한 도달 시 생성을 차단합니다.

### Team Hooks

| Hook | 목적 | 결정 제어 |
|------|------|----------|
| `TeamCreate` (PreToolUse) | `MAX_TEAMS` 제한 적용 | JSON `permissionDecision: deny`로 생성 차단 |
| `TeammateIdle` | 팀원이 작업을 마치고 유휴 상태가 될 때 실행 | Exit code 2로 유휴 차단 |
| `TaskCompleted` | 팀원이 작업을 완료할 때 실행 | Exit code 2로 완료 차단 |

### 모범 사례

- 파일 충돌을 피하기 위해 각 팀원에게 별도의 파일 세트를 할당
- 스폰 프롬프트에 컨텍스트(파일 경로, 이슈 번호) 포함
- 위험한 변경에 대해 계획 승인 사용
- 최적의 조정을 위해 팀을 2-3명으로 유지
- `Ctrl+T`로 모든 팀원의 진행 상황 추적

전체 설정 가이드는 `rules/workflow/reference/agent-teams.md`를 참조하세요.

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

## Skills

이 설정은 작업 컨텍스트에 따라 가이드라인을 자동 검색하는 Claude Code Skills를 포함합니다.

### 프로젝트 Skills (컨텍스트 기반)

작업 컨텍스트에 따라 자동 트리거되는 스킬:

| Skill | 설명 | 트리거 키워드 |
|-------|------|---------------|
| **coding-guidelines** | 코딩 표준, 품질, 에러 처리 | implement, add, create, fix, refactor, review |
| **security-audit** | 보안 가이드라인, OWASP Top 10, 입력 검증 | auth, token, password, secret, security, XSS, CSRF |
| **performance-review** | 성능 최적화, 프로파일링, 캐싱 | slow, optimize, benchmark, profile, latency, cache |
| **api-design** | API 설계, 아키텍처, 로깅, 관찰성 | REST, GraphQL, API, microservice, endpoint, SOLID |
| **project-workflow** | 워크플로우, git 커밋, 이슈, PR, 테스트 | commit, PR, issue, build, test, workflow, git |
| **documentation** | README, API 문서, 주석, 정리 | document, README, comment, changelog, format, lint |
| **ci-debugging** | CI/CD 실패 진단 및 해결 | CI fail, GitHub Actions, TLS, pipeline |

### 프로젝트 Skills (사용자 호출형)

`/skill-name` 명령어로 명시적으로 호출:

| Skill | 설명 | 사용법 |
|-------|------|--------|
| **code-quality** | 코드 품질 분석, 복잡도, SOLID | `/code-quality <file-or-directory>` |
| **git-status** | Git 상태 및 액션 인사이트 | `/git-status` |
| **pr-review** | 종합 PR 리뷰 | `/pr-review <pr-number>` |

### Skills 동작 방식

1. Skills는 `.claude/skills/` 디렉토리에서 자동 검색됩니다
2. 각 skill은 name과 description을 정의하는 YAML frontmatter가 있는 `SKILL.md`를 가집니다
3. 컨텍스트 기반 스킬은 작업 키워드에 따라 자동 활성화됩니다
4. 사용자 호출형 스킬은 `/skill-name`으로 명시적으로 트리거됩니다
5. `argument-hint`, `model`, `allowed-tools` frontmatter를 지원합니다

<details>
<summary>Progressive Disclosure 패턴 & Skill 구조</summary>

### Progressive Disclosure 패턴

Skills는 토큰 효율성을 위해 Progressive Disclosure 패턴을 사용합니다:

1. **SKILL.md**: 핵심 정보만 포함 (~50줄)
2. **reference/**: 상세 가이드라인 파일에 대한 심볼릭 링크
3. **온디맨드 로딩**: Claude는 필요할 때만 reference 파일을 읽습니다

```
skills/coding-guidelines/
├── SKILL.md              # 핵심 정보 (~37줄)
└── reference/            # 상세 가이드라인 심볼릭 링크
    ├── general.md        → .claude/rules/coding/general.md
    ├── quality.md        → .claude/rules/coding/quality.md
    ├── error-handling.md → .claude/rules/coding/error-handling.md
    └── ...
```

**장점:**
- 초기 로드 토큰: ~5000 → ~1000 (80% 감소)
- 안정적인 로딩을 위한 1-level deep 참조
- 간소화된 경로 관리

### Skill 구조

```yaml
---
name: skill-name
description: 자동 검색을 위한 설명 (최대 1024자)
allowed-tools: Read, Grep, Glob  # 선택사항: 도구 제한
---

# Skill 제목

## 사용 시점
- 사용 케이스 1
- 사용 케이스 2

## 빠른 참조
- [가이드라인 링크](reference/guideline.md)
```

</details>

---

## Skills vs Rules 아키텍처

이 프로젝트는 Skills와 Rules 두 시스템을 함께 사용합니다. 각 시스템은 서로 다른 목적으로 설계되었습니다.

### 비교표

| 측면 | Skills | Rules |
|------|--------|-------|
| **위치** | `.claude/skills/<name>/SKILL.md` | `.claude/rules/<name>.md` |
| **활성화** | 컨텍스트 키워드 (모델 기반) | 파일 경로 (paths frontmatter) |
| **질문** | "이 작업을 어떻게 해야 하나요?" | "이 파일에 무엇이 적용되나요?" |
| **예시** | 보안 감사 요청 → security-audit 스킬 | `*.test.ts` 편집 → testing 규칙 |

### 언제 무엇을 사용할까요?

**Skills 사용 (작업 유형 기반)**:
- "보안 리뷰 해주세요" → `security-audit` 스킬
- "성능 최적화 방법" → `performance-review` 스킬
- "API 설계 검토" → `api-design` 스킬

**Rules 사용 (파일 경로 기반)**:
- `src/api/*.ts` 편집 → `api/rest-api.md` 규칙 자동 로드
- `tests/*.test.ts` 편집 → `testing.md` 규칙 자동 로드
- `*.md` 편집 → `documentation.md` 규칙 자동 로드

### 토큰 효율성

이 듀얼 시스템 접근 방식은 최적의 토큰 효율성을 제공합니다:
- **Skills**: 비활성 시 ~100-200 토큰 (description만 로드)
- **Rules**: 파일 경로 매칭 시에만 로드

자세한 분석은 [아키텍처 리뷰 문서](docs/architecture-review-skills-rules.md)를 참조하세요.

---

## 스크립트 설명

### 1. install.sh / install.ps1

**목적:** 백업된 설정을 새 시스템에 설치

**기능:**
- 글로벌 설정 설치 (`~/.claude/`)
- 프로젝트 설정 설치 (지정한 디렉토리)
- Skills 디렉토리 설치 (`.claude/skills/`)
- 기존 파일 자동 백업
- 설치 타입 선택 (글로벌/프로젝트/둘 다/Enterprise/전체)

**사용법:**
```bash
# macOS/Linux
./scripts/install.sh

# Windows (PowerShell 7+)
.\scripts\install.ps1
```

**주의사항:**
- 기존 파일은 `.backup_YYYYMMDD_HHMMSS` 형식으로 백업됨
- Windows: `install.ps1`는 `settings.windows.json`과 `.ps1` hook 스크립트를 자동 배포

---

### 2. backup.sh

**목적:** 현재 시스템의 설정을 백업에 저장

**기능:**
- 글로벌 설정 백업
- 프로젝트 설정 백업
- Skills 디렉토리 백업 (`.claude/skills/`)
- 타임스탬프 백업 생성
- 기존 백업 대체 옵션

**사용법:**
```bash
./scripts/backup.sh
```

**언제 사용:**
- 현재 설정을 다른 시스템에 배포하기 전
- 설정 변경 후 백업 업데이트
- 정기적인 설정 백업

---

### 3. sync.sh

**목적:** 시스템과 백업 사이의 설정 동기화

**기능:**
- 양방향 동기화 (백업 ↔ 시스템)
- Skills 디렉토리 동기화 지원
- 파일 차이점 비교
- 변경 사항 미리보기
- 안전한 백업 생성

**사용법:**
```bash
./scripts/sync.sh
```

**동기화 방향:**
- 1: 백업 → 시스템 (백업 설정을 시스템에 적용)
- 2: 시스템 → 백업 (시스템 설정을 백업에 저장)
- 3: 차이점만 확인 (변경하지 않음)

---

### 4. verify.sh

**목적:** 백업의 무결성과 완전성 확인

**기능:**
- 디렉토리 구조 검증
- 필수 파일 존재 확인
- Skills 디렉토리 및 SKILL.md 검증
- 스크립트 실행 권한 확인
- 통계 정보 표시

**사용법:**
```bash
./scripts/verify.sh
```

---

### 5. validate_skills.sh

**목적:** SKILL.md 파일의 형식 준수 여부 검증

**기능:**
- YAML frontmatter 검증
- name 필드 확인 (소문자, 숫자, 하이픈, 최대 64자)
- description 필드 확인 (비어있지 않음, 최대 1024자)
- 파일 라인 수 확인 (500줄 초과 시 경고)
- reference 디렉토리 존재 확인
- 선택적 PyYAML 구문 검증

**사용법:**
```bash
./scripts/validate_skills.sh
```

**검증 규칙:**
| 필드 | 규칙 |
|------|------|
| Frontmatter | `---`로 시작하고 끝나야 함 |
| name | `[a-z0-9-]+`, 최대 64자 |
| description | 비어있지 않음, 최대 1024자 |
| 파일 길이 | 500줄 초과 시 경고 |

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
- **커스텀 확장 가이드**: [docs/CUSTOM_EXTENSIONS.md](docs/CUSTOM_EXTENSIONS.md) - 공식 기능과 커스텀 기능 구분
- **토큰 최적화**: [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md) - 규칙 최적화 (86% 절감)
- **스킬 토큰 리포트**: [docs/SKILL_TOKEN_REPORT.md](docs/SKILL_TOKEN_REPORT.md) - 스킬별 토큰 소모 분석
- **AD-SDLC 통합**: [docs/ad-sdlc-integration.md](docs/ad-sdlc-integration.md) - AI 에이전트 기반 SDLC 통합
- **문제 해결**: 각 스크립트의 에러 메시지 확인

---

## 주의사항

1. **개인정보 보호**
   - `git-identity.md`는 개인 정보 포함
   - Public 리포지토리 사용 시 주의!

2. **백업 전 확인**
   - 중요한 변경 전 항상 백업
   - 덮어쓰기 전 차이점 확인

3. **프로젝트 설정**
   - 프로젝트별로 적절히 커스터마이즈
   - 팀과 공유 시 합의 필요

---

## 버전

- **Version**: 1.6.0
- **Last Updated**: 2026-04-03

### 변경 이력

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
  - `argument-hint`, `model`, `allowed-tools`, adaptive execution frontmatter 지원
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
- Hook 이벤트 확장, `allowed-tools`/`model` 옵션 추가

#### v1.0.0 (2025-12-03)
- 글로벌 및 프로젝트 설정으로 초기 릴리스
- Progressive Disclosure 패턴의 Claude Code Skills
- 보안 및 자동 포매팅용 Hook 설정

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
