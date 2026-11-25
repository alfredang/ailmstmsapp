# Current update — TIA TMS 1.1 build 12 (25 November 2026): admin course runs, Switch role, more admins

- **State: version 1.1, build 12, WAITING_FOR_REVIEW** (submission e9e74414-93cd-4a07-bcee-13c717d43273). Build 11's waiting submission 20f0b633 was canceled after build 12 was VALID; 1.1 has never been released, so the same version took the new build.
- New: Admin Courses tab shows each course's runs with Confirmed / Pending / Cancelled counts and a list of every run (trainer shown for confirmed runs); Switch role for an email with several roles.
- Server: AI-LMS-TMS 458c7072: `/api/mobile/staff?view=runs`, run counts on `view=courses`, and the admin sign-in allow-list now built in (angch, danny, deepa, angss, tansc @tertiaryinfotech.com).
- Tests: 19 unit tests; UI tests passed on iPad Pro 13 and an iPhone 17 Pro Max simulator (TEST SUCCEEDED).

# Current update — TIA TMS 1.1 build 8 (21 November 2026): class quizzes from a QR code

- **State: version 1.1, build 8, WAITING_FOR_REVIEW** (submission adc09c8b-84e6-4ef2-9236-225adc5f9e52, submitted 2026-11-20T17:24:43Z; read back in apple-release-readback-b8.json). Release type: after approval.
- Version 1.0 (build 7) was still WAITING_FOR_REVIEW and had never been released, so its submission 65a753b2 was canceled and the same version record was renamed 1.0 -> 1.1 with build 8 attached (build8-prepare.txt, build8-submit.txt). The place in the review queue restarted.
- Build 8: delivery 3746da11-ffa2-4749-bdf0-14e1f8d8c85c, VALID (build8-upload.txt; `altool --validate-app` passed first).
- New: quiz QR code link `https://lms-tms.tertiaryinfotech.com/quiz/<courseId>/<quizId>` opens a native quiz (App/Quiz.swift) through a universal link. Entitlement `applinks:lms-tms.tertiaryinfotech.com` in both configurations.
- Apple developer portal, through the API: Associated Domains capability enabled on the App ID 336A245TLP (apple-associated-domains-capability.json). The App Store profile "Tertiary Learning App Store" became INVALID, so it was deleted and recreated with the same name and certificates (new id W8GQ5W63AN, apple-profile-regenerated.json). The exported IPA carries the associated-domains entitlement.
- Listing through the API: description gained a CLASS QUIZZES section; review notes explain the sample quiz ("Class quiz" > "Try the sample quiz") and the universal link. "What's New" was refused (409, not editable): the app has no released version yet, so the field does not exist. Release note for the record: "Scan a quiz QR code to take class quizzes in the app."
- Tests on the final code: iPhone 17 Pro Max and iPad Pro 13, 14 unit + 3 UI each, all passed (iphone-tests-b8.txt, ipad-tests-b8.txt).
- Universal link: the server's AASA went live during the release (build8-evidence/aasa-live.json). `xcrun simctl openurl` opened the app on the quiz sign-in screen with a Debug build using `?mode=developer` (reads the AASA from the site directly; build8-evidence/universal-link-simctl-openurl.png). With the normal entitlement the simulator still opened Safari, because Apple's AASA CDN answered 404 to the simulator at that time (it answered 200 to curl). Not verified on a physical device.
- Not verified: a live quiz fetch and submit with a real learner account (no test account in this repo). The live requests are covered by a stubbed-portal unit test built from the server routes.
- App Privacy label (website only): quiz answers are "Other User Content", the same category as assessment files and course feedback. Confirm that category is on the published label.

# Current update — TIA TMS, build 7 (19 November 2026)

- App renamed **TIA TMS**; version 1.0 build 7 uploaded (delivery 9f732393-2cc0-44cd-abcd-7235c07cee89), VALID and attached to version 1.0.
- Listing updated through the API: name, subtitle, description, keywords, review notes, 10 iPhone 6.9" and 10 iPad 13" screenshots.
- The rejected submission d202e84f was canceled; a new draft submission 65a753b2 exists.
- **Not submitted.** Adding the version to the submission returns 409: two unfulfilled compliance requirements (`SECURITYASF395E` and `AIGENERATEFD1DE`). They must be completed in the App Store Connect website, then run `python3 ~/.claude/skills/asc-api-submit/scripts/submit_for_review.py --version 1.0 --build 7`.
- The App Privacy label has not been updated for the new data (phone number, files a learner submits, camera for QR). It is website-only.
- Backend routes deployed: AI-LMS-TMS main 8c19debd (live check: new routes return 401 unauthenticated, health connected).
- Tests: iPhone 9 unit + 2 UI pass; iPad 8 unit + 2 UI pass (before the fixture test was added).

# Current update — company logo, build 5

The user-approved premium blue T company logo with TIA LMS lettering is now submitted in version 1.0 build 5. Apple build c56e01fd-152d-4587-88db-ef35562c32ba is VALID, attached and WAITING_FOR_REVIEW. The masked App Store icon was visually verified with Playwright and matches the approved artwork. The Apps overview remains black; this visible issue is unresolved. See company-icon-validation.json, company-icon-upload.txt and company-apple-icons.json. Builds 3 and 4 are superseded. Native behavior is unchanged from the tested build 3.

## Prior validation record

# Release status

App: **Tertiary LMS** · `com.tertiaryinfotech.ailmstms` · version **1.0**, build **3**.

## Apple submission

- App 6809272168; current submission 26135d42-f522-4836-abcc-2e4c605aaf7d is **WAITING_FOR_REVIEW**, verified directly through Apple on 7 September 2026.
- Valid build 3 (5b93d819-535b-4cab-9e37-c69aac8b6e61) is attached to version 1.0. App name and native display name are Tertiary LMS.
- The original build 1 submission was canceled and build 1 expired. Build 2 was an intermediate icon correction; build 3 includes the rename.
- The source icon and compiled iPhone/iPad icons contain the intended teal and white graduation cap. Apple’s submitted build 3 Included Assets icon was visually verified as correct.
- **Unresolved visible difference:** the ASC Apps overview still renders a black icon and references a Placeholder.mill asset. The correct submitted build asset does not establish that the overview card is fixed. No cache or propagation explanation is assumed.
- Privacy disclosures published, Education category, 4+ rating, content-rights declaration, 12 complete screenshots, free pricing and 175 regions verified.
- Evidence: apple-submission.json, apple-upload.txt, icon-resubmission-audit.json, icon-fix.md.

## Validation and deployment

- Fresh iPhone and iPad tests passed: three model tests and learner/trainer navigation on each, including the Tertiary LMS title assertion. See iphone-rename-tests.txt and ipad-rename-tests.txt.
- Signed archive: build/TertiaryLMS.xcarchive. IPA: build/export-lms/TertiaryLearning.ipa. The internal executable/scheme name remains TertiaryLearning; public branding is Tertiary LMS.
- Backend branding commit 738c7a5a6ab6835ee8050b7ce20449a35ab5e86b deployed successfully through job nrpif6qm0dxhcer2t1u3rlm7. Running container image matches this SHA.
- All six live public pages match repository bytes. Health reports database connected; unauthenticated learner/Android endpoints return 401 and malformed OTP input returns 400. See live-readback.json.
- Prior backend integration tests covered ownership, role isolation, trainer assignment, cancellation, OTP replay, device registration, scheduler access and deletion. Prior API guard checks passed (587 checks). The branding change preserves those behaviors.
- Production APNs credentials and 3-day/1-day reminder scheduler were enabled and checked in the preceding release. Physical-device push delivery and real-account OTP receipt remain unverified.
- User, Codex and Claude iOS skills updated with icon, version, rename and submission verification lessons; imports verified in skills-audit.json.

Apple approval is pending. The updated Developer Program agreement remains for account-holder review; it was not accepted by the agent and did not block this submission. Production configuration skips TypeScript validation; a full type-check pass is not claimed.

## 20 Nov 2026 — iOS 1.0 (7) submitted

- State: WAITING_FOR_REVIEW (submission 65a753b2-f4ec-405f-bce0-5d82de57c9ea).
- App Compliance (website only): Security Assessment = No, AI Generated or Synthetic Content = No (China mainland). Both Active.
- App Privacy: Phone Number added (App Functionality, linked, no tracking) and published.
- Previous rejection (submission d202e84f, Sep 2026): Guideline 4.3(a) Design - Spam. Review notes now explain how TIA TMS differs from the TC LMS SG/MY/GH apps.
