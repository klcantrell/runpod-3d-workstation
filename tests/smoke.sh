#!/bin/bash
# Smoke test for the built image, run by CI before it's pushed:
#   tests/smoke.sh <image>
# 1. ws-entrypoint refuses to start with missing or unresolved secrets
# 2. tests/in-image.sh: tools, add-on, and sync scripts
# 3. a full boot: services start, the desktop answers over plain HTTP, the
#    r2-sync service restores, and a final save happens on docker stop
# No GPU, so this can't check streaming, Vulkan, Isaac Sim or Unreal.
set -euo pipefail
image="${1:?usage: tests/smoke.sh <image>}"
here="$(cd "$(dirname "$0")" && pwd)"
net="ws-smoke-$$"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
cleanup() {
  docker rm -f "$net-pod" "$net-s3" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT

good_env=(-e PASSWD=smoke-test-pass -e R2_ACCOUNT_ID=test -e R2_ACCESS_KEY_ID=test
          -e R2_SECRET_ACCESS_KEY=test -e R2_BUCKET=bucket -e R2_ENDPOINT="http://$net-s3:9000")

# --- 1. Secret guard
for bad in "PASSWD=" "PASSWD=mypasswd" "PASSWD={{ RUNPOD_SECRET_desktop_password }}" "R2_BUCKET={{ RUNPOD_SECRET_r2_bucket }}"; do
  if out="$(docker run --rm "${good_env[@]}" -e "$bad" "$image" 2>&1)"; then
    fail "container started with $bad"
  fi
  grep -q "FATAL" <<<"$out" || fail "no FATAL message for $bad: $out"
done
pass "entrypoint refuses missing and unresolved secrets"

# --- 2. In-image checks
docker run --rm --entrypoint bash -v "$here:/tests:ro" "$image" /tests/in-image.sh

# --- 3. Full boot
docker network create "$net" >/dev/null
docker run -d --name "$net-s3" --network "$net" --entrypoint bash "$image" \
  -c 'mkdir -p /tmp/s3/bucket/work && echo restored > /tmp/s3/bucket/work/hello.txt &&
      exec rclone serve s3 /tmp/s3 --addr 0.0.0.0:9000' >/dev/null
docker run -d --name "$net-pod" --network "$net" "${good_env[@]}" "$image" >/dev/null

on_pod() { docker exec "$net-pod" bash -c "$1"; }
for _ in $(seq 1 60); do
  on_pod 'test -f /tmp/runtime-ubuntu/ws-restored' 2>/dev/null && break
  sleep 3
done
on_pod 'test -f /tmp/runtime-ubuntu/ws-restored' || { docker logs "$net-pod" | tail -50; fail "r2-sync never restored"; }
on_pod 'grep -q restored ~/work/hello.txt' || fail "restore didn't bring back work/hello.txt"
pass "r2-sync service restores at boot"

for _ in $(seq 1 40); do
  code="$(on_pod 'curl -s -o /dev/null -w "%{http_code}" -u ubuntu:smoke-test-pass http://localhost:8080/' || true)"
  [ "$code" = 200 ] && break
  sleep 3
done
[ "$code" = 200 ] || { docker logs "$net-pod" | tail -50; fail "desktop didn't answer over HTTP on 8080 (got $code)"; }
code="$(on_pod 'curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/')"
[ "$code" = 401 ] || fail "desktop answered without a password (got $code)"
pass "desktop serves plain HTTP on 8080 behind basic auth"

on_pod 'echo "written before stop" > ~/work/final.txt'
docker stop -t 60 "$net-pod" >/dev/null
docker exec "$net-s3" grep -q "written before stop" /tmp/s3/bucket/work/final.txt ||
  { docker logs "$net-pod" | tail -50; fail "no final save on docker stop"; }
pass "final save on SIGTERM"

echo "smoke test passed"
