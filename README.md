# Use Your Tokens

A macOS menu bar app showing remaining quota and reset times for Codex account.

## Build and run

1. Use Xcode 27.
2. Prepare the pinned helper once from the repository root:

   ```sh
   bash Scripts/prepare-codex-helper.sh
   ```

The helper is downloaded only during development. The build copies it into
`Contents/Helpers`, signs it with sandbox inheritance, and includes its license,
notice, and version in the app's resources. End users do not need an installed
Codex CLI, Homebrew, Node.js, or another Codex app. Binaries are ignored by Git;
the preparation script verifies the pinned release archive's SHA-256 checksum.

## Authentication and isolation

The app uses the documented [Codex App Server protocol](https://developers.openai.com/codex/app-server/)
over stdin/stdout. It calls only initialization and account/login/quota methods;
it does not start agent threads, run tools, or make model requests.

The account helper is named `UseYourTokensAccountHelper`, with signing identifier
`$(PRODUCT_BUNDLE_IDENTIFIER).AccountHelper`. The app-owned credential broker is
`UseYourTokensCredentialStore`, with identifier
`$(PRODUCT_BUNDLE_IDENTIFIER).CredentialStore`. Both are signed by Xcode with the
app's identity and inherit its sandbox. These identifiers remain stable across
builds and upstream helper versions.

Sign-in persists in the login Keychain using Codex's `keyring` mode and direct
backend (`features.secret_auth_storage=false`). The broker creates each entry
with an explicit access policy trusting both helpers. It disables Keychain UI in
its own process and checks access before starting the account helper and before
account operations. No token data is sent back to the Swift app or logged.

The broker also records and validates the account helper's designated signing
requirement. Unreadable credentials or a changed helper identity select a fresh
credential slot and request browser sign-in; old items are not read with a prompt
or deleted. A locked Keychain produces a retry message and preserves the slot.
The app deliberately does not import credentials from the earlier development
prototype or from a regular Codex CLI/IDE installation.

Each slot has its own `CODEX_HOME` under the app container's Application Support
directory (`UseYourTokens/Authentication/<UUID>`). UserDefaults stores only the
non-secret slot UUID. Authentication tokens stay in Keychain, never in auth.json
or UserDefaults. Refresh tokens allow silent sign-in after normal relaunches.
The broker integration is specific to the pinned upstream storage schema and
must be rechecked when updating Codex.

The app permits outgoing network requests and an incoming connection for Codex's
local OAuth callback listener. The helper inherits these permissions. App Sandbox
and Xcode's build-script sandbox remain enabled.

## Validation

The Debug app includes an opt-in packaging check:

```sh
"/path/to/Use Your Tokens.app/Contents/MacOS/Use Your Tokens" --smoke-test
```

It checks container execution, initializes the bundled helper, reads account
state, starts and cancels browser authentication without opening a browser, and
shuts down the helper. It prints only pass/fail messages.

Additional Debug launch arguments provide regression checks:

- `--check-notifications`: checks notification preferences, permission handling,
  reset filtering, message content, and test delivery using a fake notification
  client, without requesting system permission or sending real notifications.
- `--credential-self-test`: creates disposable, randomly named test entries;
  checks reuse, value-only updates, a changed helper identity, and denied access
  without UI; then deletes only those test entries.
- `--check-saved-sign-in`: restores an existing browser login in a fresh process
  and retrieves live quota without starting another browser login. It reports
  only pass/fail, never account details or tokens.
- `--check-model-state`: verifies connection, saved-account restoration, refresh,
  shutdown, and cancelled connection states using the app's saved login.

Credential fixtures live in `HelperSources/Tests/CredentialStoreTests.m`, separate
from the production Keychain implementation. They compile only in Debug builds.
Their named exit-status contract is declared in `HelperSources/CredentialStore.h`
and mirrored by `CredentialAccess.ExitStatus` in Swift.

Pinned upstream release and checksums: `Vendor/Codex/VERSION`.

## Helper source and licence

The server is OpenAI's standalone `codex-app-server` executable from the public
[Codex 0.164.0 release](https://github.com/openai/codex/releases/tag/rust-v0.164.0).

The upstream project is licensed under [Apache License 2.0](https://github.com/openai/codex/blob/rust-v0.164.0/LICENSE). The build includes the unedited upstream `LICENSE` and `NOTICE` in
`Contents/Resources/Codex`.
