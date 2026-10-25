#!/bin/bash
set -euo pipefail

# The prototype builds for the host architecture. Universal distribution needs
# both prepared slices and a merged helper; it must not ship a mismatched helper.
helper_source="$SRCROOT/Vendor/Codex/$NATIVE_ARCH_ACTUAL/codex-app-server"
if [[ ! -x "$helper_source" ]]; then
    echo "error: Run bash Scripts/prepare-codex-helper.sh $NATIVE_ARCH_ACTUAL before building." >&2
    exit 1
fi
# Xcode permits scratch files under TARGET_TEMP_DIR. DerivedSources is stricter:
# codesign's temporary sibling file is denied even when the executable is a
# declared output. Keep the staging executable in the dedicated scratch area.
helper_dir="$TARGET_TEMP_DIR/CodexHelper"
resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Codex"
mkdir -p "$helper_dir" "$resource_dir"
install -m 755 "$helper_source" "$helper_dir/UseYourTokensAccountHelper"
debug_mode=0
if [[ "$CONFIGURATION" == Debug ]]; then debug_mode=1; fi
/usr/bin/xcrun clang -fobjc-arc -fno-modules -Wno-deprecated-declarations \
    -DQUOTA_DEBUG="$debug_mode" \
    -arch "$NATIVE_ARCH_ACTUAL" -isysroot "$SDKROOT" \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    -framework Foundation -framework Security \
    "$SRCROOT/HelperSources/CredentialStore.m" \
    "$SRCROOT/HelperSources/Tests/CredentialStoreTests.m" \
    -o "$helper_dir/UseYourTokensCredentialStore"
cp "$SRCROOT/Vendor/Codex/LICENSE" "$resource_dir/LICENSE"
cp "$SRCROOT/Vendor/Codex/NOTICE" "$resource_dir/NOTICE"
cp "$SRCROOT/Vendor/Codex/VERSION" "$resource_dir/VERSION"

# Stage the inheritance entitlements with an ad-hoc signature, which needs no
# Keychain access. Xcode's native Copy Files phase then signs the embedded copy
# using the app's identity, preserving these entitlements. Signing with a real
# identity inside this sandboxed script cannot reliably access the Keychain.
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
    --identifier "$PRODUCT_BUNDLE_IDENTIFIER.AccountHelper" \
    --entitlements "$SRCROOT/Configuration/CodexHelper.entitlements" \
    "$helper_dir/UseYourTokensAccountHelper"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none \
    --identifier "$PRODUCT_BUNDLE_IDENTIFIER.CredentialStore" \
    --entitlements "$SRCROOT/Configuration/CodexHelper.entitlements" \
    "$helper_dir/UseYourTokensCredentialStore"
