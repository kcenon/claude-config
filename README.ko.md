# Claude Configuration Backup & Deployment System

<p align="center">
  <a href="https://github.com/kcenon/claude-config/releases"><img src="https://img.shields.io/badge/version-1.3.0-blue.svg" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-green.svg" alt="License"></a>
  <a href="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml"><img src="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>여러 시스템 간에 CLAUDE.md 설정을 쉽게 공유하고 동기화하는 도구</strong>
</p>

<p align="center">
  <a href="#빠른-시작">빠른 시작</a> •
  <a href="#원라인-설치">설치</a> •
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

| 작업 | 명령어 |
|------|--------|
| 설정 백업 | `./scripts/backup.sh` |
| 설정 동기화 | `./scripts/sync.sh` |
| 백업 검증 | `./scripts/verify.sh` |

상세 시나리오는 [사용 시나리오](#사용-시나리오)를 참조하세요.

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

---

## 구조

<details>
<summary>디렉토리 구조 펼치기</summary>

```
claude_config_backup/
├── global/                      # 글로벌 설정 백업 (~/.claude/)
│   ├── CLAUDE.md               # 메인 설정 파일
│   ├── settings.json           # Hook 설정 (보안, 세션, UserPromptSubmit, Stop)
│   ├── commit-settings.md      # 커밋/PR 정책 (Claude 정보 비활성화)
│   ├── conversation-language.md # 대화 언어 설정
│   ├── git-identity.md         # Git 사용자 정보
│   ├── token-management.md     # 토큰 관리 정책
│   └── commands/               # 글로벌 슬래시 명령어
│       ├── _policy.md          # 모든 명령어 공통 정책
│       ├── branch-cleanup.md   # /branch-cleanup 명령어
│       ├── issue-create.md     # /issue-create 명령어
│       ├── issue-work.md       # /issue-work 명령어
│       ├── pr-work.md          # /pr-work 명령어
│       └── release.md          # /release 명령어
│
├── project/                     # 프로젝트 설정 백업
│   ├── CLAUDE.md               # 프로젝트 메인 설정
│   ├── CLAUDE.local.md.template # 로컬 설정 템플릿 (커밋 제외)
│   ├── .mcp.json               # MCP 서버 설정 템플릿
│   ├── .claude/
│   │   ├── settings.json       # Hook 설정 (자동 포맷팅)
│   │   ├── settings.local.json.template  # 로컬 설정 템플릿
│   │   ├── rules/              # 경로 기반 조건부 규칙
│   │   │   ├── coding.md       # 코딩 표준 (코드 파일에 자동 로드)
│   │   │   ├── testing.md      # 테스트 표준 (테스트 파일에 자동 로드)
│   │   │   ├── security.md     # 보안 가이드라인
│   │   │   ├── documentation.md # 문서화 표준
│   │   │   └── api/
│   │   │       └── rest-api.md # REST API 디자인 패턴
│   │   ├── commands/           # 사용자 정의 슬래시 명령어
│   │   │   ├── pr-review.md    # /pr-review 명령어
│   │   │   ├── code-quality.md # /code-quality 명령어
│   │   │   └── git-status.md   # /git-status 명령어
│   │   ├── agents/             # 특화 에이전트 설정
│   │   │   ├── code-reviewer.md
│   │   │   ├── documentation-writer.md
│   │   │   └── refactor-assistant.md
│   │   └── skills/             # Claude Code Skills
│   │       ├── coding-guidelines/
│   │       │   ├── SKILL.md    # 코딩 표준 스킬
│   │       │   └── reference/  # 가이드라인 심볼릭 링크
│   │       ├── security-audit/
│   │       │   ├── SKILL.md    # 보안 감사 스킬
│   │       │   └── reference/  # 가이드라인 심볼릭 링크
│   │       ├── performance-review/
│   │       │   ├── SKILL.md    # 성능 리뷰 스킬
│   │       │   └── reference/  # 가이드라인 심볼릭 링크
│   │       ├── api-design/
│   │       │   ├── SKILL.md    # API 및 아키텍처 스킬
│   │       │   └── reference/  # 가이드라인 심볼릭 링크
│   │       ├── project-workflow/
│   │       │   ├── SKILL.md    # 워크플로우 및 프로젝트 관리 스킬
│   │       │   └── reference/  # 가이드라인 심볼릭 링크
│   │       └── documentation/
│   │           ├── SKILL.md    # 문서화 표준 스킬
│   │           └── reference/  # 가이드라인 심볼릭 링크
│   └── claude-guidelines/      # 가이드라인 모듈
│       ├── api-architecture/   # API 및 아키텍처
│       │   ├── api-design.md
│       │   ├── architecture.md
│       │   ├── logging.md
│       │   └── observability.md
│       ├── coding-standards/   # 코딩 표준
│       │   ├── general.md
│       │   ├── quality.md
│       │   ├── error-handling.md
│       │   ├── concurrency.md
│       │   ├── memory.md
│       │   └── performance.md
│       ├── project-management/ # 프로젝트 관리
│       │   ├── build.md
│       │   ├── testing.md
│       │   └── documentation.md
│       ├── operations/         # 운영
│       │   ├── monitoring.md
│       │   └── cleanup.md
│       ├── communication.md
│       ├── environment.md
│       ├── git-commit-format.md
│       ├── problem-solving.md
│       ├── security.md
│       ├── workflow.md
│       └── conditional-loading.md
│
├── scripts/                     # 자동화 스크립트
│   ├── install.sh              # 새 시스템에 설치
│   ├── backup.sh               # 현재 설정 백업
│   ├── sync.sh                 # 설정 동기화
│   ├── verify.sh               # 백업 무결성 검증
│   └── validate_skills.sh      # SKILL.md 파일 검증
│
├── hooks/                       # Git hooks
│   ├── pre-commit              # 커밋 전 스킬 검증
│   └── install-hooks.sh        # Hook 설치 스크립트
│
├── .github/
│   └── workflows/
│       └── validate-skills.yml # CI 스킬 검증
│
├── plugin/                      # Claude Code Plugin (Beta)
│   ├── .claude-plugin/
│   │   └── plugin.json         # 플러그인 매니페스트
│   ├── skills/                 # 독립형 스킬 (심볼릭 링크 없음)
│   └── hooks/                  # 플러그인 후크
│
├── bootstrap.sh                 # 원라인 설치 스크립트
├── README.md                    # 상세 가이드 (영문)
├── README.ko.md                 # 상세 가이드 (한글)
├── QUICKSTART.md               # 빠른 시작 가이드
└── HOOKS.md                    # Hook 설정 가이드
```

</details>

---

## 글로벌 명령어

글로벌 명령어는 `~/.claude/commands/`에 설치되어 모든 프로젝트에서 사용 가능합니다.

### 사용 가능한 글로벌 명령어

| 명령어 | 설명 | 예시 |
|--------|------|------|
| `/branch-cleanup` | 병합/오래된 브랜치 정리 | `/branch-cleanup --dry-run` |
| `/release` | 자동 changelog 생성 릴리스 | `/release 1.2.0` |
| `/issue-create` | 5W1H 기반 GitHub 이슈 생성 | `/issue-create myproject --type bug` |
| `/issue-work` | GitHub 이슈 워크플로우 자동화 | `/issue-work myproject` |
| `/pr-work` | PR CI/CD 실패 분석 및 수정 | `/pr-work myproject 42` |

### 명령어 상세

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
/pr-work <project-name> <pr-number> [--org <organization>]
```
- 실패한 CI/CD 워크플로우 분석
- 수정 제안 및 구현 지원

---

## Skills

이 설정은 작업 컨텍스트에 따라 가이드라인을 자동 검색하는 Claude Code Skills를 포함합니다.

### 사용 가능한 Skills

| Skill | 설명 | 트리거 키워드 |
|-------|------|---------------|
| **coding-guidelines** | 코딩 표준, 품질, 에러 처리 | implement, add, create, fix, refactor, review |
| **security-audit** | 보안 가이드라인, OWASP Top 10, 입력 검증 | auth, token, password, secret, security, XSS, CSRF |
| **performance-review** | 성능 최적화, 프로파일링, 캐싱 | slow, optimize, benchmark, profile, latency, cache |
| **api-design** | API 설계, 아키텍처, 로깅, 관찰성 | REST, GraphQL, API, microservice, endpoint, SOLID |
| **project-workflow** | 워크플로우, git 커밋, 이슈, PR, 테스트 | commit, PR, issue, build, test, workflow, git |
| **documentation** | README, API 문서, 주석, 정리 | document, README, comment, changelog, format, lint |

### Skills 동작 방식

1. Skills는 `.claude/skills/` 디렉토리에서 자동 검색됩니다
2. 각 skill은 name과 description을 정의하는 YAML frontmatter가 있는 `SKILL.md`를 가집니다
3. Skills는 요청의 트리거 키워드에 따라 활성화됩니다
4. Skills는 상세 가이드라인에 대한 빠른 참조 링크를 제공합니다

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
    ├── general.md        → claude-guidelines/coding-standards/general.md
    ├── quality.md        → claude-guidelines/coding-standards/quality.md
    ├── error-handling.md → claude-guidelines/coding-standards/error-handling.md
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

### 1. install.sh

**목적:** 백업된 설정을 새 시스템에 설치

**기능:**
- 글로벌 설정 설치 (`~/.claude/`)
- 프로젝트 설정 설치 (지정한 디렉토리)
- Skills 디렉토리 설치 (`.claude/skills/`)
- 기존 파일 자동 백업
- 설치 타입 선택 (글로벌/프로젝트/둘 다)

**사용법:**
```bash
./scripts/install.sh
```

**주의사항:**
- ⚠️ 설치 후 `git-identity.md`를 반드시 개인 정보로 수정!
- 기존 파일은 `.backup_YYYYMMDD_HHMMSS` 형식으로 백업됨

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
cp -r ~/project/claude-guidelines ~/claude_config_backup/project/
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

- **Claude Code 사용 가이드**: 프로젝트 내 `CLAUDE_CODE_REAL_GUIDE.md`
- **설정 예제**: `global/` 및 `project/` 디렉토리 참조
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

- **Version**: 1.3.0
- **Last Updated**: 2026-01-15

### 변경 이력

#### v1.3.0 (2026-01-15)
- 자동 changelog 생성을 위한 `/release` 명령어 추가
- 병합/오래된 브랜치 정리를 위한 `/branch-cleanup` 명령어 추가
- 5W1H 프레임워크 기반 `/issue-create` 명령어 추가
- GitHub 워크플로우 자동화를 위한 `/issue-work`, `/pr-work` 명령어 추가
- 공유 명령어 규칙을 위한 공통 정책 파일 (`_policy.md`) 추가
- 모든 글로벌 명령어가 공유 정책 참조하도록 업데이트

#### v1.2.0 (2026-01-15)
- 공식 베스트 프랙티스 준수를 위한 CLAUDE.md 최적화
- project/CLAUDE.md 간소화 (212 → ~85줄)
- 핵심 규칙에 강조 표현 추가
- common-commands.md 생성
- conditional-loading.md 최적화
- Progressive Disclosure 적용한 github-issue-5w1h.md 분리

#### v1.1.0 (2025-01-15)
- 경로 기반 조건부 로딩을 지원하는 `.claude/rules/` 디렉토리 추가
- 사용자 정의 슬래시 명령어를 위한 `.claude/commands/` 추가
- 특화 에이전트 설정을 위한 `.claude/agents/` 추가
- MCP 설정 템플릿 (`.mcp.json`) 추가
- 로컬 설정 템플릿 (`CLAUDE.local.md.template`, `settings.local.json.template`) 추가
- `UserPromptSubmit`, `Stop` 이벤트 훅 추가
- 모든 settings.json에 `alwaysThinkingEnabled` 설정 추가
- 모든 SKILL.md에 `allowed-tools`, `model` 옵션 추가

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

---

**Happy Coding with Claude!**
