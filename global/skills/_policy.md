# Global Command Policies

- Git/GitHub output (commits, PRs, issues, release notes): English
- No emojis in commits, PR titles, issue titles
- Commit format: Conventional Commits (`type(scope): description`)
- Use closing keywords (`Closes #N`) in PR descriptions when applicable
- All builds must pass before PR; all CI checks before merge
- See `rules/workflow/build-verification.md` for verification patterns
- Batch processing: 2-second pause between items, 0.3-second pause between API calls during discovery
- Batch mode: max 200 repos for cross-repo discovery, max 100 items per repo
- Batch failure: continue to next item on failure, present summary at end
