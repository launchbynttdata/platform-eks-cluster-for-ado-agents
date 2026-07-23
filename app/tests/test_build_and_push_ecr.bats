#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/app/build-and-push-ecr.sh"
  TEST_ROOT="${BATS_TMPDIR}/build-and-push-ecr"
  BIN_DIR="${TEST_ROOT}/bin"
  CTX="${TEST_ROOT}/context"
  LOG_FILE="${TEST_ROOT}/commands.log"

  mkdir -p "$BIN_DIR" "$CTX"
  : > "$LOG_FILE"

  cat > "${CTX}/Dockerfile" <<'EOF'
FROM scratch
EOF
  cat > "${CTX}/container-structure-test.yaml" <<'EOF'
schemaVersion: 2.0.0
EOF

  cat > "${BIN_DIR}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "aws $*" >> "$FAKE_COMMAND_LOG"

case "${1:-} ${2:-}" in
  "sts get-caller-identity")
    echo "123456789012"
    ;;
  "ecr describe-repositories")
    ;;
  "ecr get-login-password")
    echo "password"
    ;;
  "ecr batch-delete-image")
    ;;
  *)
    echo "unexpected aws command: $*" >&2
    exit 1
    ;;
esac
EOF

  cat > "${BIN_DIR}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "docker $*" >> "$FAKE_COMMAND_LOG"

case "${1:-} ${2:-}" in
  "buildx version")
    ;;
  "buildx inspect")
    ;;
  "buildx use")
    ;;
  "buildx build")
    ;;
  "buildx imagetools")
    ;;
  "login --username")
    cat >/dev/null
    ;;
  "pull --platform")
    ;;
  "image inspect")
    ;;
  "tag "*)
    ;;
  "push "*)
    ;;
  *)
    echo "unexpected docker command: $*" >&2
    exit 1
    ;;
esac
EOF

  cat > "${BIN_DIR}/container-structure-test" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "container-structure-test $*" >> "$FAKE_COMMAND_LOG"
EOF

  chmod +x "${BIN_DIR}/aws" "${BIN_DIR}/docker" "${BIN_DIR}/container-structure-test"

  export PATH="${BIN_DIR}:${PATH}"
  export FAKE_COMMAND_LOG="$LOG_FILE"
}

@test "single-platform structure test path builds once then pushes tested image" {
  run "$SCRIPT" \
    -r ado-agent \
    -t v1.2.3 \
    --context "$CTX" \
    --platforms linux/amd64 \
    --builder testbuilder

  [ "$status" -eq 0 ]

  run grep -c "docker buildx build" "$LOG_FILE"
  [ "$output" -eq 1 ]

  grep -q "docker buildx build .* --platform linux/amd64 .* --load " "$LOG_FILE"
  grep -q "container-structure-test test --image 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3 .* --platform linux/amd64" "$LOG_FILE"
  grep -q "docker push 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3" "$LOG_FILE"
  ! grep -q "docker buildx build .* --push " "$LOG_FILE"
}

@test "multi-platform structure test path tests locally before pushing temporary tags" {
  run "$SCRIPT" \
    -r ado-agent \
    -t v1.2.3 \
    --context "$CTX" \
    --platforms linux/amd64,linux/arm64 \
    --builder testbuilder

  [ "$status" -eq 0 ]

  run grep -c "docker buildx build" "$LOG_FILE"
  [ "$output" -eq 2 ]

  grep -q "docker buildx build .* --platform linux/amd64 .* -t ado-build-local/ado-agent:v1.2.3-linux-amd64 --load " "$LOG_FILE"
  grep -q "docker buildx build .* --platform linux/arm64 .* -t ado-build-local/ado-agent:v1.2.3-linux-arm64 --load " "$LOG_FILE"
  grep -q "container-structure-test test --image ado-build-local/ado-agent:v1.2.3-linux-amd64 .* --platform linux/amd64" "$LOG_FILE"
  grep -q "container-structure-test test --image ado-build-local/ado-agent:v1.2.3-linux-arm64 .* --platform linux/arm64" "$LOG_FILE"
  grep -q "docker tag ado-build-local/ado-agent:v1.2.3-linux-amd64 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3-buildtest-linux-amd64-" "$LOG_FILE"
  grep -q "docker tag ado-build-local/ado-agent:v1.2.3-linux-arm64 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3-buildtest-linux-arm64-" "$LOG_FILE"
  grep -q "docker push 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3-buildtest-linux-amd64-" "$LOG_FILE"
  grep -q "docker push 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3-buildtest-linux-arm64-" "$LOG_FILE"
  grep -q "docker buildx imagetools create -t 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3-buildtest-linux-amd64-.* 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3-buildtest-linux-arm64-" "$LOG_FILE"
  grep -q "aws ecr batch-delete-image .* --image-ids imageTag=v1.2.3-buildtest-linux-amd64-" "$LOG_FILE"
  grep -q "aws ecr batch-delete-image .* --image-ids imageTag=v1.2.3-buildtest-linux-arm64-" "$LOG_FILE"
  ! grep -q "docker pull --platform" "$LOG_FILE"

  local first_push_line second_test_line
  first_push_line="$(grep -n "docker push 123456789012.dkr.ecr.us-west-2.amazonaws.com/ado-agent:v1.2.3-buildtest-" "$LOG_FILE" | head -n 1 | cut -d: -f1)"
  second_test_line="$(grep -n "container-structure-test test --image ado-build-local/ado-agent:v1.2.3-linux-arm64" "$LOG_FILE" | cut -d: -f1)"
  [ "$first_push_line" -gt "$second_test_line" ]
}
