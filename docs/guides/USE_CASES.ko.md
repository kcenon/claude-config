# 사용 시나리오와 FAQ

첫 화면을 짧게 두려고 [README](../../README.ko.md)에서 옮겼습니다. English: [USE_CASES.md](USE_CASES.md).

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
git clone YOUR_PROJECT_REPO_URL project
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

# Git identity 확인; 누락되었거나 틀린 경우에만 수정
grep -E "^(name|email):" ~/.claude/git-identity.md
```

---

### 시나리오 D: 열린 이슈 또는 실패 PR 일괄 처리

각 항목마다 새 `claude` 프로세스를 띄우는 외부 오케스트레이터입니다. 한 프로세스가 정확히 하나의 이슈(또는 PR)를 처리하므로 항목 사이에 컨텍스트 상태가 누출될 수 없습니다 — 항목 N+1은 항목 1과 동일한 CLAUDE.md / 스킬 attention pool로 시작합니다. `/issue-work`와 `/pr-work`의 in-session 배치 모드를 보완하며, 격리를 OS 프로세스 경계로 끌어올립니다.

다음 상황에서 사용하세요:

- 배치가 in-session 안전 캡(기본 5, `--force-large` 없을 때 하드 캡 10)을 초과할 것으로 예상되고 항목별로 더 엄격한 격리를 원할 때
- 무인 운영(cron, CI, 야간) 중이며 배치가 얼마나 길게 돌아가든 각 항목이 깨끗한 상태에서 시작하기를 원할 때
- 라이브 터미널의 단일 스크롤백이 아닌 사후 분석용 항목별 디스크 로그가 필요할 때

```bash
# 저장소에서 최대 5개의 열린 이슈 처리 (기본 limit)
./scripts/batch-issue-work.sh kcenon/claude-config

# 최대 3개 이슈 처리
./scripts/batch-issue-work.sh kcenon/claude-config 3

# 실패한 PR을 대신 처리
./scripts/batch-pr-work.sh kcenon/claude-config
```

```powershell
# PowerShell 동등 명령
.\scripts\batch-issue-work.ps1 -OrgProject kcenon/claude-config
.\scripts\batch-issue-work.ps1 -OrgProject kcenon/claude-config -Limit 3
.\scripts\batch-pr-work.ps1    -OrgProject kcenon/claude-config
```

항목별 로그는 `~/.claude/batch-logs/<timestamp>/`에 기록됩니다:

- `issue-<번호>.log`: `batch-issue-work`이 처리한 각 이슈
- `pr-<번호>.log`: `batch-pr-work`이 처리한 각 PR

항목 실패 시 배치는 **일시 중지하고 비-0 코드로 종료**합니다. 성공한 항목은 롤백되지 않습니다. 실패한 항목의 로그를 확인해 근본 원인을 수정한 뒤 오케스트레이터를 다시 실행하세요 — 이미 머지된 항목은 더 이상 열린 목록에 없으므로 자동으로 건너뜁니다.

---

<details>
<summary><strong>고급 사용법</strong> (GitHub Actions, 환경 변수)</summary>

## FAQ

### Q1: Git identity를 왜 개인화해야 하나요?

**A:** `git-identity.md`는 개인 정보(이름, 이메일)를 포함하므로, 각 설치는 사용자 본인의 값을 사용해야 합니다. 설치 프로그램은 `git config --global user.name` 및 `git config --global user.email` 값이 모두 있으면 자동으로 채우며, 값이 누락되었거나 틀린 경우에만 파일을 수정하면 됩니다.

```bash
vi ~/.claude/git-identity.md
# 설치된 값이 누락되었거나 틀린 경우에만 name과 email 변경
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

**A:** 비공개 포크를 쓰려면 bootstrap이 두 곳에서 포크를 가리켜야 합니다:

1. [Private Repository](INSTALLATION.ko.md#private-repository)처럼 Personal Access Token으로 포크의 `bootstrap.sh`를 받습니다.
   URL에는 포크 소유자를 넣습니다. Token은 GitHub Settings > Developer settings > Personal access tokens에서 만듭니다.
2. 고급 사용법의 *환경 변수로 커스터마이즈*처럼 `GITHUB_USER`를 포크 소유자로 지정합니다(이름을 바꿨다면 `GITHUB_REPO`도).
   지정하지 않으면 bootstrap은 `kcenon/claude-config`를 클론합니다. 포크에 기본 릴리스 태그가 없으면 `GITHUB_REF`도 지정합니다.

bootstrap은 포크를 일반 `git clone`으로 클론합니다. 1단계의 token은 넘어가지 않으므로,
git이 포크에 접근할 자격 증명을 따로 갖고 있어야 합니다(예: credential helper).

## Memory sync (다중 머신)

Memory sync는 Claude Code의 auto-memory를 비공개 git 저장소를 통해 모든 머신 간에 일관되게 유지합니다. 다음 문서를 참조하세요:

Scheduler 자동화는 Unix 전용입니다. macOS는 `launchd`, Linux는 `systemd` user timer를 사용하며, Windows 사용자는 WSL에서 Linux 경로로 실행해야 합니다. Memory sync의 native PowerShell scheduling은 지원하지 않습니다.

- [운영 가이드](../../docs/MEMORY_SYNC.md) — 일상 운영, 문제 해결, 롤백, 충돌 해결
- [위협 모델](../../docs/THREAT_MODEL.md) — 보안 분석, 7가지 위협 카테고리, 5층 방어
- [검증 명세](../../docs/MEMORY_VALIDATION_SPEC.md) — 검증기 계약과 frontmatter 스키마
- [신뢰 모델](../../docs/MEMORY_TRUST_MODEL.md) — 신뢰 계층과 라이프사이클
