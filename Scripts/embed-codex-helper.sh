#!/bin/bash
set -euo pipefail

# The prototype builds for the host architecture. Universal distribution needs
# both prepared slices and a merged helper; it must not ship a mismatched helper.
helper_source="$SRCROOT/Vendor/Codex/$NATIVE_ARCH_ACTUAL/codex-app-server"
if [[ ! -x "$helper_source" ]]; then
    echo "error: Run bash Scripts/prepare-codex-helper.sh $NATIVE_ARCH_ACTUAL before building." >&2
    exit 1
fi
helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Codex"
mkdir -p "$helper_dir" "$resource_dir"
install -m 755 "$helper_source" "$helper_dir/codex-app-server"
cp "$SRCROOT/Vendor/Codex/LICENSE" "$resource_dir/LICENSE"
cp "$SRCROOT/Vendor/Codex/NOTICE" "$resource_dir/NOTICE"
cp "$SRCROOT/Vendor/Codex/VERSION" "$resource_dir/VERSION"

# Always sign the helper, including ad-hoc development builds. These two
# entitlements make the child inherit the parent app's sandbox permissions.
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$identity" ]]; then identity="-"; fi
/usr/bin/codesign --force --sign "$identity" --options runtime --timestamp=none \
    --entitlements "$SRCROOT/Configuration/CodexHelper.entitlements" \
    "$helper_dir/codex-app-server"
