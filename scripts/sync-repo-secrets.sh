#!/usr/bin/env bash
# Sync secrets from a local source down to consumer repos.
#
# Why per-repo and not an org secret: on the GitHub Free plan, org secrets
# cannot be used by private repositories (only public ones). Each consumer
# carries its own copy — this script makes that a single command.
#
# Why not read the org secret's value: GitHub secret values are write-only
# (unreadable via API or UI, even as org admin). The values therefore come
# from, in order of precedence:
#   1. the environment (OPENROUTER_API_KEY / DEVTOOLS_APP_PRIVATE_KEY)
#   2. the local secrets store: ~/agent-conventions/secrets.env
#      (single-line KEY=value or export KEY=value; literal \n become
#       newlines for multi-line PEM values; override path: SECRETS_FILE=...)
#   3. an interactive prompt (hidden input; for the PEM, paste the key then
#      terminate with an empty line)
# Values missing from both 1 and 2 are asked on 3; answering empty skips
# that secret.
#
# Synced secrets:
#   OPENROUTER_API_KEY          — AI review (devtools ai-review.yml callers)
#   DEVTOOLS_APP_PRIVATE_KEY    — devtools GitHub App
#
# Usage:
#   scripts/sync-repo-secrets.sh                # all default repos
#   scripts/sync-repo-secrets.sh pia bot        # subset of repos
# Requires gh authenticated with admin on the target repos.
#
# Rotate: renew the credential at its provider, update the local source,
# re-run.

set -euo pipefail

ORG="ostara-labs"
SECRETS_FILE="${SECRETS_FILE:-${HOME}/agent-conventions/secrets.env}"
DEFAULT_REPOS=(pia bot world-monitor-tui messenger-assistant home)
SYNCED_SECRETS=(OPENROUTER_API_KEY DEVTOOLS_APP_PRIVATE_KEY)

if [ ! -f "${SECRETS_FILE}" ]; then
	if [ -t 0 ]; then
		echo "note: no secrets file at ${SECRETS_FILE} — falling back to prompts" >&2
	fi
	SECRETS_FILE="/dev/null"
fi

REPOS=("$@")
if [ ${#REPOS[@]} -eq 0 ]; then
	REPOS=("${DEFAULT_REPOS[@]}")
fi

# from_store NAME — value from the secrets file, or empty.
from_store() {
	local name="$1" raw
	raw="$(grep -E "^(export )?${name}=" "${SECRETS_FILE}" | tail -n 1 | cut -d= -f2- || true)"
	[ -z "${raw}" ] && return 0
	raw="${raw%\"}"
	raw="${raw#\"}"
	raw="${raw%$'\r'}"
	printf '%s' "${raw//\\n/$'\n'}"
}

# prompt_value NAME — interactive entry; empty answer = skip.
prompt_value() {
	local name="$1" line out=""
	if [ "${name}" = "DEVTOOLS_APP_PRIVATE_KEY" ]; then
		echo "Paste the PEM for ${name}, then end with an EMPTY line:" >&2
		while IFS= read -r line && [ -n "${line}" ]; do
			out+="${line}"$'\n'
		done
	else
		read -rs -p "Value for ${name} (hidden, empty = skip): " line || line=""
		echo >&2
		out="${line}"
	fi
	printf '%s' "${out}"
}

synced_any=0
for name in "${SYNCED_SECRETS[@]}"; do
	value="$(printenv "${name}" || true)"
	if [ -z "${value}" ]; then
		value="$(from_store "${name}")"
	fi
if [ -z "${value}" ]; then
	value="$(prompt_value "${name}")"
fi
if [ -z "${value}" ]; then
	continue
fi

	for repo in "${REPOS[@]}"; do
		printf '%s' "${value}" | gh secret set "${name}" -R "${ORG}/${repo}"
	done
	echo "✓ ${name} → ${REPOS[*]}"
	synced_any=1
done

if [ "${synced_any}" -eq 0 ]; then
	echo "no secret synced — provide one via environment, ${SECRETS_FILE}, or prompt" >&2
	exit 2
fi
