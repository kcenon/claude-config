# Claude Configuration Backup & Deployment System

Status: active · Release: [v1.14.0](https://github.com/kcenon/claude-config/releases/tag/v1.14.0) · [English](README.md)

<p align="center">
  <a href="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml"><img src="https://github.com/kcenon/claude-config/actions/workflows/validate-skills.yml/badge.svg" alt="CI"></a>
</p>

<p align="center">
  <strong>여러 시스템 간에 CLAUDE.md 설정을 쉽게 공유하고 동기화하는 도구</strong>
</p>

Claude Code 문서는 `code.claude.com/docs/en/*`로 이동했고, 이 문서의 링크는 새 주소를 씁니다. settings 필드별 안정성 분류는 [COMPATIBILITY.md](COMPATIBILITY.md#settings-field-inventory-and-stability)를 확인하세요.

---

## 빠른 시작

```bash
# 1. 원라인 설치
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash

# 2. Git identity 확인 (가능하면 git config에서 자동 입력)
grep -E "^(name|email):" ~/.claude/git-identity.md

# 3. Claude Code 재시작 - 완료!
```

**주요 명령어:**

| 작업 | macOS/Linux | Windows (PowerShell) |
|------|-------------|----------------------|
| 설정 설치 | `./scripts/install.sh` | `.\scripts\install.ps1` |
| 설정 백업 | `./scripts/backup.sh` | `.\scripts\backup.ps1` |
| 설정 동기화 | `./scripts/sync.sh` | `.\scripts\sync.ps1` |
| 백업 검증 | `./scripts/verify.sh` | `.\scripts\verify.ps1` |
| 열린 이슈 일괄 처리 | `./scripts/batch-issue-work.sh <org/repo>` | `.\scripts\batch-issue-work.ps1 -OrgProject <org/repo>` |
| 실패 PR 일괄 처리 | `./scripts/batch-pr-work.sh <org/repo>` | `.\scripts\batch-pr-work.ps1 -OrgProject <org/repo>` |

상세 시나리오는 [사용 시나리오와 FAQ](docs/guides/USE_CASES.ko.md)를 참조하세요.

---

## 설치하면 무엇이 달라지나요

claude-config을 설치하면 Claude Code에 다음 기능이 즉시 적용됩니다:

**보안** — `.env`, `.pem`, 인증 정보 파일이 자동으로 읽기/쓰기 차단됩니다. `rm -rf /` 같은 위험한 명령도 실행 전에 차단됩니다.

**자동 포맷팅** — 코드 저장 시 자동 포맷: Python (black), TypeScript (prettier), Go (gofmt), Rust (rustfmt), C++ (clang-format), Kotlin (ktlint).

**워크플로우 자동화** — `/issue-work`로 GitHub 이슈를 선택해서 PR 생성까지 한 번에 처리합니다. `/release`는 변경 로그를 자동 생성하고, `/pr-work`는 CI 실패를 진단·수정합니다.

**커밋 품질 관리** — 깨진 마크다운 링크, AI 어트리뷰션, 비표준 커밋 메시지가 저장소에 들어가기 전에 자동으로 검출됩니다.

**컨텐츠 언어 정책 선택** — 설치 시점에 커밋 메시지·PR 본문·문서의 언어를 English (ASCII 및 허용된 English typography) 또는 Korean (산출물 단위 엄격, 인라인 혼용 금지) 중에서 선택합니다. 세 옵션 프리셋 UI는 `CLAUDE_CONTENT_LANGUAGE=english|exclusive_bilingual` 로 매핑되며, 레거시 값 (`korean_plus_english`, `any`) 은 `settings.json` 직접 편집을 통해서만 사용 가능합니다.

**주문형 코드 분석** — `/security-audit`, `/performance-review`, `/code-quality`, `/pr-review`로 필요할 때 전문 분석을 실행합니다.

**에이전트 팀 설계** — `/harness`로 프로젝트에 맞는 멀티 에이전트 아키텍처를 설계하고, 6가지 아키텍처 패턴과 오케스트레이터 템플릿을 활용합니다.

**크로스 플랫폼** — macOS, Linux, Windows (PowerShell) 모두 지원합니다. Memory sync scheduler는 예외적으로 Unix 전용입니다. 자세한 내용은 [`COMPATIBILITY.md`](COMPATIBILITY.md#cross-platform-notes)를 확인하세요.

**필요할 때만 로드** — 규칙과 스킬은 현재 작업에 필요할 때만 로드되고, 자세한 레퍼런스는 요청할 때까지 `.claude/reference/`에 남아 있습니다. [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md)를 참조하세요.

---

## 설치

bootstrap은 고정해 둔 릴리스 태그를 클론하고, Claude Code CLI를 확인한 뒤, 글로벌 설정을 `~/.claude/`에 배포합니다. 선택하면 프로젝트 설정도 배포합니다.

```bash
curl -sSL https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/kcenon/claude-config/main/bootstrap.ps1 | iex
```

이 저장소의 마켓플레이스(`kcenon-plugins`)에서 Claude Code 플러그인으로 설치하려면:

```bash
claude plugin marketplace add kcenon/claude-config
claude plugin install claude-config@kcenon-plugins        # 전체 구성
claude plugin install claude-config-lite@kcenon-plugins   # 행동 가드레일만
```

비대화형 설치, 비공개 포크, Git clone, Windows 참고 사항, Enterprise 설정, `CLAUDE.local.md`, 환경 변수는 [설치 안내](docs/guides/INSTALLATION.ko.md)에 있습니다.

---

## 문서

| 주제 | 문서 |
|------|------|
| 설치, Enterprise·개인 설정, 고급 사용법 | [docs/guides/INSTALLATION.ko.md](docs/guides/INSTALLATION.ko.md) |
| 저장소 구조 | [docs/guides/STRUCTURE.ko.md](docs/guides/STRUCTURE.ko.md) |
| 자동 동작, 규칙, 스킬, 에이전트, MCP, 스크립트, Git hooks | [docs/guides/FEATURES.ko.md](docs/guides/FEATURES.ko.md) |
| 사용 시나리오, FAQ, memory sync | [docs/guides/USE_CASES.ko.md](docs/guides/USE_CASES.ko.md) |
| Hooks 레퍼런스 | [HOOKS.md](HOOKS.md) |
| 사전 요구 사항과 호환성 | [PREREQUISITES.md](PREREQUISITES.md), [COMPATIBILITY.md](COMPATIBILITY.md) |
| 설치기 내부 (manifest, prune, drift) | [docs/install.md](docs/install.md) |
| 브랜치 모델과 릴리스 절차 | [docs/branching-strategy.md](docs/branching-strategy.md) |
| 공식 기능과 커스텀 기능 구분 | [docs/CUSTOM_EXTENSIONS.md](docs/CUSTOM_EXTENSIONS.md) |
| 컨텍스트 크기와 스킬별 소모 | [docs/TOKEN_OPTIMIZATION.md](docs/TOKEN_OPTIMIZATION.md), [docs/SKILL_TOKEN_REPORT.md](docs/SKILL_TOKEN_REPORT.md) |
| Memory sync 운영과 위협 모델 | [docs/MEMORY_SYNC.md](docs/MEMORY_SYNC.md), [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) |
| README 규칙과 이를 검사하는 lint | [docs/contributing/README_POLICY.md](docs/contributing/README_POLICY.md) |
| 릴리스 기록 | [CHANGELOG.md](CHANGELOG.md) |

---

## 버전 관리

claude-config는 **저장소 단일 버전을 사용하지 않습니다**. 출하되는 각 산출물이 독립된 SemVer 라인을 가지며 `VERSION_MAP.yml`에 한 곳으로 모여 있습니다:

| 필드 | 추적 산출물 | Consumer 파일 |
|------|------------|---------------|
| `suite` | 상태 줄에 표시되고 원라인 설치가 고정하는 사용자용 릴리스 식별자 | `README.md`, `README.ko.md`의 릴리스 링크; `docs/guides/INSTALLATION.md`, `docs/guides/INSTALLATION.ko.md`의 `GITHUB_REF` 예시; `bootstrap.sh`, `bootstrap.ps1` 기본 `GITHUB_REF` 핀 |
| `plugin` | 마켓플레이스 플러그인 버전 | `plugin/.claude-plugin/plugin.json` |
| `plugin-lite` | 경량 플러그인 (행동 가드레일) | `plugin-lite/.claude-plugin/plugin.json` |
| `settings-schema` | 훅 발사 `settings.json` 스키마 | `global/settings.json`, `global/settings.windows.json` |
| `hooks` | 출하 훅 번들 (롤아웃마다 bump) | _없음 — `check_versions`로 SemVer만 검증하며 consumer 파일은 없습니다. `/release --target hooks`로 bump합니다 (tag `hooks-v<version>`)._ |

`scripts/check_versions.sh`가 각 Consumer 파일이 `VERSION_MAP.yml`에 선언된 필드와 일치하는지 검증합니다. 한 번에 한 필드만 bump하려면 `/release <field> <new-version>` (또는 `scripts/sync_versions.sh`)을 사용하세요. `suite`가 claude-docker의 태그 라인과 어떻게 연결되는지는 [`docs/CLAUDE_DOCKER_CONTRACT.md`](docs/CLAUDE_DOCKER_CONTRACT.md)를 참조하세요. 이전 릴리스 기록은 [`CHANGELOG.md`](CHANGELOG.md)에 있습니다.

---

## 기여

1. 저장소를 Fork합니다
2. `develop`에서 기능 브랜치를 만듭니다 (`git checkout -b feature/amazing-feature`)
3. 변경을 커밋합니다 (`git commit -m 'Add amazing feature'`)
4. 브랜치를 push합니다 (`git push origin feature/amazing-feature`)
5. `develop`을 대상으로 Pull Request를 엽니다

---

## Related Projects

### AD-SDLC (Agent-Driven Software Development Lifecycle)

AI 에이전트 기반 소프트웨어 개발 자동화 플랫폼입니다. AD-SDLC 에이전트는 본 프로젝트의 스킬과 가이드라인을 참조해 코드 품질을 향상시킬 수 있습니다.

- **저장소**: [kcenon/claude_code_agent](https://github.com/kcenon/claude_code_agent)
- **통합 가이드**: [docs/ad-sdlc-integration.md](docs/ad-sdlc-integration.md)

---

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

This project includes third-party content. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.
