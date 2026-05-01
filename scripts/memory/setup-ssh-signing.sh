#!/bin/bash
# setup-ssh-signing.sh -- Configure git to sign commits with an SSH key.
#
# Per issue #518: every machine that pushes to claude-memory must sign commits
# with an SSH key, so a committed memory file's authorship is cryptographically
# verifiable. This helper configures git on the current machine and prints the
# next steps the operator must perform manually (key registration on GitHub).
#
# Non-destructive by default:
#   - Detects existing SSH keys; never generates one without --generate-key
#   - Backs up ~/.gitconfig before modifying it
#   - Never uploads keys to GitHub (operator does this with explicit consent)
#
# Exit codes:
#   0   success (configured, or already configured -- idempotent)
#   1   pre-flight failed (git too old, no SSH key, etc.)
#   64  usage error
#
# Bash 3.2 compatible (macOS default). macOS and Linux both supported.
#
# Usage:
#   setup-ssh-signing.sh                    auto-detect key, configure git
#   setup-ssh-signing.sh --key <pubkey>     use a specific public key file
#   setup-ssh-signing.sh --generate-key     create id_ed25519 if none exists
#   setup-ssh-signing.sh --dry-run          show what would change, do not write
#   setup-ssh-signing.sh --help|-h          show this help
#
# Environment overrides (all optional):
#   OWNER_EMAIL   email to register in allowed_signers (default: from git config user.email)

set -u

DEFAULT_OWNER_EMAIL=""

# Required minimum git version for SSH signing.
GIT_MIN_MAJOR=2
GIT_MIN_MINOR=34

# Standard SSH public key locations, in preference order (ed25519 > ecdsa > rsa).
SSH_KEY_CANDIDATES=(
  "$HOME/.ssh/id_ed25519.pub"
  "$HOME/.ssh/id_ecdsa.pub"
  "$HOME/.ssh/id_rsa.pub"
)

usage() {
  cat <<EOF
setup-ssh-signing.sh -- configure git for SSH commit signing

Usage:
  $(basename "$0")                    auto-detect SSH key and configure
  $(basename "$0") --key <pubkey>     use a specific .pub file
  $(basename "$0") --generate-key     create ~/.ssh/id_ed25519 if missing
  $(basename "$0") --dry-run          print intended changes, do not apply
  $(basename "$0") --help|-h          show this help

What it does:
  1. Verifies git >= ${GIT_MIN_MAJOR}.${GIT_MIN_MINOR}
  2. Locates an SSH public key (or generates one with --generate-key)
  3. Backs up ~/.gitconfig to ~/.gitconfig.bak.<timestamp>
  4. Sets gpg.format=ssh, user.signingkey, commit.gpgsign=true, tag.gpgsign=true
  5. Writes ~/.config/git/allowed_signers and configures gpg.ssh.allowedSignersFile
  6. Prints next-step instructions for registering the key on GitHub

What it does NOT do (you must do these manually):
  - Generate keys (unless --generate-key is passed)
  - Upload keys to GitHub
  - Modify branch protection rules

Exit codes: 0=success, 1=pre-flight failed, 64=usage error.

Environment overrides:
  OWNER_EMAIL   override email registered in allowed_signers
                (default: git config --global user.email)
EOF
}

# log_info / log_ok / log_warn / log_error -- consistent prefixed output.
log_info()  { printf '[..] %s\n' "$*"; }
log_ok()    { printf '[OK] %s\n' "$*"; }
log_warn()  { printf '[WARN] %s\n' "$*" >&2; }
log_error() { printf '[ERROR] %s\n' "$*" >&2; }

# check_git_version -- verify git is installed and >= 2.34.
check_git_version() {
  if ! command -v git >/dev/null 2>&1; then
    log_error "git not found in PATH"
    return 1
  fi
  local v major minor
  v="$(git --version 2>/dev/null | awk '{print $3}')"
  major="${v%%.*}"
  minor="${v#*.}"
  minor="${minor%%.*}"
  if [[ -z "$major" ]] || [[ -z "$minor" ]]; then
    log_error "could not parse git version: $v"
    return 1
  fi
  if (( major < GIT_MIN_MAJOR )) || { (( major == GIT_MIN_MAJOR )) && (( minor < GIT_MIN_MINOR )); }; then
    log_error "git ${v} is too old; SSH signing requires >= ${GIT_MIN_MAJOR}.${GIT_MIN_MINOR}"
    return 1
  fi
  log_ok "git version: $v"
  return 0
}

# find_ssh_key -- echo the first existing public key path. Returns 0 if found.
find_ssh_key() {
  local candidate
  for candidate in "${SSH_KEY_CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# generate_ed25519_key -- create ~/.ssh/id_ed25519 with default options.
# Caller must have already confirmed it does not exist.
generate_ed25519_key() {
  local key_path="$HOME/.ssh/id_ed25519"
  log_info "generating ${key_path} (ed25519)..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if ! ssh-keygen -t ed25519 -f "$key_path" -N ""; then
    log_error "ssh-keygen failed"
    return 1
  fi
  log_ok "generated $key_path"
  printf '%s.pub\n' "$key_path"
  return 0
}

# resolve_owner_email -- echo the email to use in allowed_signers.
# Order: $OWNER_EMAIL env > git config --global user.email > empty (error).
resolve_owner_email() {
  if [[ -n "${OWNER_EMAIL:-$DEFAULT_OWNER_EMAIL}" ]]; then
    printf '%s\n' "${OWNER_EMAIL:-$DEFAULT_OWNER_EMAIL}"
    return 0
  fi
  local e
  e="$(git config --global user.email 2>/dev/null || true)"
  if [[ -n "$e" ]]; then
    printf '%s\n' "$e"
    return 0
  fi
  return 1
}

# backup_gitconfig -- copy ~/.gitconfig to a timestamped backup. Idempotent
# (returns 0 even if no existing config). Echoes the backup path on success.
backup_gitconfig() {
  local src="$HOME/.gitconfig"
  if [[ ! -f "$src" ]]; then
    return 0
  fi
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local dst="${src}.bak.${stamp}"
  if cp "$src" "$dst"; then
    printf '%s\n' "$dst"
    return 0
  fi
  return 1
}

# write_allowed_signers -- create or update ~/.config/git/allowed_signers with
# one line per (email, key) pair. Appends if email/key combo not present.
write_allowed_signers() {
  local email="$1"
  local pubkey_path="$2"
  local signers_dir="$HOME/.config/git"
  local signers_file="$signers_dir/allowed_signers"

  mkdir -p "$signers_dir"

  # Read the public-key body (everything except the optional trailing comment).
  local key_content
  key_content="$(awk '{print $1, $2}' "$pubkey_path" 2>/dev/null)"
  if [[ -z "$key_content" ]]; then
    log_error "could not read public key: $pubkey_path"
    return 1
  fi

  local entry="${email} ${key_content}"

  # If the exact entry already exists, do nothing.
  if [[ -f "$signers_file" ]] && grep -Fxq "$entry" "$signers_file"; then
    log_ok "allowed_signers already contains this entry"
    return 0
  fi

  # Append the new entry. Preserve any existing entries (multi-machine).
  printf '%s\n' "$entry" >> "$signers_file"
  chmod 644 "$signers_file"
  log_ok "wrote $signers_file"
  return 0
}

# apply_git_config -- set the global git config keys for SSH signing.
apply_git_config() {
  local pubkey_path="$1"
  local signers_file="$HOME/.config/git/allowed_signers"

  git config --global gpg.format ssh
  git config --global user.signingkey "$pubkey_path"
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true
  git config --global gpg.ssh.allowedSignersFile "$signers_file"
}

# print_next_steps -- post-configuration instructions. Operator-driven.
print_next_steps() {
  local pubkey_path="$1"
  cat <<EOF

Next steps (operator action required):

  1. Open https://github.com/settings/ssh/new
  2. Paste the public key shown below; set Key type = Signing Key
       cat "$pubkey_path"
  3. From any local clone of claude-memory, verify a signed commit:
       git commit -S --allow-empty -m "test signed commit"
       git log --show-signature -1
     Expected:
       Good "ssh" signature for <email> with ED25519 key SHA256:...
  4. (Repository owner only) Enable required-signed-commit branch protection:
       gh api repos/kcenon/claude-memory/branches/main/protection \\
         --method PUT \\
         -f required_signatures.enabled=true \\
         -f required_pull_request_reviews=null \\
         -f restrictions=null \\
         -f enforce_admins=true

After step 4, unsigned commits to claude-memory main will be rejected.
EOF
}

# print_dry_run -- show what would change without writing anything.
print_dry_run() {
  local pubkey_path="$1"
  local email="$2"
  cat <<EOF

[DRY RUN] No changes written. Intended changes:

  Backup:
    ~/.gitconfig -> ~/.gitconfig.bak.<timestamp> (if ~/.gitconfig exists)

  git config --global:
    gpg.format = ssh
    user.signingkey = ${pubkey_path}
    commit.gpgsign = true
    tag.gpgsign = true
    gpg.ssh.allowedSignersFile = \$HOME/.config/git/allowed_signers

  ~/.config/git/allowed_signers (append):
    ${email} <key body from ${pubkey_path}>

Re-run without --dry-run to apply.
EOF
}

main() {
  local pubkey_path=""
  local generate_key=0
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --key)
        if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
          log_error "--key requires a path argument"
          usage >&2
          exit 64
        fi
        pubkey_path="$2"
        shift 2
        ;;
      --generate-key)
        generate_key=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      *)
        log_error "unknown argument: $1"
        usage >&2
        exit 64
        ;;
    esac
  done

  # 1. Pre-flight: git version.
  if ! check_git_version; then
    return 1
  fi

  # 2. Locate or generate SSH key.
  if [[ -n "$pubkey_path" ]]; then
    if [[ ! -f "$pubkey_path" ]]; then
      log_error "public key not found: $pubkey_path"
      return 1
    fi
    log_ok "using specified key: $pubkey_path"
  else
    if pubkey_path="$(find_ssh_key)"; then
      log_ok "found SSH key: $pubkey_path"
    else
      if (( generate_key == 1 )); then
        if ! pubkey_path="$(generate_ed25519_key)"; then
          return 1
        fi
      else
        log_error "no SSH key found in ~/.ssh/"
        log_error "generate one with:"
        log_error "    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519"
        log_error "or re-run this script with --generate-key"
        return 1
      fi
    fi
  fi

  # 3. Resolve owner email.
  local email
  if ! email="$(resolve_owner_email)"; then
    log_error "could not determine owner email"
    log_error "set it with: git config --global user.email <you@example.com>"
    log_error "or pass via: OWNER_EMAIL=you@example.com $(basename "$0")"
    return 1
  fi
  log_ok "owner email: $email"

  # 4. Dry run mode -- print intended changes and exit.
  if (( dry_run == 1 )); then
    print_dry_run "$pubkey_path" "$email"
    return 0
  fi

  # 5. Backup existing ~/.gitconfig.
  local backup
  if backup="$(backup_gitconfig)"; then
    if [[ -n "$backup" ]]; then
      log_ok "backed up ~/.gitconfig to $backup"
    fi
  else
    log_warn "could not back up ~/.gitconfig; continuing"
  fi

  # 6. Write allowed_signers.
  if ! write_allowed_signers "$email" "$pubkey_path"; then
    return 1
  fi

  # 7. Apply git config.
  apply_git_config "$pubkey_path"
  log_ok "configured git for SSH signing"

  # 8. Print next steps.
  print_next_steps "$pubkey_path"
  return 0
}

main "$@"
exit $?
