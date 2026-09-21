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

### Jev-assisted driver

`Driver/` builds the separate macOS 26 `axe-driver` executable. It keeps TypeSafe and `TYPESAFE_API_KEY` out of the ordinary macOS 14-compatible `axe` executable.

```bash
# Build AXe's simulator dependencies and an optimized driver.
make setup-axe-driver

# Run a bounded goal. The caller supplies exact text and independent evidence.
printf '%s\n' '{
  "simulatorUDID": "<UDID>",
  "instruction": "Create and save an event titled Cameron Birthday",
  "text": "Cameron Birthday",
  "maxSteps": 8,
  "requirements": [
    "An event titled Cameron Birthday is visibly present"
  ],
  "expectLabels": ["Cameron Birthday"]
}' | Driver/.build/release/axe-driver

# Or pass the goal directly without constructing JSON.
Driver/.build/release/axe-driver \
  --udid "<UDID>" \
  --goal "Create and save an event titled Cameron Birthday" \
  --text "Cameron Birthday" \
  --max-steps 8 \
  --requirement "An event titled Cameron Birthday is visibly present"
```

The driver sends compact accessibility labels and values to TypeSafe's API. Use fixture or test-account data. It asks Jev to select one offered operation and one compatible visible target per step; AXe owns coordinates, freshness checks, HID input, budgets, and final verification. `completed` is returned only after a fresh UI observation satisfies every configured requirement and deterministic expectation. `done_unverified`, `uncertain`, `stale`, and `uncertain_write` return control without retrying a mutation.

Goal runs write progress to standard error for every observation, Jev selection, action outcome, and terminal status. The final machine-readable result remains the only output on standard output, so redirect or pipe it independently. Set `AXE_DRIVER_LOG=0` to suppress progress logging.

Set `observeOnly: true` to inspect actionable rows without calling Jev. `minimumConfidence` defaults to `0.5` for action selection. Visible target selection requires at least `0.5` selected probability; `minimumProbability` can raise the probability gate for both. Every selected target is then revalidated against a fresh accessibility snapshot before input. Pin `model` for repeatable benchmarks or omit it to use `jev-latest`.

Full documentation is available at [axe-cli.com/docs](https://axe-cli.com/docs).

## Disclaimer

AXe is an independent open-source iOS Simulator automation project and is not affiliated with, endorsed by, or associated with Deque Systems or its axe® accessibility products.

## Licence

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Third-party licensing notices, including Meta's IDB MIT attribution, are in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES).
