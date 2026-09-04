# Dipstick — Milestone 7 Report: CI pipeline

**Status:** Green on PR #7. Every push and PR runs `gofmt` / `go vet` /
`golangci-lint` / `go test -race` for both Go services and compiles the iOS app +
test bundles. Pushes to `main` also build and push Docker images to GHCR.

---

## Concepts Introduced This Milestone

**GitHub Actions workflows**
A workflow is a YAML file in `.github/workflows/`. It has `on:` triggers
(`pull_request`, `push`, with optional `paths:` filters), and `jobs:` that each
run on a fresh VM (`runs-on:`). Steps in a job are either `uses:` (a prebuilt
action) or `run:` (shell). Jobs run in parallel unless one `needs:` another.

**Matrix jobs**
`strategy.matrix.service: [vehicle-service, activity-service]` runs the same job
once per value, in parallel. One job definition, both services checked, and each
shows up as its own status check on the PR.

**Path filters gate which workflow runs**
`backend.yml` only triggers on changes under `backend/**` (plus its own file and
`.golangci.yml`); `ios.yml` only on `ios/**`. A backend-only PR doesn't spin up a
macOS runner, and vice versa.

**`GITHUB_TOKEN` and GHCR**
Every workflow run gets an automatic `secrets.GITHUB_TOKEN`. With
`permissions: packages: write` on the job, that token can push images to
`ghcr.io/<owner>/...` — no personal access token or repo secret to set up. The
image is owned by the repo.

**Image tagging with `docker/metadata-action`**
Produces tag/label strings from the git context: `latest` plus
`sha-<full-commit>`, so every `main` build is both "the current one" and
permanently addressable by commit.

**Build caching**
`actions/setup-go` caches the module download and build cache keyed on `go.sum`.
`docker/build-push-action` with `cache-from/to: type=gha` caches Docker layers in
the Actions cache, so unchanged layers aren't rebuilt.

---

## File Reference

| File | Role |
|---|---|
| `.github/workflows/backend.yml` | `test` (matrix): gofmt check, vet, build, `go test -race`. `lint` (matrix): golangci-lint. `images` (matrix, `needs: [test, lint]`, `if:` push-to-main only): login GHCR → build → push `latest` + `sha`. |
| `.github/workflows/ios.yml` | `build`: macOS runner, `xcodebuild build-for-testing` against the generic simulator SDK. |
| `.golangci.yml` | golangci-lint v2 config: standard linters + `std-error-handling` exclusions + an errcheck exception for `(*sql.Tx).Rollback`, so idiomatic code passes. |
| `scripts/check.sh` | Runs the same checks (fmt, vet, lint, test) locally for both services. |
| `README.md` | Architecture sketch, local dev commands, CI badges. |

---

## Design Decisions Made Beyond the Spec

- **Two workflows, not one.** The architecture doc's CI is "`go test` for both
  services → build images → push". iOS CI is an addition; keeping it in its own
  workflow means a flaky macOS runner never blocks a backend change, and the
  path filters keep each PR's checks relevant.
- **`golangci-lint` is in the pipeline.** Not in the doc, but it's standard on
  real Go projects and the point of this project is job-relevant reps. The config
  is conservative (standard linter set) and tuned so the existing idiomatic code
  (`defer rows.Close()`, `defer tx.Rollback()`) passes without `//nolint`
  comments.
- **iOS CI is build-only.** GitHub's macOS runners don't ship an iOS simulator
  runtime, and `xcodebuild -downloadPlatform iOS` didn't reliably produce a
  usable device in ~8s. `build-for-testing` compiles the app *and* both test
  bundles against the simulator SDK — it catches every compile error with no
  runtime needed. Actually *running* the tests in CI (download a runtime, create
  a device) is a tracked follow-up; the tests run locally and pass.
- **Images are pushed only from `main`, only after test + lint pass** (`needs:` +
  `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`). PRs
  build nothing to a registry.
- **`sha-<full>` tag, not `sha-<short>`** — unambiguous and matches what a deploy
  step would pin to.
- **The "deploy" half of CD is Milestone 8.** This milestone stops at "images in
  the registry".

---

## Verification (Actually Run)

On PR #7 (three iterations to get the runner specifics right):

```
test (vehicle-service)      pass   ~19s
test (activity-service)     pass   ~20s
lint (vehicle-service)      pass   ~30s
lint (activity-service)     pass   ~28s
build (app + tests)         pass   ~41s
build & push image (...)    skipped   (correct — PRs don't publish)
```

Locally, `scripts/check.sh` runs the same fmt/vet/lint/test for both services and
passes.

The `images` job (build + push to GHCR) only runs on a push to `main`, so it'll
first execute when this PR merges — the config is the standard
`docker/login-action` + `metadata-action` + `build-push-action` flow.

---

## Open Items for Milestone 8+

- **Milestone 8: deploy.** Free host, chosen for real-role learning — leaning
  Oracle Cloud Always Free VM + Docker Compose + Caddy (automatic HTTPS) + real
  DNS; k3s as a stretch. Once deployed, add a deploy step here (SSH + `docker
  compose pull && up`, or `kubectl set image`), point the iOS app's default URL
  at the HTTPS endpoint, and the app works anywhere.
- **Run iOS unit tests in CI** — download a simulator runtime and create a
  device, or cache the runtime.
- **Milestone 9: polish** — `GET /vehicles/{id}/stats` + MPG trend chart; the
  vehicle-list at-a-glance info; a `/due` dashboard.
