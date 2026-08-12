# Pachyderm

A beautiful Mastodon client for iOS, written in SwiftUI.

## Requirements

- iOS 18.0+
- Xcode 27 on macOS 15.5 or later

No third-party dependencies — the app uses Swift's own `Observation`, `URLSession`
and Keychain APIs directly.

## Building

Open the project in Xcode, change the bundle ID to your own, and then change the team to your own. It is essential to do these steps in exact order. After doing them, you can now build and run the app.

To build an unsigned `.ipa` from the command line:

```sh
./ipabuild.sh            # Release
./ipabuild.sh --debug    # Debug, unstripped
./ipabuild.sh --clean    # wipe the build folder first
./ipabuild.sh --tipa     # package as .tipa instead of .ipa
```

## Generative AI Usage Disclosure

LLMs such as Anthropic's Claude Opus 5 were extensively used to rewrite large portions of the app's codebase. Commits containing AI-generated code will include an `Assisted-by` trailer with the name of the model used.
