# TestFlight

Open **Actions → TestFlight → Run workflow**, select the **regram-beta** branch,
and select a mode. The default `master` branch retains a discovery-only entry
that fails with instructions to select `regram-beta`; it never builds or uploads.
The beta workflow builds the `//Telegram:Regram`
target with an Apple Distribution identity, includes all six extensions, verifies
the signed IPA, uploads it to App Store Connect, and submits the processed build
to Beta App Review for the **External Testers** group.

The internal **Admins** group receives every build automatically. After a build
is valid, distribution also sends any pending internal invitations. The App Store
Connect app uses Limited Access, so only Admin-role users can see it.

The app's registered bundle ID is `dev.regram.ios`. Its App Store Connect name is
**Regram Messenger**; the installed app keeps the Regram name.

## Workflow modes

- `publish`: build, upload, attach the external group, and submit Beta App Review.
- `build`: validate signing and build the app without uploading it.
- `distribute`: retry external distribution of `build_number` without building or
  uploading again. The app version must match `versions.json`.

Only manual dispatch on `regram-beta` publishes to TestFlight. For a normal new
upload, choose `publish` and leave `build_number` empty. Pushes continue to run
the reference IPA build; GitHub Releases remain a separate manual `master` flow.

The build number starts at `versions.json`'s declared build for a new app. Later
runs select the greater of that number and one above every existing numeric build
or pending upload. All modes share a concurrency group. The version remains the
one declared in `versions.json`.

Update `testflight-notes.txt` before publishing. The notes become the build's
English **What to Test** text. Apple processing and Beta App Review are separate:
an accepted upload or review submission does not mean external testing is live.
If processing exceeds the polling deadline, use `distribute` with the uploaded
build number.

## Private configuration

Store these values as repository **Actions secrets**, never repository variables,
workflow inputs, source literals, or documentation:

| Secret | Purpose |
| --- | --- |
| `REGRAM_BETA_BUILD_CONFIGURATION` | Beta JSON build configuration, including Telegram API credentials and `rg_config` |
| `APPLE_TEAM_ID` | Apple signing team |
| `ASC_APP_ID` | App Store Connect app record |
| `ASC_KEY_ID` | App Store Connect API key identifier |
| `ASC_ISSUER_ID` | App Store Connect API issuer |
| `ASC_KEY_P8_BASE64` | Base64 encoded API private key |
| `DIST_CERT_P12_BASE64` | Base64 encoded distribution certificate and private key |
| `DIST_CERT_PASSWORD` | Password for the distribution certificate archive |

The `ASC_KEY_*` secrets belong to a team API key used only by this workflow, with
the App Manager role. Revoking it in App Store Connect under **Users and Access ›
Integrations › App Store Connect API** stops the workflow without affecting other
apps. To resume, generate a new App Manager key and replace `ASC_KEY_ID`,
`ASC_ISSUER_ID`, and `ASC_KEY_P8_BASE64`.

The workflow maps `REGRAM_BETA_BUILD_CONFIGURATION` to its private input
`REGRAM_BUILD_CONFIGURATION`, preserving Telegram API and Regram configuration.
All builds on this branch use `dev.regram.ios` and `group.dev.regram.ios`, including
the main application and all six extensions. The secret's `telegram_bundle_id`
must be `dev.regram.ios`. The beta branch continues to exclude in-app IPA updates
and signing. This identity has a different data container from older beta builds
that used `com.regram.app`; existing sessions and local data do not transfer
between those identities automatically.

The initial signing setup enables production push notifications,
communication notifications, and `group.dev.regram.ios` for the app and all six
extensions. Siri, iCloud, and the watch app are not enabled in this signing setup.
Restricted notification filtering is included only if Apple grants it in the
notification service's provisioning profile.

Profiles are fetched or created through the API and validated against the bundle,
team, certificate, App Group, expiration, and App Store distribution type.
Development, device-specific, expired, and mismatched profiles fail the build.

Signing identities are masked, and raw signing/build/upload diagnostics are kept
private on the ephemeral runner. The workflow publishes no signed IPA, profile,
certificate, debug symbols, or signed build cache to Actions artifacts or GitHub
Releases. It may restore the existing reference cache but never saves it after
signing. Private inputs and the temporary keychain are removed even after failure.
Apple's signed package necessarily contains its signing identity; it is sent
directly to Apple.

## Validation

```sh
python3 -m unittest discover -s build-system/ci -p 'test_*.py'
actionlint .github/workflows/testflight.yml
bash -n build-system/ci/testflight-build.sh
```
