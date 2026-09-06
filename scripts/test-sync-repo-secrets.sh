#!/usr/bin/env bash
# Local validation harness for scripts/sync-repo-secrets.sh (no network, stubbed gh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Git Bash on Windows: $TEMP is a Windows path (backslashes) — convert it,
# otherwise the stub gh never resolves via PATH.
if command -v cygpath >/dev/null 2>&1 && [ -n "${TEMP:-}" ]; then
	WORK="$(cygpath -u "${TEMP}")/sync-test-$$"
else
	WORK="${TEMP:-/tmp}/sync-test-$$"
fi
STUB="${WORK}/bin"
mkdir -p "${STUB}"
export WORK

cat > "${STUB}/gh" <<'EOF'
#!/usr/bin/env bash
# stub gh: args are [secret, set, NAME, -R, ORG/repo] ; value from stdin
name="$3"
repo="$5"
touch "${WORK}/stub-used"
out="${WORK}/received-${repo//\//_}-${name}.txt"
cat > "${out}"
echo "MOCK ${name} -> ${repo}"
EOF
chmod +x "${STUB}/gh"

fail=0
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

# ---------- Phase A: values from a secrets.env file ----------
SECF="${WORK}/secrets.env"
printf 'OPENROUTER_API_KEY=sk-or-v1-test123\r\n' > "${SECF}"
printf 'export DEVTOOLS_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\\nMIIEline1\\nMIIEline2\\n-----END RSA PRIVATE KEY-----"\n' >> "${SECF}"

SECRETS_FILE="${SECF}" PATH="${STUB}:${PATH}" bash "${SCRIPT_DIR}/sync-repo-secrets.sh" pia >/dev/null

or_file="${WORK}/received-ostara-labs_pia-OPENROUTER_API_KEY.txt"
pem_file="${WORK}/received-ostara-labs_pia-DEVTOOLS_APP_PRIVATE_KEY.txt"

if [ ! -f "${WORK}/stub-used" ]; then
	echo "ENV FAIL: stub gh was never invoked — results are meaningless"; exit 2
fi

if [ -f "${or_file}" ] && [ "$(cat "${or_file}")" = "sk-or-v1-test123" ]; then
	echo "A1 PASS: OPENROUTER_API_KEY exact (CRLF stripped)"
else
	echo "A1 FAIL: OPENROUTER_API_KEY got: [$(cat "${or_file}" 2>/dev/null)]"; fail=1
fi
if [ -f "${pem_file}" ] \
	&& [ "$(sed -n '1p' "${pem_file}")" = "-----BEGIN RSA PRIVATE KEY-----" ] \
	&& [ "$(sed -n '2p' "${pem_file}")" = "MIIEline1" ] \
	&& [ "$(sed -n '4p' "${pem_file}")" = "-----END RSA PRIVATE KEY-----" ]; then
	echo "A2 PASS: PEM multi-line from \\n escapes (4 lines, correct header/footer)"
else
	echo "A2 FAIL: PEM content: [$(cat "${pem_file}" 2>/dev/null)]"; fail=1
fi

# ---------- Phase B: interactive prompt (piped stdin, no secrets file) ----------
B_IN="${WORK}/prompt-input.txt"
printf 'sk-or-v1-prompt\n-----BEGIN RSA PRIVATE KEY-----\nline1\n-----END RSA PRIVATE KEY-----\n\n' > "${B_IN}"
SECRETS_FILE="${WORK}/does-not-exist.env" PATH="${STUB}:${PATH}" \
	bash "${SCRIPT_DIR}/sync-repo-secrets.sh" pia < "${B_IN}" >/dev/null 2>&1

or_file_b="${WORK}/received-ostara-labs_pia-OPENROUTER_API_KEY.txt"
pem_file_b="${WORK}/received-ostara-labs_pia-DEVTOOLS_APP_PRIVATE_KEY.txt"

if [ -f "${or_file_b}" ] && [ "$(cat "${or_file_b}")" = "sk-or-v1-prompt" ]; then
	echo "B1 PASS: prompt mode OPENROUTER_API_KEY"
else
	echo "B1 FAIL: prompt OPENROUTER got: [$(cat "${or_file_b}" 2>/dev/null)]"; fail=1
fi
if [ -f "${pem_file_b}" ] \
	&& [ "$(sed -n '1p' "${pem_file_b}")" = "-----BEGIN RSA PRIVATE KEY-----" ] \
	&& [ "$(sed -n '2p' "${pem_file_b}")" = "line1" ] \
	&& [ "$(sed -n '3p' "${pem_file_b}")" = "-----END RSA PRIVATE KEY-----" ]; then
	echo "B2 PASS: prompt mode multi-line PEM (3 lines, empty-line terminator)"
else
	echo "B2 FAIL: prompt PEM content: [$(cat "${pem_file_b}" 2>/dev/null)]"; fail=1
fi

# ---------- Phase C: nothing provided -> exit 2, nothing synced ----------
rm -f "${WORK}"/received-*
if SECRETS_FILE="${WORK}/still-missing.env" PATH="${STUB}:${PATH}" \
	bash "${SCRIPT_DIR}/sync-repo-secrets.sh" pia </dev/null >/dev/null 2>&1; then
	echo "C FAIL: expected exit 2 with no values"; fail=1
else
	if ls "${WORK}"/received-* >/dev/null 2>&1; then
		echo "C FAIL: no values but a sync happened"; fail=1
	else
		echo "C PASS: no values -> exit 2, nothing synced"
	fi
fi

if [ "${fail}" -eq 0 ]; then
	echo "ALL PASS"
else
	exit 1
fi
