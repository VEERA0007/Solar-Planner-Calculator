# Solar Planner & Calculator

Flutter app (Android, iOS, Windows, web): live sun dashboard, rooftop solar estimator with USC search and PDF quotes, appliance load analysis and solar analysis.

- Version name is read from `VERSION` (0.0.7) on every build; the build number is the GitHub run number and increases automatically.
- Every push to `main` runs analysis and tests, builds all platforms and publishes a GitHub Release (`build-N`).
- The app checks the latest Release when it opens and offers to download the update (needs the Releases page to be public).
- Android builds are signed with `signing/debug.keystore` so each build installs over the previous one.

Native platform folders are generated in CI by `tools/scaffold.sh`.
