#!/bin/bash -eux

IS_DEBUG=${PDFium_IS_DEBUG:-false}
OS=${PDFium_TARGET_OS:?}
VERSION=${PDFium_VERSION:-}
PATCHES="$PWD/patches"
BUILD_TYPE=${PDFium_BUILD_TYPE:-shared}
USE_SYSTEM_LIBJPEG=${PDFium_USE_SYSTEM_LIBJPEG:-false}

SOURCE=${PDFium_SOURCE_DIR:-pdfium}
BUILD=${PDFium_BUILD_DIR:-pdfium/out}

STAGING="$PWD/staging"
STAGING_BIN="$STAGING/bin"
STAGING_LIB="$STAGING/lib"

mkdir -p "$STAGING"
rm -rf "$STAGING"/*
mkdir -p "$STAGING_LIB"

case "$BUILD_TYPE" in
  shared)
    CMAKE_CONFIG_FILE="PDFiumConfig.cmake"
    ;;
  static)
    CMAKE_CONFIG_FILE="PDFiumStaticConfig.cmake"
    ;;
esac
sed "s/#VERSION#/${VERSION:-0.0.0.0}/" <"$PATCHES/$CMAKE_CONFIG_FILE" >"$STAGING/PDFiumConfig.cmake"

cp LICENSE "$STAGING"
cat >>"$STAGING/LICENSE" <<END

This package also includes third-party software. See the licenses/ directory for their respective licenses.
END

cp "$BUILD/args.gn" "$STAGING"
cp -R "$SOURCE/public" "$STAGING/include"
rm -f "$STAGING/include/DEPS"
rm -f "$STAGING/include/README"
rm -f "$STAGING/include/PRESUBMIT.py"

case "$OS-$BUILD_TYPE" in
  android-shared|linux-shared)
    mv "$BUILD/libpdfium.so" "$STAGING_LIB"
    ;;

  android-static|linux-static|mac-static|ios-static)
    mv "$BUILD/obj/libpdfium.a" "$STAGING_LIB"
    ;;

  mac-shared|ios-shared)
    mv "$BUILD/libpdfium.dylib" "$STAGING_LIB"
    ;;

  emscripten-*)
    mv "$BUILD/obj/libpdfium.a" "$STAGING_LIB"
    rm -rf "$STAGING/include/cpp"
    rm "$STAGING/PDFiumConfig.cmake"
    ;;

  win-shared)
    mv "$BUILD/pdfium.dll.lib" "$STAGING_LIB"
    mkdir -p "$STAGING_BIN"
    mv "$BUILD/pdfium.dll" "$STAGING_BIN"
    [ "$IS_DEBUG" == "true" ] && mv "$BUILD/pdfium.dll.pdb" "$STAGING_BIN"
    ;;

  win-shared)
    mv "$BUILD/obj/pdfium.lib" "$STAGING_LIB"
    ;;
esac

if [ -n "$VERSION" ]; then
  cat >"$STAGING/VERSION" <<END
MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)
BUILD=$(echo "$VERSION" | cut -d. -f3)
PATCH=$(echo "$VERSION" | cut -d. -f4)
END
fi

if [ "$OS" == "emscripten" ] && [ "$USE_SYSTEM_LIBJPEG" == "true" ]; then
  : "${SKIASHARP_VERSION:?SkiaSharp dependency resolution was not run}"
  : "${SKIASHARP_TAG:?SkiaSharp dependency resolution was not run}"
  : "${SKIASHARP_SKIA_COMMIT:?SkiaSharp dependency resolution was not run}"
  : "${SKIASHARP_LIBJPEG_TURBO_REPOSITORY:?SkiaSharp dependency resolution was not run}"
  : "${SKIASHARP_LIBJPEG_TURBO_VERSION:?SkiaSharp dependency resolution was not run}"
  : "${SKIASHARP_LIBJPEG_TURBO_COMMIT:?SkiaSharp dependency resolution was not run}"
  : "${SKIASHARP_JPEG_LIB_VERSION:?SkiaSharp dependency resolution was not run}"

  cat >"$STAGING/SKIASHARP_LIBJPEG_TURBO" <<END
SKIASHARP_VERSION=$SKIASHARP_VERSION
SKIASHARP_TAG=$SKIASHARP_TAG
SKIASHARP_SKIA_COMMIT=$SKIASHARP_SKIA_COMMIT
LIBJPEG_TURBO_REPOSITORY=$SKIASHARP_LIBJPEG_TURBO_REPOSITORY
LIBJPEG_TURBO_VERSION=$SKIASHARP_LIBJPEG_TURBO_VERSION
LIBJPEG_TURBO_COMMIT=$SKIASHARP_LIBJPEG_TURBO_COMMIT
JPEG_LIB_VERSION=$SKIASHARP_JPEG_LIB_VERSION
END
fi
