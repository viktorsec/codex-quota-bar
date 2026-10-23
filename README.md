# Codex Quota Bar

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

The helper uses a dedicated `CODEX_HOME` under the app container's Application
Support directory (`CodexQuotaBar/Codex`). It uses Codex's `keyring` credential
storage mode, with no plaintext credential fallback. It does not read, import,
or sign out the user's regular CLI/IDE session. Authentication tokens and login
URLs are never written to our app logs.

The app permits outgoing network requests and an incoming connection for Codex's
local OAuth callback listener. The helper inherits these permissions. App Sandbox
and Xcode's build-script sandbox remain enabled.

## Validation

The Debug app includes an opt-in packaging check:

```sh
/path/to/CodexQuotaBar.app/Contents/MacOS/CodexQuotaBar --smoke-test
```

It checks container execution, initializes the bundled helper, reads account
state, starts and cancels browser authentication without opening a browser, and
shuts down the helper. It prints only pass/fail messages. Full authentication,
Keychain persistence, and live quota retrieval require completing browser sign-in.

Validated locally: signed sandboxed Debug build; helper smoke check; user-completed
browser sign-in and live quota display. Clean-machine installation, relaunch
persistence, and App Store review have not yet been validated.

Pinned upstream release and checksums: `Vendor/Codex/VERSION`.

## Helper source and licence

The server is OpenAI's standalone `codex-app-server` executable from the public
[Codex 0.164.0 release](https://github.com/openai/codex/releases/tag/rust-v0.164.0).

The upstream project is licensed under [Apache License 2.0](https://github.com/openai/codex/blob/rust-v0.164.0/LICENSE). The build includes the unedited upstream `LICENSE` and `NOTICE` in
`Contents/Resources/Codex`.
