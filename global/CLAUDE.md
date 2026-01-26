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

| Setting | Value | Override |
|---------|-------|----------|
| Response language | Korean | Project `communication.md` |
| Git identity | System config | Not overridable |
| Claude attribution | Disabled | Not overridable |
| Token display | Always | Not overridable |

**NEVER** include Claude/AI attribution in commits, issues, or PRs (see `commit-settings.md`).

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

*Version: 1.4.0 | Last updated: 2026-01-22*
