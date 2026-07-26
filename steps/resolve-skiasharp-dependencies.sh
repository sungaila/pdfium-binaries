#!/bin/bash
set -euo pipefail

SKIASHARP_VERSION=${SKIASHARP_VERSION:?SKIASHARP_VERSION is required}
ENV_FILE=${GITHUB_ENV:-$PWD/.env}

if [[ ! "$SKIASHARP_VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]]; then
  echo "Invalid SkiaSharp version: $SKIASHARP_VERSION" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

CGMANIFEST="$WORK_DIR/cgmanifest.json"
DEPS_FILE="$WORK_DIR/DEPS"
JCONFIG_FILE="$WORK_DIR/jconfig.h"
RESOLVED_TAG=""

for TAG in "v$SKIASHARP_VERSION" "$SKIASHARP_VERSION"; do
  URL="https://raw.githubusercontent.com/mono/SkiaSharp/$TAG/cgmanifest.json"
  if curl --fail --silent --show-error --location --retry 3 \
      "$URL" --output "$CGMANIFEST"; then
    RESOLVED_TAG="$TAG"
    break
  fi
done

if [[ -z "$RESOLVED_TAG" ]]; then
  echo "Unable to find cgmanifest.json for SkiaSharp $SKIASHARP_VERSION." >&2
  echo "Expected a mono/SkiaSharp tag named v$SKIASHARP_VERSION or $SKIASHARP_VERSION." >&2
  exit 1
fi

readarray -t MANIFEST_VALUES < <(python3 - "$CGMANIFEST" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
with open(manifest_path, encoding="utf-8") as stream:
    manifest = json.load(stream)

def normalize_repository(url: str) -> str:
    value = url.rstrip("/").lower()
    return value[:-4] if value.endswith(".git") else value

skia_commit = None
libjpeg_version = None
for registration in manifest.get("registrations", []):
    component = registration.get("component", {})

    git_component = component.get("git")
    if git_component:
        repository = normalize_repository(git_component.get("repositoryUrl", ""))
        if repository == "https://github.com/mono/skia":
            skia_commit = git_component.get("commitHash")

    other_component = component.get("other")
    if other_component and other_component.get("name", "").lower() == "libjpeg-turbo":
        libjpeg_version = other_component.get("version")

if not skia_commit:
    raise SystemExit("cgmanifest.json does not contain the mono/skia commit")
if len(skia_commit) != 40 or any(ch not in "0123456789abcdefABCDEF" for ch in skia_commit):
    raise SystemExit(f"Invalid mono/skia commit in cgmanifest.json: {skia_commit}")

print(skia_commit.lower())
print(libjpeg_version or "")
PY
)

SKIASHARP_SKIA_COMMIT=${MANIFEST_VALUES[0]}
CGMANIFEST_LIBJPEG_TURBO_VERSION=${MANIFEST_VALUES[1]}
SKIA_RAW_BASE="https://raw.githubusercontent.com/mono/skia/$SKIASHARP_SKIA_COMMIT"

curl --fail --silent --show-error --location --retry 3 \
  "$SKIA_RAW_BASE/DEPS" \
  --output "$DEPS_FILE"

readarray -t DEPS_VALUES < <(python3 - "$DEPS_FILE" <<'PY'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    deps = stream.read()

match = re.search(
    r'["\']third_party/externals/libjpeg-turbo["\']\s*:\s*'
    r'["\']([^"\']+)@([0-9a-fA-F]{40})["\']',
    deps,
)
if not match:
    raise SystemExit("mono/skia DEPS does not contain a pinned libjpeg-turbo revision")

print(match.group(1))
print(match.group(2).lower())
PY
)

SKIASHARP_LIBJPEG_TURBO_REPOSITORY=${DEPS_VALUES[0]}
SKIASHARP_LIBJPEG_TURBO_COMMIT=${DEPS_VALUES[1]}

curl --fail --silent --show-error --location --retry 3 \
  "$SKIA_RAW_BASE/third_party/libjpeg-turbo/jconfig.h" \
  --output "$JCONFIG_FILE"

SKIASHARP_LIBJPEG_TURBO_VERSION=$(awk \
  '$1 == "#define" && $2 == "LIBJPEG_TURBO_VERSION" { gsub(/"/, "", $3); print $3 }' \
  "$JCONFIG_FILE")
SKIASHARP_JPEG_LIB_VERSION=$(awk \
  '$1 == "#define" && $2 == "JPEG_LIB_VERSION" { print $3 }' \
  "$JCONFIG_FILE")

if [[ -z "$SKIASHARP_LIBJPEG_TURBO_VERSION" ]]; then
  echo "Unable to determine LIBJPEG_TURBO_VERSION from mono/skia jconfig.h." >&2
  exit 1
fi
if [[ -z "$SKIASHARP_JPEG_LIB_VERSION" ]]; then
  echo "Unable to determine JPEG_LIB_VERSION from mono/skia jconfig.h." >&2
  exit 1
fi
if [[ -n "$CGMANIFEST_LIBJPEG_TURBO_VERSION" ]] && \
   [[ "$CGMANIFEST_LIBJPEG_TURBO_VERSION" != "$SKIASHARP_LIBJPEG_TURBO_VERSION" ]]; then
  echo "SkiaSharp dependency metadata is inconsistent:" >&2
  echo "  cgmanifest.json: $CGMANIFEST_LIBJPEG_TURBO_VERSION" >&2
  echo "  mono/skia jconfig.h: $SKIASHARP_LIBJPEG_TURBO_VERSION" >&2
  exit 1
fi

export SKIASHARP_VERSION
export SKIASHARP_TAG="$RESOLVED_TAG"
export SKIASHARP_SKIA_COMMIT
export SKIASHARP_LIBJPEG_TURBO_REPOSITORY
export SKIASHARP_LIBJPEG_TURBO_VERSION
export SKIASHARP_LIBJPEG_TURBO_COMMIT
export SKIASHARP_JPEG_LIB_VERSION

cat >>"$ENV_FILE" <<END
SKIASHARP_VERSION=$SKIASHARP_VERSION
SKIASHARP_TAG=$SKIASHARP_TAG
SKIASHARP_SKIA_COMMIT=$SKIASHARP_SKIA_COMMIT
SKIASHARP_LIBJPEG_TURBO_REPOSITORY=$SKIASHARP_LIBJPEG_TURBO_REPOSITORY
SKIASHARP_LIBJPEG_TURBO_VERSION=$SKIASHARP_LIBJPEG_TURBO_VERSION
SKIASHARP_LIBJPEG_TURBO_COMMIT=$SKIASHARP_LIBJPEG_TURBO_COMMIT
SKIASHARP_JPEG_LIB_VERSION=$SKIASHARP_JPEG_LIB_VERSION
END

cat <<END
Resolved SkiaSharp native dependencies:
  SkiaSharp tag:         $SKIASHARP_TAG
  mono/skia commit:      $SKIASHARP_SKIA_COMMIT
  libjpeg-turbo repo:    $SKIASHARP_LIBJPEG_TURBO_REPOSITORY
  libjpeg-turbo version: $SKIASHARP_LIBJPEG_TURBO_VERSION
  libjpeg-turbo commit:  $SKIASHARP_LIBJPEG_TURBO_COMMIT
  JPEG ABI:              $SKIASHARP_JPEG_LIB_VERSION
END

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >>"$GITHUB_STEP_SUMMARY" <<END
## SkiaSharp native dependency resolution

| Dependency | Resolved value |
|---|---|
| SkiaSharp | \`$SKIASHARP_VERSION\` (tag \`$SKIASHARP_TAG\`) |
| mono/skia | \`$SKIASHARP_SKIA_COMMIT\` |
| libjpeg-turbo | \`$SKIASHARP_LIBJPEG_TURBO_VERSION\` |
| libjpeg-turbo commit | \`$SKIASHARP_LIBJPEG_TURBO_COMMIT\` |
| JPEG ABI | \`JPEG_LIB_VERSION=$SKIASHARP_JPEG_LIB_VERSION\` |
END
fi
