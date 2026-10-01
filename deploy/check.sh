#!/bin/sh
# Checks a deployment from outside: HTTP redirects to HTTPS, the API refuses
# requests without the token and answers with it. Prompts for the token so it
# stays out of shell history and the process list.
#
# Usage, from any machine with curl: sh deploy/check.sh <domain>
set -u
if [ $# -ne 1 ]; then
  echo "usage: sh deploy/check.sh <domain>" >&2
  exit 64
fi
domain=$1
failed=0

check() { # <label> <expected status> <actual status>
  if [ "$3" = "$2" ]; then
    echo "ok    $1 ($3)"
  else
    echo "FAIL  $1: expected $2, got $3"
    failed=1
  fi
}

check "http:// redirects to https://" 308 \
  "$(curl -s -o /dev/null -w '%{http_code}' "http://$domain/api/status")"
check "no token is refused" 401 \
  "$(curl -s -o /dev/null -w '%{http_code}' "https://$domain/api/status")"

printf 'API token: '
stty -echo 2>/dev/null
read -r token
stty echo 2>/dev/null
echo
check "token is accepted" 200 \
  "$(printf 'Authorization: Bearer %s\n' "$token" |
    curl -s -o /dev/null -w '%{http_code}' -H @- "https://$domain/api/status")"

exit $failed
