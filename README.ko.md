# Claude Configuration Backup & Deployment System

<p align="center">
  <strong>여러 시스템 간에 CLAUDE.md 설정을 쉽게 공유하고 동기화하는 도구</strong>
</p>

<p align="center">
  <a href="#원라인-설치">원라인 설치</a> •
  <a href="#구조">구조</a> •
  <a href="#스크립트-설명">스크립트</a> •
  <a href="#사용-시나리오">시나리오</a> •
  <a href="#faq">FAQ</a> •
  <a href="README.md">English</a>
</p>

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

```
claude_config_backup/
├── global/                      # 글로벌 설정 백업 (~/.claude/)
│   ├── CLAUDE.md               # 메인 설정 파일
│   ├── commit-settings.md      # 커밋/PR 정책 (Claude 정보 비활성화)
│   ├── conversation-language.md # 대화 언어 설정
│   ├── git-identity.md         # Git 사용자 정보
│   └── token-management.md     # 토큰 관리 정책
│
├── project/                     # 프로젝트 설정 백업
│   ├── CLAUDE.md               # 프로젝트 메인 설정
│   ├── .claude/
│   │   ├── settings.json       # Hook 설정 (자동 포맷팅)
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
└── QUICKSTART.md               # 빠른 시작 가이드
```

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

---

## 빠른 시작

### 시나리오 1: 새 시스템에 설정 설치

```bash
# 1. 저장소 클론
git clone https://github.com/kcenon/claude-config.git ~/claude_config_backup

# 2. 설치 실행
cd ~/claude_config_backup
./scripts/install.sh

# 3. Git identity 개인화 (필수!)
vi ~/.claude/git-identity.md

# 4. Claude Code 재시작
```

### 시나리오 2: 현재 설정 백업

```bash
cd ~/claude_config_backup
./scripts/backup.sh

# 타입 선택:
#  1) 글로벌 설정만
#  2) 프로젝트 설정만
#  3) 둘 다 (권장)
```

### 시나리오 3: 설정 동기화

```bash
cd ~/claude_config_backup
./scripts/sync.sh

# 방향 선택:
#  1) 백업 → 시스템
#  2) 시스템 → 백업
#  3) 차이점만 확인
```

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

- **Version**: 1.0.0
- **Last Updated**: 2025-12-03

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
