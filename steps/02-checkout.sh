#!/bin/bash -eux

PDFium_URL='https://pdfium.googlesource.com/pdfium.git'
OS=${PDFium_TARGET_OS:?}
ENABLE_V8=${PDFium_ENABLE_V8:-false}

CONFIG_ARGS=()
# Clone
CONFIG_ARGS+=( --custom-var "checkout_configuration=default" )
gclient config --unmanaged "$PDFium_URL" "${CONFIG_ARGS[@]-}"
cat >> .gclient <<EOF
target_os = [ "linux", "$OS" ]
EOF


# Reset
for FOLDER in pdfium pdfium/build pdfium/v8 pdfium/third_party/libjpeg_turbo pdfium/base/allocator/partition_allocator; do
  if [ -e "$FOLDER" ]; then
    git -C $FOLDER reset --hard
    git -C $FOLDER clean -df
  fi
done

gclient sync -r "origin/${PDFium_BRANCH:-main}" --no-history --shallow --reset --force --delete_unversioned_trees
gclient runhooks

test -f pdfium/third_party/libjpeg_turbo/jerror.h && echo ok || echo missing
test -f pdfium/third_party/libjpeg_turbo/jpeglib.h && echo ok || echo missing
test -f pdfium/gen/third_party/libjpeg_turbo/jconfig.h && echo gen-ok || echo gen-missing