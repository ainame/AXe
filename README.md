<img src="banner.png" alt="AXe" width="600"/>

AXe is a comprehensive CLI tool for interacting with iOS Simulators using Apple's HID (Human Interface Device) functionality.

[![CI](https://github.com/cameroncooke/AXe/actions/workflows/release.yml/badge.svg)](https://github.com/cameroncooke/AXe/actions/workflows/release.yml)
[![Licence: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Install

```bash
brew tap cameroncooke/axe
brew install axe
```

Or install in one command:

```bash
brew install cameroncooke/axe/axe
```

Verify the CLI:

```bash
axe --help
axe list-simulators
```

## Xcode compatibility

AXe supports Xcode 26 and Xcode 27. Xcode 27 simulator automation uses Device Hub; Simulator.app is not required.

Release artifacts are built once with the Xcode version selected by the release environment and run unchanged with either supported Xcode selected. Compatibility was validated with Xcode 26.5 (build `17F42`) and iOS 26.5 (`23F77`), and with Xcode 27 Beta 3 (build `27A5218g`) and iOS 27 (`24A5380g`).

AXe builds IDB from the immutable fork revision configured in `scripts/build.sh`, based on a verified upstream IDB revision. The build does not apply a local patch queue.

## E2E development

`make e2e` rebuilds the local IDB XCFrameworks, builds AXe, and runs the simulator tests with the Xcode selected by `DEVELOPER_DIR` or `xcode-select`. XcodeGen is required to generate the IDB projects. When Xcode 27 is selected, the runner starts Device Hub, chooses an available iOS 27 iPhone 17 Pro, and boots it with `simctl`.

To validate a release payload unchanged under another supported Xcode, first build the test bundle with that Xcode, then run `AXE_BIN_PATH=/path/to/release/axe ./test-runner.sh --tests-only`. The supplied executable must retain its packaged frameworks beside it.

## Basic usage

```bash
# Find a booted simulator UDID
axe list-simulators
export UDID=<UDID>

# Inspect the current UI
axe describe-ui --udid "$UDID"

# Interact with the simulator
axe tap --label "Continue" --udid "$UDID"
axe type 'Hello world' --udid "$UDID"
axe screenshot --output ./screen.png --udid "$UDID"
```

## Documentation

### Jev-assisted driver (fork)

`Driver/` builds the separate `axe-driver` executable. It requires macOS 26, Swift 6.4, Xcode 27 simulator support, the IDB XCFrameworks built for AXe, and `TYPESAFE_API_KEY`. The ordinary `axe` executable does not load TypeSafe or require its credentials.

```bash
# From the repository root, prepare the binary IDB dependencies once.
./scripts/build.sh setup
./scripts/build.sh frameworks
./scripts/build.sh install
./scripts/build.sh strip
./scripts/build.sh xcframeworks

cd Driver
swift build --product axe-driver
printf '%s\n' '{"simulatorUDID":"<UDID>","instruction":"Tap Continue"}' | swift run axe-driver
```

Select the intended Xcode with `DEVELOPER_DIR` if it is not the active Xcode. The input is one JSON object on standard input. Set `observeOnly: true` to return the current actionable rows without calling Jev. For text entry, include the exact `text` string supplied by the calling agent. `minimumProbability` defaults to `0.65`. The result contains `status`, before and after rows, candidates, the model selection and probabilities, execution details, latency, and token usage. `executed` means input was sent; `executed_unverified` means the follow-up observation failed; `uncertain_write` means input may have been sent. Inspect fresh UI evidence before retrying either uncertain result. The calling agent must confirm the larger task outcome. The driver does not launch apps or decide task goals.

The root package remains at macOS 14 compatibility. `Driver/` is a separate macOS 26 package because the TypeSafe Swift SDK requires macOS 26. During local development, set `TYPESAFE_PACKAGE_DIR` to a checkout of `swift-typesafe`; otherwise SwiftPM resolves its `0.7.0` release.

Full documentation is available at [axe-cli.com/docs](https://axe-cli.com/docs).

## Disclaimer

AXe is an independent open-source iOS Simulator automation project and is not affiliated with, endorsed by, or associated with Deque Systems or its axe® accessibility products.

## Licence

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Third-party licensing notices, including Meta's IDB MIT attribution, are in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
