#!/usr/bin/env bash
# validate-bridge-build.sh - Validates that the bridge binary can be built
# with CGO_ENABLED=0 (static binary for Alpine Docker images).
#
# This catches issues like the Oracle/godror CGO dependency that breaks
# the bridge Dockerfile build.

set -euo pipefail

# Source directory for the bridge (relative to workspace root)
CORE_API_DIR="${CORE_API_DIR:-/mnt/c/git/core-api/schemabounce-api}"
BRIDGE_CMD_DIR="${CORE_API_DIR}/cmd/bridge"

echo "=== Bridge Build Validation ==="

# Check source directory exists
if [ ! -d "$BRIDGE_CMD_DIR" ]; then
    echo "SKIP: Bridge source not found at ${BRIDGE_CMD_DIR}"
    echo "Set CORE_API_DIR to override the source location."
    exit 0
fi

# Check go.mod exists
if [ ! -f "${CORE_API_DIR}/go.mod" ]; then
    echo "SKIP: No go.mod found at ${CORE_API_DIR}/go.mod"
    exit 0
fi

echo "Source: ${BRIDGE_CMD_DIR}"
echo ""

# 1. Test CGO_ENABLED=0 build (matches Dockerfile)
echo "--- Test 1: CGO_ENABLED=0 (static binary, matches Dockerfile) ---"
TMPBIN=$(mktemp)
trap 'rm -f "$TMPBIN"' EXIT

if (cd "${CORE_API_DIR}" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags "-X main.Version=validate -X main.GitCommit=validate -X main.BuildTime=validate" \
    -o "$TMPBIN" \
    ./cmd/bridge/); then
    echo "PASS: CGO_ENABLED=0 build succeeded"
    # Verify it's statically linked
    if file "$TMPBIN" | grep -q "statically linked"; then
        echo "PASS: Binary is statically linked"
    else
        echo "WARN: Binary may not be statically linked"
        file "$TMPBIN"
    fi
else
    echo "FAIL: CGO_ENABLED=0 build failed!"
    echo ""
    echo "This means the bridge Dockerfile will fail to build."
    echo "Common cause: a CGO-dependent package (like godror/Oracle) is"
    echo "being imported transitively. Check for new blank imports in"
    echo "internal/services/pipeline/ or internal/pipeline/producer/."
    exit 1
fi

echo ""

# 2. Run go vet on bridge package
echo "--- Test 2: go vet (static analysis) ---"
if (cd "${CORE_API_DIR}" && CGO_ENABLED=0 go vet ./cmd/bridge/ ./internal/bridge/...); then
    echo "PASS: go vet passed"
else
    echo "FAIL: go vet found issues"
    exit 1
fi

echo ""
echo "=== All bridge build validations passed ==="
