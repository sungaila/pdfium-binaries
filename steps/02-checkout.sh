#!/bin/bash -eux

PDFium_URL='https://pdfium.googlesource.com/pdfium.git'
OS=${PDFium_TARGET_OS:?}
ENABLE_V8=${PDFium_ENABLE_V8:-false}

CONFIG_ARGS=()

# Clone
gclient config --unmanaged "$PDFium_URL" "${CONFIG_ARGS[@]-}"
echo "target_os = [ '$OS' ]" >> .gclient


# Reset
for FOLDER in pdfium pdfium/build pdfium/v8 pdfium/third_party/libjpeg_turbo pdfium/base/allocator/partition_allocator; do
  if [ -e "$FOLDER" ]; then
    git -C $FOLDER reset --hard
    git -C $FOLDER clean -df
  fi
done

gclient sync -r "origin/${PDFium_BRANCH:-main}" --no-history --shallow

set +e
FOUND=""
for d in third_party/libjpeg_turbo third_party/libjpeg; do
  if [ -f "pdfium/$d/jerror.h" ] && [ -f "pdfium/$d/jpeglib.h" ]; then
    echo "Found JPEG headers in pdfium/$d"
    FOUND="yes"
    break
  fi
done
set -e
if [ -z "$FOUND" ]; then
  echo "ERROR: libjpeg headers (jerror.h / jpeglib.h) wurden nicht eingecheckt."
  echo "Tipp: checkout_configuration=minimal entfernen oder auf 'default' setzen."
  exit 1
fi