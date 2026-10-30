#!/usr/bin/env sh
# Run this on the k3s server, as root: it checks Rancher the way a person
# would. It reads the hostname from the ingress and the password from the
# file the circuit writes, and goes through k3s's ingress on 127.0.0.1, so
# it works before DNS does. -k because Rancher's own CA isn't trusted here.
set -eu
host=$(k3s kubectl -n cattle-system get ingress rancher -o jsonpath='{.spec.rules[0].host}')
pw=$(cat /etc/rancher/manager/bootstrap-password)
api() { curl -sk --resolve "$host:443:127.0.0.1" "$@"; }

[ "$(api "https://$host/ping")" = pong ] || { echo "API did not answer /ping" >&2; exit 1; }
echo "api: pong"

login="https://$host/v3-public/localProviders/local?action=login"
# The password reaches curl on stdin, so it never shows in ps.
token=$(printf '{"username":"admin","password":"%s"}' "$pw" | api -H 'Content-Type: application/json' -d @- "$login" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$token" ] || { echo "Login with the bootstrap password failed" >&2; exit 1; }
echo "login: ok"

code=$(printf '{"username":"admin","password":"not-the-password"}' | api -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -d @- "$login")
[ "$code" = 401 ] || { echo "A wrong password got $code, not 401" >&2; exit 1; }
echo "wrong password: 401"

# The cluster goes back to waiting for a minute or two after a reboot.
state=
for _ in $(seq 60); do
  state=$(printf 'header = "Authorization: Bearer %s"\n' "$token" | api -K - "https://$host/v3/clusters/local" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p' | head -1)
  [ "$state" = active ] && { echo "local cluster: active"; exit 0; }
  sleep 5
done
echo "Local cluster is '$state', not active" >&2
exit 1
