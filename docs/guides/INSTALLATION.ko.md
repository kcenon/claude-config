# 설치 안내

첫 화면을 짧게 두려고 [README](../../README.ko.md)에서 옮겼습니다. English: [INSTALLATION.md](INSTALLATION.md).

## 원라인 설치

### Public Repository

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex
```

> **bootstrap이 자동으로 처리하는 것.** Claude Code CLI 미설치 시 사용자 동의 후 Anthropic 공식 native installer(`https://claude.ai/install.sh`)를 실행해 `claude` 바이너리를 `~/.local/bin/`에 배치하고 백그라운드 자동 업데이트를 활성화합니다. npm 패키지 `@anthropic-ai/claude-code`는 더 이상 사용되지 않습니다. PowerShell은 `claude.ai/install.ps1`로 동일하게 동작합니다. 자세한 내용은 [PREREQUISITES.md → Auto-installed by bootstrap](../../PREREQUISITES.md#auto-installed-by-bootstrap).

### 비대화형 설치

CI·무인 설치 환경에서는 `scripts/install.sh`와 동일한 환경 변수로 응답을 미리
지정하거나(프롬프트 없음), `--yes`로 모든 기본값을 강제할 수 있습니다:

```bash
# 무인 설치: 설치 타입만 env로 지정하고 나머지는 기본값 사용
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | INSTALL_TYPE=3 bash

# 모든 프롬프트를 기본값으로 강제
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash -s -- --yes
```

```powershell
# 무인 설치: 설치 타입만 env로 지정하고 나머지는 기본값 사용
$env:INSTALL_TYPE = '3'; irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex

# 모든 프롬프트를 기본값으로 강제
$env:FORCE_MODE = '1'; irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex
```

인식되는 오버라이드: `INSTALL_TYPE`, `PROJECT_DIR`, `INSTALL_NPM`, `OVERWRITE`,
`AGENT_LANGUAGE`, `CONTENT_LANGUAGE`. PowerShell은 Bash의 `--yes`와 같은
기본값 강제 무인 경로로 `FORCE_MODE=1`도 인식합니다. `curl | bash`로
대화형 실행 시, bootstrap은 스크립트 본문 대신 `/dev/tty`에서 응답을 읽습니다.

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

# 3. Git identity 확인 (누락되었거나 틀린 경우에만 수정)
grep -E "^(name|email):" ~/.claude/git-identity.md
```

### Plugin 설치 (Beta)

Claude Code Plugin으로 설치하여 쉽게 배포하고 업데이트할 수 있습니다:

```bash
# 마켓플레이스 추가
/plugin marketplace add kcenon/claude-config

# 플러그인 설치 (마켓플레이스: kcenon-plugins)
/plugin install claude-config@kcenon-plugins
```

또는 로컬에서 테스트:

```bash
# 플러그인 직접 로드 (개발/테스트용)
claude --plugin-dir ./plugin
```

자세한 내용은 [plugin/README.md](../../plugin/README.md)를 참조하세요.

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

#### Docker 호환 dual-variant 설치

`install.ps1`은 모든 hook 및 유틸리티 스크립트의 PowerShell(`.ps1`)·bash(`.sh`) 변종을 **둘 다** `~/.claude/hooks/`와 `~/.claude/scripts/`에 배포합니다. `.sh` 파일은 LF 줄바꿈(UTF-8, BOM 없음)으로 작성됩니다.

이는 Windows 호스트의 `~/.claude/`가 Linux Claude Code 컨테이너에 bind-mount될 때(예: 동반 [claude-docker](https://github.com/kcenon/claude-docker) 프로젝트) 중요합니다: 컨테이너 entrypoint가 `pwsh ... -File foo.ps1` hook 명령을 `foo.sh`로 재작성하는데, 마운트에 대응 `.sh` 파일이 있어야만 동작합니다. 설치 스크립트는 페어링 감사를 실행해 `.sh` 짝이 없는 `.ps1`(또는 그 반대)을 경고하여 Docker 측 재작성이 누락 파일로 조용히 해석되지 않게 합니다.

### 경량 Plugin (Behavioral Guardrails Only)

전체 구성 없이 핵심 동작 교정만 원하시나요?

```bash
# lite plugin 설치 (마켓플레이스: kcenon-plugins)
claude plugin marketplace add kcenon/claude-config
claude plugin install claude-config-lite@kcenon-plugins

# 또는 로컬 테스트
claude --plugin-dir ./plugin-lite
```

| 방식 | 포함 내용 |
|------|----------|
| Full plugin | 모든 스킬, 에이전트, 훅을 포함한 전체 설정 |
| **Lite plugin** | LLM 코딩 실수를 위한 핵심 동작 가드레일 |
| Bootstrap 스크립트 | ~/.claude/에 배포되는 전체 시스템 설정 |

자세한 내용은 [plugin-lite/README.md](../../plugin-lite/README.md)를 참조하세요.

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

두 설치기 모두 이 트리의 SHA-256 매니페스트를 `<enterprise-dir>/.install-manifest.json`에 기록합니다. 따라서 재설치가 로컬에서 편집한 정책 파일을 덮어쓰지 않고 보존하며, 드리프트 점검이 낡은 배포와 편집된 파일을 구분할 수 있습니다. 프롬프트 없이 덮어쓰려면 `BOOTSTRAP_FORCE=1`을 설정하세요. POSIX에서는 enterprise 루트에 쓰기 권한이 없을 때 복사와 매니페스트 배치가 `sudo`를 거치며, 매니페스트 자체는 읽기 가능하게 남겨 두어 감사에 권한이 필요 없습니다. 퇴역한 규칙은 삭제되지 않습니다. [docs/install.md](../../docs/install.md)를 참고하세요.

## 개인 설정 (CLAUDE.local.md)

버전 관리에 포함되지 않아야 하는 머신별 설정은 프로젝트 루트에 `CLAUDE.local.md`를 생성하세요.

```bash
# 템플릿 복사
cp project/CLAUDE.local.md.template CLAUDE.local.md
```

로컬 서버 URL, 머신별 경로, 개인 워크플로우 선호도에 사용하세요. 자격 증명이나 API 키는 여기에 넣지 **마세요** — 환경 변수를 사용하세요.

이 파일은 gitignore되며 Claude Code의 메모리 계층에서 가장 낮은 우선순위를 가집니다.

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
GITHUB_REF=v1.14.0 \
INSTALL_DIR=~/my-claude-config \
bash -c "$(curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh)"
```

| 변수 | 기본값 | 목적 |
|------|--------|------|
| `GITHUB_USER` | `kcenon` | 저장소를 소유한 GitHub user/org |
| `GITHUB_REPO` | `claude-config` | 저장소 이름 |
| `GITHUB_REF` | 최신 release tag (예: `v1.14.0`) | clone할 tag, branch, commit. tag pinning은 SLSA-aligned supply-chain hardening으로 설치를 재현 가능하게 하고 `main`의 일시적 손상에 덜 취약하게 만듭니다. 개발 테스트에만 `develop`으로 override하세요. |
| `INSTALL_DIR` | `~/claude_config_backup` | 저장소를 clone할 위치 |

> **Deprecated**: `GITHUB_BRANCH`는 `GITHUB_REF`의 한 release alias로 보존되며, 설정 시 stderr deprecation warning을 출력합니다. 다음 major release 전 `GITHUB_REF`로 이전하세요.

</details>
