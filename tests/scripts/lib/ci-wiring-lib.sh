#!/bin/bash
# Shared CI-wiring detection helpers.
#
# Single source of truth for "what counts as a test being wired into CI":
# an executable workflow `run:` command that invokes the test path. Path
# entries in trigger `paths:` filters, comments, and echo statements must
# NOT count as wiring.
#
# Consumed by:
#   - tests/scripts/test-ci-wiring.sh            (#823, tests/scripts/test-*)
#   - tests/scripts/test-nonstandard-test-wiring.sh (#833, everything else)
#
# Keeping both gates on this one library is what lets #833 extend the wiring
# contract repo-wide "without duplicating the #823 gate": the two gates share
# the detection primitive and differ only in the set of paths they police.

# Extract only commands from YAML `run:` keys. A path that appears in a
# trigger filter, a comment, or a step description is not an executable
# command and must not be emitted here.
extract_run_commands() {
    awk '
        function indentation(value) {
            match(value, /^[[:space:]]*/)
            return RLENGTH
        }
        {
            line = $0
            sub(/\r$/, "", line)

            if (in_block) {
                if (line ~ /^[[:space:]]*$/) {
                    next
                }
                if (indentation(line) > block_indent) {
                    sub(/^[[:space:]]+/, "", line)
                    print line
                    next
                }
                in_block = 0
            }

            trimmed = line
            sub(/^[[:space:]]+/, "", trimmed)
            if (trimmed !~ /^run:[[:space:]]*/) {
                next
            }

            block_indent = indentation(line)
            sub(/^run:[[:space:]]*/, "", trimmed)
            if (trimmed ~ /^[|>][-+]?$/) {
                in_block = 1
                next
            }
            print trimmed
        }
    ' "$1"
}

# Return success only when the path is an argument to an executable test
# command (bash/pwsh/powershell/ ./ ). Merely echoing or mentioning the path
# does not satisfy the gate.
commands_reference_path() {
    local test_path="$1"
    local commands_file="$2"
    awk -v path="$test_path" '
        {
            line = $0
            position = index(line, path)
            if (position == 0) {
                next
            }

            prefix = substr(line, 1, position - 1)
            suffix = substr(line, position + length(path))
            if (suffix !~ /^([[:space:]\\;&|]|$)/) {
                next
            }

            if (prefix ~ /(^|[;&|][[:space:]]*)(bash|pwsh|powershell)([[:space:]][^#]*)?$/ ||
                prefix ~ /(^|[;&|][[:space:]]*)\.?\/?$/) {
                found = 1
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$commands_file"
}
