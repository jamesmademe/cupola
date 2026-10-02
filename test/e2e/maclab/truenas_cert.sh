#!/usr/bin/env bash

# The disposable certificate of the lab's TrueNAS mock.
#
# Cupola refuses to dial a TrueNAS address that is not https:// (the server
# revokes an API key that arrives in cleartext), so the mock speaks TLS with a
# self-signed certificate and the app trusts it the way a user does: by its
# fingerprint. This script makes that certificate once, keeps it with the lab's
# other disposable state, and says what its fingerprint is.
#
#   truenas_cert.sh [--state-dir DIR] [ensure|fingerprint|credentials]
#
#   ensure       make the certificate when it is missing (the default)
#   fingerprint  ensure, then print the fingerprint on stdout
#   credentials  ensure, then set CUPOLA_MACLAB_TRUENAS_CERT_FINGERPRINT in the
#                lab's credentials.env, leaving every other entry as it is
#
# The fingerprint is printed exactly as the app compares it: the SHA-256 of
# the certificate's DER encoding as 64 lowercase hex digits, without colons.
#
# The state directory is CUPOLA_MACLAB_STATE_DIR, or the lab's default under
# this checkout. A worktree may name another checkout's lab (the running lab is
# one per machine), so only the shape of the path is checked: it must sit under
# a .ai/scratch/zz_maclab directory. Nothing here removes anything.
#
# The certificate and its key never leave that directory and are never
# committed. The mock reads them for every connection, so a certificate made
# again is served without restarting the container.

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
repo_root="$(cd -- "$script_dir/../../.." && pwd)"
state_dir="${CUPOLA_MACLAB_STATE_DIR:-$repo_root/.ai/scratch/zz_maclab/state}"
action=ensure

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state-dir)
      [[ $# -ge 2 ]] || { printf '%s needs a directory\n' "$1" >&2; exit 2; }
      state_dir="$2"
      shift 2
      ;;
    ensure|fingerprint|credentials)
      action="$1"
      shift
      ;;
    --help|-h)
      sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [[ "$state_dir" != /* ]]; then
  state_dir="$repo_root/$state_dir"
fi
case "$state_dir" in
  *"/../"*|*"/.."|*"/./"*)
    printf 'Refusing a state directory with dot segments: %s\n' "$state_dir" >&2
    exit 2
    ;;
  */.ai/scratch/zz_maclab/*) ;;
  *)
    printf 'Refusing a state directory outside a .ai/scratch/zz_maclab: %s\n' "$state_dir" >&2
    exit 2
    ;;
esac

command -v openssl >/dev/null || { printf 'openssl is required\n' >&2; exit 1; }

cert_dir="$state_dir/truenas"
cert="$cert_dir/truenas.crt"
key="$cert_dir/truenas.key"

# Is there a certificate that is readable, not about to expire, and made for
# the key beside it?
certificate_is_usable() {
  [[ -s "$cert" && -s "$key" ]] || return 1
  openssl x509 -in "$cert" -noout -checkend 86400 >/dev/null 2>&1 || return 1
  local from_cert from_key
  from_cert="$(openssl x509 -in "$cert" -noout -pubkey 2>/dev/null)" || return 1
  from_key="$(openssl pkey -in "$key" -pubout 2>/dev/null)" || return 1
  [[ -n "$from_cert" && "$from_cert" == "$from_key" ]]
}

make_certificate() {
  mkdir -p "$cert_dir"
  local config new_cert new_key
  config="$(mktemp "${TMPDIR:-/tmp}/cupola-truenas-cert.XXXXXX")"
  new_cert="$(mktemp "$cert_dir/.crt.XXXXXX")"
  new_key="$(mktemp "$cert_dir/.key.XXXXXX")"
  # The ten years keep the certificate from expiring under a lab that stays up;
  # a lab that is reset makes a new one anyway.
  cat >"$config" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no

[subject]
CN = cupola-truenas-mock
O = Cupola disposable lab

[extensions]
subjectAltName = DNS:localhost,IP:127.0.0.1
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
CONFIG
  if ! openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -config "$config" -keyout "$new_key" -out "$new_cert" >/dev/null 2>&1; then
    rm -f "$config" "$new_cert" "$new_key"
    printf 'openssl could not make the TrueNAS mock certificate\n' >&2
    return 1
  fi
  rm -f "$config"
  chmod 644 "$new_cert"
  mv "$new_key" "$key"
  mv "$new_cert" "$cert"
}

fingerprint() {
  openssl x509 -in "$cert" -outform DER 2>/dev/null |
    openssl dgst -sha256 -binary |
    od -An -v -tx1 |
    tr -d ' \n'
  printf '\n'
}

if ! certificate_is_usable; then
  make_certificate
  printf 'Made the TrueNAS mock certificate in %s\n' "$cert_dir" >&2
fi

case "$action" in
  ensure) ;;
  fingerprint)
    fingerprint
    ;;
  credentials)
    credentials="$state_dir/credentials.env"
    value="$(fingerprint)"
    scratch="$(mktemp "$credentials.XXXXXX")"
    {
      if [[ -f "$credentials" ]]; then
        grep -v '^CUPOLA_MACLAB_TRUENAS_CERT_FINGERPRINT=' "$credentials" || true
      fi
      printf 'CUPOLA_MACLAB_TRUENAS_CERT_FINGERPRINT=%s\n' "$value"
    } >"$scratch"
    chmod 600 "$scratch"
    mv "$scratch" "$credentials"
    ;;
esac
