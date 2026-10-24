#import <Foundation/Foundation.h>
#import <Security/Security.h>

// Process exit-status contract mirrored by CredentialAccess.ExitStatus.
typedef NS_ENUM(int, CredentialStoreStatus) {
    CredentialStoreReady = 0,
    CredentialStoreSignedOut = 10,
    CredentialStoreSignInRequired = 20,
    CredentialStoreKeychainLocked = 21,
    CredentialStoreStorageUnavailable = 22
};

CredentialStoreStatus CredentialStorePrepare(NSString *service, NSString *account, NSString *helperPath);
