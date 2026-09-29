# 저장소 구조

첫 화면을 짧게 두려고 [README](../../README.ko.md)에서 옮겼습니다. English: [STRUCTURE.md](STRUCTURE.md).

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
│   ├── hooks/                  # 훅 스크립트(.sh + .ps1) — 전체 정본 목록은 HOOKS.md 참조
│   │   └── lib/               # 공유 라이브러리
│   │       ├── AttributionValidator.psm1
│   │       ├── CommonHelpers.psm1  # PowerShell 공유 모듈
│   │       ├── LanguageValidator.psm1
│   │       ├── path-utils.sh
│   │       ├── rotate.sh/.ps1
│   │       ├── timeout-wrapper.sh
│   │       └── tokenize-shell.sh
│   ├── scripts/                # 유틸리티 스크립트
│   │   ├── statusline-command.sh/.ps1
│   │   └── weekly-usage.sh
│   └── skills/                 # 글로벌 Skills (사용자 호출형)
│       └── _internal/          # claude-config 전용 스킬 (strict 검증)
│           ├── _shared/        # 스킬 공통 헬퍼 (invariants.md)
│           ├── branch-cleanup/ # 병합/오래된 브랜치 정리
│           ├── ci-fix/         # CI 실패 수정 워크플로우
│           ├── doc-index/      # 문서 인덱스 파일 생성
│           ├── doc-review/     # 마크다운 문서 리뷰
│           ├── evidence-pack/  # 릴리스 증거 패키지 조립
│           ├── fleet-orchestrator/ # Fleet 오케스트레이션 패턴
│           ├── harness/        # Agent team & skill 아키텍처 설계
│           ├── implement-all-levels/ # 완전 구현 강제
│           ├── issue-create/   # GitHub 이슈 생성 (5W1H)
│           ├── issue-work/     # GitHub 이슈 워크플로우
│           ├── memory-review/  # 오래된/플래그/중복 메모리 검토
│           ├── pr-work/        # PR CI/CD 실패 수정
│           ├── preflight/      # 푸시 전 CI 사전점검
│           ├── release/        # 자동 릴리스 생성
│           ├── research/       # 리서치/문헌 조사
│           ├── risk-control/   # 위험/해저드 기록 관리 (규제 트랙)
│           ├── sonar-fix/      # SonarCloud 결함 분류 및 수정
│           ├── soup-inventory/ # SOUP(서드파티) 레지스터 관리
│           └── traceability/   # 양방향 추적성 매트릭스
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
│       │   │   └── cpp-specifics.md
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
│       │   │   └── session-resume.md
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
│       ├── reference/          # 온디맨드 레퍼런스 문서 (rules/ 밖, 자동 로드 안 됨)
│       │   ├── coding/         # anti-patterns.md
│       │   └── workflow/       # 5W1H 예시, 레이블, 자동화, Agent Teams
│       ├── agents/             # 특화 에이전트 설정
│       │   ├── code-reviewer.md
│       │   ├── codebase-analyzer.md
│       │   ├── dependency-auditor.md
│       │   ├── documentation-writer.md
│       │   ├── qa-reviewer.md
│       │   ├── refactor-assistant.md
│       │   ├── structure-explorer.md
│       │   └── test-strategist.md
│       └── skills/             # Claude Code Skills
│           ├── coding-guidelines/
│           ├── security-audit/
│           ├── performance-review/
│           ├── api-design/
│           ├── project-workflow/
│           ├── documentation/
│           ├── ci-debugging/
│           ├── code-quality/   # 사용자 호출형
│           ├── doc-update/     # 사용자 호출형
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
│       ├── InstallerFetch.psm1
│       ├── installer-fetch.sh
│       ├── validate-commit-message.sh  # 공유 검증 라이브러리
│       ├── validate-language.sh
│       └── validate-traceability.sh
│
├── .github/
│   └── workflows/              # PR 검증, 예약 드리프트 점검, 릴리스 자동화
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
