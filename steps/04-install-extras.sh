#!/bin/bash -eux

PATH_FILE=${GITHUB_PATH:-$PWD/.path}
ENV_FILE=${GITHUB_ENV:-$PWD/.env}
ROOT=$PWD
SOURCE="${PDFium_SOURCE_DIR:-pdfium}"
TARGET_OS=${PDFium_TARGET_OS:?}
TARGET_ENVIRONMENT=${PDFium_TARGET_ENVIRONMENT:-}
TARGET_CPU=${PDFium_TARGET_CPU:?}
USE_SYSTEM_LIBJPEG=${PDFium_USE_SYSTEM_LIBJPEG:-false}

SKIASHARP_VERSION=${SKIASHARP_VERSION:-4.150.1}

if [ "$TARGET_OS" == "emscripten" ] && [ "$USE_SYSTEM_LIBJPEG" == "true" ] &&
   { [ -z "${SKIASHARP_SKIA_COMMIT:-}" ] ||
     [ -z "${SKIASHARP_LIBJPEG_TURBO_REPOSITORY:-}" ] ||
     [ -z "${SKIASHARP_LIBJPEG_TURBO_VERSION:-}" ] ||
     [ -z "${SKIASHARP_LIBJPEG_TURBO_COMMIT:-}" ] ||
     [ -z "${SKIASHARP_JPEG_LIB_VERSION:-}" ]; }; then
  # Local builds reach this fallback directly. GitHub Actions resolves these
  # values in a dedicated step and persists them through GITHUB_ENV.
  "$ROOT/steps/resolve-skiasharp-dependencies.sh"
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi

install_skiasharp_libjpeg_turbo_headers() {
  local LIBJPEG_DIR="$PWD/third_party/skiasharp_libjpeg_turbo"
  local SKIA_RAW_BASE="https://raw.githubusercontent.com/mono/skia/$SKIASHARP_SKIA_COMMIT/third_party/libjpeg-turbo"
  local ACTUAL_VERSION

  rm -rf "$LIBJPEG_DIR"
  mkdir -p "$LIBJPEG_DIR"

  # Fetch the exact libjpeg-turbo source revision pinned by the mono/skia
  # revision used to build the selected SkiaSharp version.
  git -C "$LIBJPEG_DIR" init
  git -C "$LIBJPEG_DIR" remote add origin \
    "$SKIASHARP_LIBJPEG_TURBO_REPOSITORY"
  git -C "$LIBJPEG_DIR" fetch --depth 1 origin \
    "$SKIASHARP_LIBJPEG_TURBO_COMMIT"
  git -C "$LIBJPEG_DIR" checkout --detach FETCH_HEAD

  # Skia's GN build does not run libjpeg-turbo's CMake configure step. Instead,
  # SkiaSharp uses these exact pre-baked configuration headers from mono/skia.
  for HEADER in jconfig.h jconfigint.h jversion.h; do
    curl \
      --fail \
      --location \
      --retry 3 \
      "$SKIA_RAW_BASE/$HEADER" \
      --output "$LIBJPEG_DIR/$HEADER"
  done

  test "$(git -C "$LIBJPEG_DIR" rev-parse HEAD)" = \
    "$SKIASHARP_LIBJPEG_TURBO_COMMIT"
  test -f "$LIBJPEG_DIR/src/jpeglib.h"
  test -f "$LIBJPEG_DIR/src/jmorecfg.h"
  test -f "$LIBJPEG_DIR/jconfig.h"
  test -f "$LIBJPEG_DIR/jconfigint.h"
  test -f "$LIBJPEG_DIR/jversion.h"

  grep -Eq "^#define JPEG_LIB_VERSION[[:space:]]+$SKIASHARP_JPEG_LIB_VERSION$" \
    "$LIBJPEG_DIR/jconfig.h"

  ACTUAL_VERSION=$(awk \
    '$1 == "#define" && $2 == "LIBJPEG_TURBO_VERSION" { gsub(/"/, "", $3); print $3 }' \
    "$LIBJPEG_DIR/jconfig.h")
  test "$ACTUAL_VERSION" = "$SKIASHARP_LIBJPEG_TURBO_VERSION"

  ACTUAL_VERSION=$(awk \
    '$1 == "#define" && $2 == "VERSION" { gsub(/"/, "", $3); print $3 }' \
    "$LIBJPEG_DIR/jconfigint.h")
  test "$ACTUAL_VERSION" = "$SKIASHARP_LIBJPEG_TURBO_VERSION"

  cat <<END
Using SkiaSharp-compatible libjpeg-turbo headers:
  SkiaSharp:      $SKIASHARP_VERSION
  mono/skia:      $SKIASHARP_SKIA_COMMIT
  libjpeg-turbo:  $SKIASHARP_LIBJPEG_TURBO_VERSION
  libjpeg commit: $SKIASHARP_LIBJPEG_TURBO_COMMIT
  JPEG ABI:       $SKIASHARP_JPEG_LIB_VERSION
END
}

pushd "$SOURCE"

case "$TARGET_OS" in
  linux)
    build/install-build-deps.sh --no-prompt
    gclient runhooks
    build/linux/sysroot_scripts/install-sysroot.py "--arch=$TARGET_CPU"

    if [ "$TARGET_ENVIRONMENT" == "musl" ]; then
      case "$TARGET_CPU" in
        x86)
          MUSL_VERSION="i686-linux-musl-cross"
          ;;
        x64)
          MUSL_VERSION="x86_64-linux-musl-cross"
          ;;
        arm)
          MUSL_VERSION="arm-linux-musleabihf-cross"
          ;;
        arm64)
          MUSL_VERSION="aarch64-linux-musl-cross"
          ;;
      esac
      ln -sf "$ROOT/$MUSL_VERSION" "third_party/$MUSL_VERSION"
    fi
    ;;

  android)
    build/install-build-deps.sh --no-prompt --android
    gclient runhooks
    ;;

  emscripten)
    pushd third_party
    if [ -e "emsdk" ]; then
      git -C "emsdk" pull
    else
      git clone https://github.com/emscripten-core/emsdk.git
    fi
    cd emsdk
    ./emsdk install ${EMSDK_VERSION:-latest}
    ./emsdk activate ${EMSDK_VERSION:-latest}
    echo "$PWD/upstream/emscripten" >> "$PATH_FILE"
    echo "$PWD/upstream/bin" >> "$PATH_FILE"
    popd

    # Do not use Emscripten's libjpeg port here. Emscripten 3.1.56 ships an
    # IJG v9 ABI, which can differ from the libjpeg-turbo ABI bundled by the
    # selected SkiaSharp release. PDFium must compile against SkiaSharp's headers.
    [ "$USE_SYSTEM_LIBJPEG" == "true" ] && install_skiasharp_libjpeg_turbo_headers
    ;;
esac

popd
