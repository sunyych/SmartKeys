#!/bin/sh
set -eu

cargo=$(command -v cargo || true)
if [ -z "$cargo" ] && [ -x "${HOME}/.cargo/bin/cargo" ]; then
  cargo="${HOME}/.cargo/bin/cargo"
fi
if [ -z "$cargo" ]; then
  echo 'error: Cargo is required to build LumiaKey Desktop.' >&2
  exit 1
fi

manifest="$SRCROOT/../native/windows_shortcuts/Cargo.toml"
target_dir="$DERIVED_FILE_DIR/lumiakeys-rust"
frameworks="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$target_dir" "$frameworks"

set --
for arch in $ARCHS; do
  case "$arch" in
    arm64) target=aarch64-apple-darwin ;;
    x86_64) target=x86_64-apple-darwin ;;
    *) echo "error: Unsupported LumiaKey macOS architecture: $arch" >&2; exit 1 ;;
  esac
  "$cargo" build --locked --release --manifest-path "$manifest" \
    --target "$target" --target-dir "$target_dir"
  set -- "$@" "$target_dir/$target/release/liblumiakeys_windows_shortcuts.dylib"
done

intermediate="$target_dir/liblumiakeys_desktop.dylib"
case "$#" in
  0) echo 'error: Xcode did not specify a LumiaKey architecture.' >&2; exit 1 ;;
  1) cp "$1" "$intermediate" ;;
  *) /usr/bin/lipo -create "$@" -output "$intermediate" ;;
esac
/usr/bin/install_name_tool -id '@rpath/liblumiakeys_desktop.dylib' "$intermediate"
library="$frameworks/liblumiakeys_desktop.dylib"
/usr/bin/install -m 755 "$intermediate" "$library"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$library"
fi
