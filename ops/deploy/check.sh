#!/usr/bin/env bash
# Checks of deploy settings, run by .github/workflows/deploy.yml on the runner before anything is
# shipped, and by Deploy CI. Exit status 0 when the check passes; otherwise a message on stderr.
#
#   check.sh proxies "<TRUSTED_PROXIES>"
#       comma-separated IPv4/IPv6 addresses or CIDRs, none broader than /24 (IPv4) or /64 (IPv6):
#       only the tunnel connector may say who the visitor is.
#   check.sh cert <environment> <cert.pem> <key.pem> <host>
#       the Origin certificate: signed by Cloudflare's Origin CA (ops/tls/*.pem), covering <host>,
#       matching its key, not expired (a warning within 30 days). ORIGIN_CA_EXTRA names one more CA
#       file to trust, for Deploy CI's throwaway CA; it is refused for production.
set -euo pipefail

die() { echo "$*" >&2; exit 1; }

check_proxies() {
  local list="$1" entry address bits
  [ -n "${list//[[:space:],]/}" ] || die "TRUSTED_PROXIES is empty: set it to the tunnel connector's address"
  IFS=',' read -ra entries <<< "$list"
  for entry in "${entries[@]}"; do
    entry="${entry//[[:space:]]/}"
    [ -n "$entry" ] || continue
    address="${entry%/*}" bits=""
    [[ "$entry" == */* ]] && bits="${entry#*/}"
    if [[ "$address" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
      for octet in "${BASH_REMATCH[@]:1}"; do [ "$octet" -le 255 ] || die "TRUSTED_PROXIES: $entry is not an IPv4 address"; done
      if [ -n "$bits" ]; then
        if ! [[ "$bits" =~ ^[0-9]{1,2}$ ]] || [ "$bits" -gt 32 ]; then die "TRUSTED_PROXIES: $entry has a bad prefix length"; fi
        [ "$bits" -ge 24 ] || die "TRUSTED_PROXIES: $entry is broader than /24; list the tunnel connector's own address"
      fi
    elif [[ "$address" =~ ^[0-9A-Fa-f:]+$ && "$address" == *:*:* ]]; then
      if [ -n "$bits" ]; then
        if ! [[ "$bits" =~ ^[0-9]{1,3}$ ]] || [ "$bits" -gt 128 ]; then die "TRUSTED_PROXIES: $entry has a bad prefix length"; fi
        [ "$bits" -ge 64 ] || die "TRUSTED_PROXIES: $entry is broader than /64; list the tunnel connector's own address"
      fi
    else
      die "TRUSTED_PROXIES: '$entry' is not an IP address or CIDR (host names are not allowed)"
    fi
  done
}

check_cert() {
  local environment="$1" cert="$2" key="$3" host="$4" roots
  roots="$(mktemp)"
  trap 'rm -f "$roots"' RETURN
  cat "$(dirname "${BASH_SOURCE[0]}")/../tls/"*.pem > "$roots"
  if [ -n "${ORIGIN_CA_EXTRA:-}" ]; then
    [ "$environment" != production ] || die "ORIGIN_CA_EXTRA is for Deploy CI only: production must use a Cloudflare Origin CA certificate"
    cat "$ORIGIN_CA_EXTRA" >> "$roots"
  fi
  openssl verify -purpose sslserver -CAfile "$roots" -untrusted "$cert" "$cert" > /dev/null 2>&1 \
    || die "TLS_CERT is not signed by Cloudflare's Origin CA (ops/tls): create it under SSL/TLS > Origin Server"
  openssl x509 -in "$cert" -noout -checkhost "$host" | grep -q 'does match' || die "TLS_CERT does not cover ORIGIN_HOST ($host)"
  [ "$(openssl x509 -in "$cert" -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum)" = "$(openssl pkey -in "$key" -pubout -outform DER | sha256sum)" ] \
    || die "TLS_KEY does not match TLS_CERT"
  openssl x509 -in "$cert" -noout -checkend 0 > /dev/null || die "TLS_CERT has expired"
  openssl x509 -in "$cert" -noout -checkend $((30 * 86400)) > /dev/null || echo "::warning::TLS_CERT expires within 30 days: issue a new Origin certificate"
  openssl x509 -in "$cert" -noout -subject -ext subjectAltName -enddate
}

case "${1:-}" in
  proxies) [ "$#" -eq 2 ] || die "usage: check.sh proxies <list>"; check_proxies "$2" ;;
  cert) [ "$#" -eq 5 ] || die "usage: check.sh cert <environment> <cert> <key> <host>"; check_cert "$2" "$3" "$4" "$5" ;;
  *) die "usage: check.sh proxies <list> | cert <environment> <cert> <key> <host>" ;;
esac
