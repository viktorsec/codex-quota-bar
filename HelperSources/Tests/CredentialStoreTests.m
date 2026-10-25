#import "../CredentialStore.h"

#if QUOTA_DEBUG
// Isolated fixtures only: this service never contains an actual login.
int RunCredentialStoreTests(NSString *helper) {
    NSString *service = [@"Use Your Tokens credential test " stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *account = @"cli|0000000000000000";
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: service,
        (__bridge id)kSecAttrAccount: account
    };
    int result = 1;
    if (CredentialStorePrepare(service, account, helper) != CredentialStoreSignedOut) goto cleanup;
    if (CredentialStorePrepare(service, account, helper) != CredentialStoreSignedOut) goto cleanup;
    // Emulate Codex's value-only update and ensure access metadata survives.
    {
        NSData *value = [NSJSONSerialization dataWithJSONObject:@{@"tokens": @{@"access_token": @"x"}} options:0 error:NULL];
        if (SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData: value}) != errSecSuccess) goto cleanup;
        if (CredentialStorePrepare(service, account, helper) != CredentialStoreReady) goto cleanup;
    }
    // A saved signing requirement for a different helper must trigger re-login.
    {
        SecRequirementRef wrong = NULL;
        CFDataRef encoded = NULL;
        OSStatus status = SecRequirementCreateWithString(CFSTR("identifier \"invalid.test.helper\""), kSecCSDefaultFlags, &wrong);
        if (status == errSecSuccess) status = SecRequirementCopyData(wrong, kSecCSDefaultFlags, &encoded);
        if (status == errSecSuccess) status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{(__bridge id)kSecAttrGeneric: (__bridge id)encoded});
        if (encoded) CFRelease(encoded);
        if (wrong) CFRelease(wrong);
        if (status != errSecSuccess || CredentialStorePrepare(service, account, helper) != CredentialStoreSignInRequired) goto cleanup;
    }
    // A real denied-read ACL must also return without presenting system UI.
    if (SecItemDelete((__bridge CFDictionaryRef)query) != errSecSuccess) goto cleanup;
    {
        SecTrustedApplicationRef helperOnly = NULL;
        SecAccessRef restricted = NULL;
        OSStatus status = SecTrustedApplicationCreateFromPath(helper.fileSystemRepresentation, &helperOnly);
        if (status == errSecSuccess) status = SecAccessCreate(CFSTR("Use Your Tokens denied-access test"), (__bridge CFArrayRef)@[(__bridge id)helperOnly], &restricted);
        if (status == errSecSuccess) {
            NSMutableDictionary *entry = [query mutableCopy];
            entry[(__bridge id)kSecAttrAccess] = (__bridge id)restricted;
            entry[(__bridge id)kSecValueData] = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
            status = SecItemAdd((__bridge CFDictionaryRef)entry, NULL);
        }
        if (restricted) CFRelease(restricted);
        if (helperOnly) CFRelease(helperOnly);
        if (status != errSecSuccess || CredentialStorePrepare(service, account, helper) != CredentialStoreSignInRequired) goto cleanup;
    }
    result = 0;
cleanup:
    // Delete only this randomly named fixture; never touch a user credential.
    // Use the same legacy deletion API as the upstream keyring backend; the
    // SecItem bridge can reject owner edits on a restricted file-Keychain ACL.
    {
        SecKeychainItemRef fixture = NULL;
        OSStatus status = SecKeychainFindGenericPassword(NULL, (UInt32)[service lengthOfBytesUsingEncoding:NSUTF8StringEncoding], service.UTF8String, (UInt32)[account lengthOfBytesUsingEncoding:NSUTF8StringEncoding], account.UTF8String, NULL, NULL, &fixture);
        if (status == errSecSuccess) status = SecKeychainItemDelete(fixture);
        if (fixture) CFRelease(fixture);
        if (status != errSecSuccess && status != errSecItemNotFound) result = 2;
    }
    return result;
}
#endif
