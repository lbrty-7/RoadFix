# CI pipeline

The pipeline is defined in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). It runs on GitHub Actions on every pull request, on every push to `main`, and on demand from the **Actions** tab (**Run workflow**).

If any step fails, the run fails and the pull request shows a red ✗. Once `main` is protected (#11), a pull request with a failing run can't be merged.

## Stages

| # | Step | What it does |
|---|---|---|
| 1 | **Check out the code** | Downloads the commit being tested. |
| 2 | **Check that no private config is committed** | [`ci/check-no-secrets.sh`](../ci/check-no-secrets.sh) fails the run if `GoogleService-Info.plist`, `Sentry-Info.plist` or a `.env` file is tracked by git. |
| 3 | **Select Xcode 27.2** | Uses the same Xcode version the project is developed with, on GitHub's `xcode-27` macOS image. |
| 4 | **Restore Swift packages from cache** | Reuses Firebase and Sentry from earlier runs. The cache key is `Package.resolved`, so a dependency change downloads them again. |
| 5 | **Write placeholder Firebase config** | [`ci/write-test-config.sh`](../ci/write-test-config.sh) writes a `GoogleService-Info.plist` with fake values so the app can start for the tests. |
| 6 | **Resolve Swift packages** | Downloads the exact package versions pinned in `Package.resolved`. Skipped when the cache already matches them. |
| 7 | **Pick and boot an iPhone simulator** | Chooses a common iPhone on the newest released (non-beta) iOS runtime and starts booting it, so it boots while the app compiles. |
| 8 | **Build** | Compiles the app and the test target for the simulator (`build-for-testing`). A compile error fails the run here. |
| 9 | **Wait for the simulator to finish booting** | Usually already done by the time the build ends. |
| 10 | **Run tests** | Runs every unit test (`test-without-building`), one at a time on that simulator. One failing test fails the run. |
| 11 | **Write test summary** | Adds a table of total, passed, failed and skipped tests (and the names of failed ones) to the run's summary page. Runs even if the tests failed. |
| 12 | **Upload test results** | Saves `TestResults.xcresult` and the build and test logs as the `test-results` artifact for 14 days. Runs even if the tests failed. |

## Speed

The tests themselves take about a second. Most of the run is setup:

- **Swift packages:** cached between runs (key: `Package.resolved`), so they're downloaded only when a dependency changes.
- **Build:** Firebase compiles from source, about two minutes.
- **Simulator:** a cold boot takes minutes, so it starts before the build and runs alongside it. Tests run without parallel testing, which would boot extra simulator clones for no gain on a suite this size. Beta runtimes are skipped because they boot slower and are less stable.

## Showing the results

- **On a pull request:** the **CI / Build and test (iOS)** check at the bottom shows ✓ or ✗; **Details** opens the run.
- **On the run page:** the summary shows the test table. Each step's log can be expanded.
- **Test results file:** download the `test-results` artifact and open `TestResults.xcresult` in Xcode to see every test, its duration and any failure with its line.

## How it improves security

- **Nothing untested reaches `main`.** Every change is built and tested before it's merged, so a change that breaks the build, the tests or a security check can't slip in.
- **Private config can't be committed by accident.** Step 2 stops the run if the Firebase or Sentry config, or a `.env` file, is added to the public repo.
- **Tests never touch production.** CI uses fake Firebase values and no Sentry DSN, so a test run can't read or write real users' data and sends nothing to Sentry. CI holds no production secrets that could leak.
- **Least privilege.** The workflow's token can only read the repository (`permissions: contents: read`).
- **Pinned dependencies.** Swift packages are installed at the exact versions in `Package.resolved`, and each GitHub Action is pinned to a commit hash, so a changed or compromised tag can't run different code.
- **Reproducible.** The same Xcode version and the same steps run for everyone, so "it works on my machine" problems show up before merge.

## Secrets

The test job needs no secrets. Steps that do need real values, such as uploading debug symbols to Sentry for releases (#9, #13), will read them from GitHub Actions secrets (**Settings → Secrets and variables → Actions**), stored base64-encoded and never printed to the log. Only the repository owner can add or change those secrets.

## Running the same checks locally

```bash
bash ci/check-no-secrets.sh
xcodebuild test -project RoadFix.xcodeproj -scheme RoadFix -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```
