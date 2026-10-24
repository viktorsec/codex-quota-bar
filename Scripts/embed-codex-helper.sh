#!/bin/bash
set -euo pipefail

# The prototype builds for the host architecture. Universal distribution needs
# both prepared slices and a merged helper; it must not ship a mismatched helper.
helper_source="$SRCROOT/Vendor/Codex/$NATIVE_ARCH_ACTUAL/codex-app-server"
if [[ ! -x "$helper_source" ]]; then
    echo "error: Run bash Scripts/prepare-codex-helper.sh $NATIVE_ARCH_ACTUAL before building." >&2
    exit 1
fi
# Stage in Xcode's scratch directory so copying and signing can create their
# temporary sibling files while build-script sandboxing remains enabled.
helper_dir="$TARGET_TEMP_DIR/CodexHelper"
resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Codex"
mkdir -p "$helper_dir" "$resource_dir"
install -m 755 "$helper_source" "$helper_dir/codex-app-server"
cp "$SRCROOT/Vendor/Codex/LICENSE" "$resource_dir/LICENSE"
cp "$SRCROOT/Vendor/Codex/NOTICE" "$resource_dir/NOTICE"
cp "$SRCROOT/Vendor/Codex/VERSION" "$resource_dir/VERSION"

# Attach sandbox-inheritance entitlements without accessing a signing key.
# Xcode's native Copy Files phase signs the embedded copy with the app's identity.
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
    --entitlements "$SRCROOT/Configuration/CodexHelper.entitlements" \
    "$helper_dir/codex-app-server"
