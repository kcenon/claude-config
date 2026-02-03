# Claude Code Global Configuration

Global settings for all Claude Code sessions. Project-specific `CLAUDE.md` files override these.

## Core Settings (Import Syntax)

@./token-management.md
@./conversation-language.md
@./git-identity.md
@./commit-settings.md

## Priority Rules

**IMPORTANT**: Understand these priority rules to resolve conflicts correctly.

1. **Project overrides global** - Project `CLAUDE.md` takes precedence
2. **Intelligent loading** - Auto-selects modules via `conditional-loading.md`
3. **Token optimization** - Reduces usage by ~60-70%

## Quick Reference

| Setting | Source | Value | Override |
|---------|--------|-------|----------|
| Response language | `settings.json` | Korean | Project `settings.json` |
| Git identity | System git config | User's config | Not overridable |
| Claude attribution | `settings.json` | Disabled | Not overridable |
| Output style | `settings.json` | Explanatory | Project `settings.json` |

## Official Settings (settings.json)

Key behaviors are now configured via official `settings.json` options:

| Setting | Value | Purpose |
|---------|-------|---------|
| `language` | `"korean"` | Default response language |
| `attribution.commit` | `""` | No Claude attribution in commits |
| `attribution.pr` | `""` | No Claude attribution in PRs |
| `outputStyle` | `"Explanatory"` | Detailed explanations |
| `showTurnDuration` | `true` | Display turn timing |

See `settings.json` for the complete configuration.

## Token Optimization

**중요**: `.claudeignore` 파일을 통해 불필요한 파일이 제외되어 초기 토큰 사용량이 약 **60-70% 감소**합니다.

제외된 항목:
- 플러그인 마켓플레이스 (대용량 파일)
- 세션 메모리 (과거 대화 기록)
- 명령어 및 스킬 정의 (필요시만 로드)
- 플랜 파일 및 캐시

필요 시 다음과 같이 레퍼런스 문서를 로드할 수 있습니다:
```markdown
@load: reference/label-definitions
```

자세한 내용은 [docs/TOKEN_OPTIMIZATION.md](../docs/TOKEN_OPTIMIZATION.md) 참조.

## Configuration Updates

1. Edit module files (e.g., `token-management.md`)
2. Restart session to apply changes

---

*Version: 1.5.0 | Last updated: 2026-02-03*
