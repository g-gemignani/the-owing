#!/usr/bin/env bash
# UserPromptSubmit hook: keep AGENTS.md and DESIGN.md ("the plan") current.
#
# A hook cannot itself write good prose — only a person or the model can. What it
# CAN do is fire on every turn and put a standing reminder into the model's
# context, and escalate that reminder when the working tree shows code or content
# changed without a matching update to the docs. That turns "remember to update the
# docs" from a habit into something the harness re-asserts every call.
#
# Emits JSON on stdout: hookSpecificOutput.additionalContext is injected into the
# model's context for this turn.
set -uo pipefail
cd "$(dirname "$0")/../.." 2>/dev/null || exit 0

msg="Keep AGENTS.md (the concept + goals) and DESIGN.md (the decision log) current. \
When this turn makes a real decision or changes a system, record it: a new D## \
section in DESIGN.md with what was tried/measured/broke, and update AGENTS.md's \
pillars or content totals if they moved."

# Only meaningful in a git repo; degrade to the plain reminder otherwise.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	# working-tree changes (staged or not) under code/content, ignoring the docs
	changed=$(git status --porcelain -- scripts resources 2>/dev/null | grep -c . || true)
	docs_touched=$(git status --porcelain -- AGENTS.md DESIGN.md 2>/dev/null | grep -c . || true)
	if [[ "${changed:-0}" -gt 0 && "${docs_touched:-0}" -eq 0 ]]; then
		msg="STALE DOCS: the working tree has ${changed} uncommitted change(s) under \
scripts/ or resources/, but AGENTS.md and DESIGN.md are untouched. Before you \
finish, decide whether this needs a DESIGN.md decision entry and an AGENTS.md \
refresh — do not commit code and docs out of step. ${msg}"
	fi
fi

# jq if present (safe escaping); otherwise a hand-built object with basic escaping.
if command -v jq >/dev/null 2>&1; then
	jq -n --arg m "$msg" \
		'{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
else
	esc=${msg//\\/\\\\}; esc=${esc//\"/\\\"}
	printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$esc"
fi
