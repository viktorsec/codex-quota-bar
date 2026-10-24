// Codex Quota Bar's credential access gate. No token data is ever printed.
// Codex 0.164.0's direct keyring backend uses the legacy file-based Keychain;
// SecAccess is needed to trust the account helper alongside this broker.
#import "CredentialStore.h"

CredentialStoreStatus CredentialStorePrepare(NSString *service, NSString *account, NSString *helperPath) {
    // Applies only to this process: no lookup or write may display password UI.
    if (SecKeychainSetUserInteractionAllowed(false) != errSecSuccess) return CredentialStoreStorageUnavailable;
    SecKeychainRef keychain = NULL;
    if (SecKeychainCopyDefault(&keychain) != errSecSuccess) return CredentialStoreStorageUnavailable;
    SecKeychainStatus state = 0;
    OSStatus status = SecKeychainGetStatus(keychain, &state);
    if (status != errSecSuccess) { CFRelease(keychain); return CredentialStoreStorageUnavailable; }
    if (!(state & kSecUnlockStateStatus)) { CFRelease(keychain); return CredentialStoreKeychainLocked; }

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecMatchSearchList: @[(__bridge id)keychain],
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecReturnAttributes: @YES
    };
    CFTypeRef saved = NULL;
    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &saved);
    // The public signing-requirement API verifies that the current account
    // helper still matches the identity we granted access when creating this
    // entry. Generic metadata survives Codex's password-data-only updates.
    SecStaticCodeRef code = NULL;
    NSURL *helperURL = [NSURL fileURLWithPath:helperPath];
    OSStatus codeStatus = SecStaticCodeCreateWithPath((__bridge CFURLRef)helperURL, kSecCSDefaultFlags, &code);
    BOOL matchingHelper = NO;
    BOOL hasTokens = NO;
    if (status == errSecSuccess && saved && codeStatus == errSecSuccess) {
        NSDictionary *record = (__bridge NSDictionary *)saved;
        NSData *identity = record[(__bridge id)kSecAttrGeneric];
        NSData *value = record[(__bridge id)kSecValueData];
        if ([value isKindOfClass:NSData.class]) {
            id payload = [NSJSONSerialization JSONObjectWithData:value options:0 error:NULL];
            id tokens = [payload isKindOfClass:NSDictionary.class] ? payload[@"tokens"] : nil;
            id accessToken = [tokens isKindOfClass:NSDictionary.class] ? tokens[@"access_token"] : nil;
            hasTokens = [accessToken isKindOfClass:NSString.class] && [accessToken length] > 0;
        }
        if ([identity isKindOfClass:NSData.class]) {
            SecRequirementRef requirement = NULL;
            if (SecRequirementCreateWithData((__bridge CFDataRef)identity, kSecCSDefaultFlags, &requirement) == errSecSuccess) {
                matchingHelper = SecStaticCodeCheckValidity(code, kSecCSDefaultFlags, requirement) == errSecSuccess;
                CFRelease(requirement);
            }
        }
    }
    // Check actual access under the broker's stable identity; discard all bytes.
    if (saved) CFRelease(saved);
    if (status == errSecSuccess) {
        if (code) CFRelease(code);
        CFRelease(keychain);
        return matchingHelper ? (hasTokens ? CredentialStoreReady : CredentialStoreSignedOut) : CredentialStoreSignInRequired;
    }
    if (code) CFRelease(code);
    if (status == errSecInteractionNotAllowed || status == errSecAuthFailed) {
        CFRelease(keychain);
        return CredentialStoreSignInRequired;
    }
    if (status != errSecItemNotFound) { CFRelease(keychain); return CredentialStoreStorageUnavailable; }

    SecTrustedApplicationRef broker = NULL, helper = NULL;
    SecAccessRef access = NULL;
    CFDataRef identity = NULL;
    status = SecTrustedApplicationCreateFromPath(NULL, &broker);
    if (status == errSecSuccess) status = SecTrustedApplicationCreateFromPath(helperPath.fileSystemRepresentation, &helper);
    if (status == errSecSuccess) {
        SecStaticCodeRef helperCode = NULL;
        SecRequirementRef requirement = NULL;
        status = SecStaticCodeCreateWithPath((__bridge CFURLRef)helperURL, kSecCSDefaultFlags, &helperCode);
        if (status == errSecSuccess) status = SecCodeCopyDesignatedRequirement(helperCode, kSecCSDefaultFlags, &requirement);
        if (status == errSecSuccess) status = SecRequirementCopyData(requirement, kSecCSDefaultFlags, &identity);
        if (requirement) CFRelease(requirement);
        if (helperCode) CFRelease(helperCode);
    }
    if (status == errSecSuccess) {
        NSArray *trusted = @[(__bridge id)broker, (__bridge id)helper];
        status = SecAccessCreate(CFSTR("Codex Quota Bar sign-in"), (__bridge CFArrayRef)trusted, &access);
    }
    if (status == errSecSuccess) {
        // An empty AuthDotJson means signed out. Codex updates this same entry
        // after browser login, preserving its access policy and both identities.
        NSData *emptyAccount = [@"{\"OPENAI_API_KEY\":null}" dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *entry = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: service,
            (__bridge id)kSecAttrAccount: account,
            (__bridge id)kSecAttrLabel: @"Codex Quota Bar sign-in",
            (__bridge id)kSecAttrGeneric: (__bridge id)identity,
            (__bridge id)kSecAttrAccess: (__bridge id)access,
            (__bridge id)kSecUseKeychain: (__bridge id)keychain,
            (__bridge id)kSecValueData: emptyAccount
        };
        status = SecItemAdd((__bridge CFDictionaryRef)entry, NULL);
    }
    if (access) CFRelease(access);
    if (identity) CFRelease(identity);
    if (broker) CFRelease(broker);
    if (helper) CFRelease(helper);
    CFRelease(keychain);
    if (status == errSecSuccess) return CredentialStoreSignedOut;
    if (status == errSecInteractionNotAllowed || status == errSecAuthFailed) return CredentialStoreKeychainLocked;
    // A concurrent create fails closed; retry will check the existing entry.
    return CredentialStoreStorageUnavailable;
}

#if QUOTA_DEBUG
extern int RunCredentialStoreTests(NSString *helper);
#endif

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return CredentialStoreStorageUnavailable;
        NSString *account = [NSString stringWithUTF8String:argv[1]];
        NSString *executable = [NSString stringWithUTF8String:argv[0]];
        NSString *helper = [executable.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"CodexQuotaBarAccountHelper"];
#if QUOTA_DEBUG
        if ([account isEqualToString:@"--self-test"]) return RunCredentialStoreTests(helper);
#endif
        if (![account hasPrefix:@"cli|"] || account.length != 20) return CredentialStoreStorageUnavailable;
        return CredentialStorePrepare(@"Codex Auth", account, helper);
    }
}
