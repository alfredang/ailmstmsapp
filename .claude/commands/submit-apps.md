---
description: Ship a mobile app update to production on both stores — check the backend is live, test, build, submit the iOS app to App Store Connect and the Android app to Google Play (production), then /github-push the iOS and Android repos.
argument-hint: "[app folder names, e.g. ailmstmsapp tertiarycoursesapp] (default: this project's app)"
---

# /submit-apps — iOS + Android to production, then push

## This project: TIA TMS

| | iOS | Android |
|---|---|---|
| Folder | `~/projects/tertiary/mobile/iOS/ailmstmsapp` | `~/projects/tertiary/mobile/Android/ailmstmsapp` |
| App id | `com.tertiaryinfotech.ailmstms` | `com.tertiaryinfotech.ailmstms` |
| Repo | github.com/alfredang/ailmstmsapp | github.com/alfredang/ailmstms_android |

Backend: ai-lms-tms (`~/projects/tertiary/ai-lms-tms`, the one checkout); production `https://lms-tms.tertiaryinfotech.com/api/mobile/*`. Also per AGENTS.md: test reminder timing, cancellation/assignment filtering, OTP replay/attempt limits, and both iPhone and iPad views before submission. Admin in the app = Google admin sign-in, allow-listed in `lib/mobileGoogleSignIn.ts`.

Ship the named apps (default: the app of the current project) to **App Store Connect (App Review)**
and **Google Play (production track)**, then push both repos with `/github-push`. The user asked for
this to run end to end without stopping for confirmation; stop only on a failed check below.

Apps live in pairs with the same folder name:
`~/projects/tertiary/mobile/iOS/<app>` (SwiftUI, XcodeGen) and `~/projects/tertiary/mobile/Android/<app>`
(Kotlin, Gradle). A project-level copy of this command may name its pair and backend.

Arguments: $ARGUMENTS

## 1. Preflight (blocking)

For each app pair:
1. **Identity.** Read the bundle id from `project.yml` and the `applicationId` from
   `app/build.gradle.kts`; check them against the project's AGENTS.md / README. The submission must go
   to that app and nowhere else.
2. **Backend live.** If the change needs server work (ai-lms-tms for TIA TMS; ai-mms `/mobileapi` for
   TC LMS SG/MY/GH), confirm it is pushed and deployed: hit the new or changed endpoint on production
   and expect 401 (route exists, needs a session), not 404. Don't submit an app whose server isn't live.
3. **Versions.** iOS: bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` when the live version is
   released, or a new version is wanted), then `xcodegen generate`. Android: `versionCode` must be above
   every code on Play; bump `versionName` to match the iOS marketing version.
4. **Release notes.** The top `CHANGELOG.md` entry names this version and says what changed for users
   (no emoji, which App Store What's New rejects).
5. **Uncommitted work.** List `git status` in both repos. Everything in the working tree ships, so name
   anything you did not write in the report.

## 2. Test (blocking)

- iOS: unit tests, then UI tests on an iPhone **and** an iPad simulator (the project's own simulators,
  booted by name).
- Android: `./gradlew :app:testDebugUnitTest` and `./gradlew :app:bundleRelease` (signed with the
  project's upload keystore).
- A failing test stops the release for that app. Fix it, or report it and continue with the other app.
- If an iPhone is wired (`xcrun devicectl list devices`, "available (paired)"), install the build on it
  for the user (`xcodebuild … -destination id=<udid> build`, then `xcrun devicectl device install app`).

## 3. iOS → App Store Connect

Follow the `asc-api-submit` skill (load it):
- `set -a; source .env; set +a`, then `python3 ~/.claude/skills/asc-api-submit/scripts/submit_for_review.py --dry-run`;
  check the `app:` line.
- Archive, export with `ExportOptions.plist`, upload with `xcrun altool` (API key from `.env`).
- If the previous version is still `WAITING_FOR_REVIEW`, replace it as the skill says. If it is
  `IN_REVIEW`, use the skill's `submit_next_version.py` in the background.
- Submit with `--version <v> --build <n>` and report only what Apple returns (`WAITING_FOR_REVIEW`).

## 4. Android → Google Play production

Follow the `android-app-submission` skill (load it):
- Corporate account only (`sales@tertiarycourses.com.sg`, developer 6132721113732535566). Prove
  ownership as the skill says before uploading.
- Use the project's release script when there is one (`scripts/play_release.py --track production
  --dry-run`, then without `--dry-run`); otherwise the Publisher API flow in the skill.
- Read the production track back and report the versionCode and status Google returns.

## 5. Push both repos

Only after both submissions return success, run `/github-push` in the iOS repo and then in the Android
repo (commit message names the version and the change). Never push secrets, `.env`, keystores or
`*.p8` keys. If a repo has no remote, say so instead of creating one.

## 6. Report

One table per app: platform, version/build, store state from Apple/Google, commit pushed. List anything
skipped and why. Then record a lesson in the relevant skill's `reference/lessons_log.md` if a step
failed in a new way.
