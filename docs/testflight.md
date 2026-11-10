# Spendie TestFlight release

The iOS display name is Spendie. The configured app bundle ID is `pg.spendie.ios`; keep it aligned with App Store Connect. The target/scheme and backend retain their MoneyTrack technical names.

## Privacy

Account → Privacy is available without signing in and reads a bundled copy of [the shared notice](../server/priv/privacy.json), so it works offline. The server renders the same source at `/privacy` without requiring authentication. Use that path on the configured central HTTPS instance for the App Store Connect privacy-policy URL; deployment identifiers remain in ignored configuration.

[PrivacyInfo.xcprivacy](../ios/MoneyTrack/PrivacyInfo.xcprivacy) declares no tracking, the app-functionality collection of account identifiers, email addresses, financial records, purchase history, user-entered content and operational metadata, and the `CA92.1` UserDefaults reason for app-owned cached rates. It does not claim that connected ledger data stays solely on the device. Apple handles TestFlight diagnostics and feedback under its separate TestFlight privacy terms, linked in the notice.

`ITSAppUsesNonExemptEncryption` is false: the native app uses system-provided HTTPS, Keychain and storage protection and contains no custom encryption implementation. Reassess the manifest and declaration when adding SDKs or changing data handling or cryptography.

The bundled manifest does not fill in App Store Connect's App Privacy questionnaire. Keep those answers aligned with this notice and the manifest, and set the public privacy-policy URL after verifying that `/privacy` is deployed. Neither an archive nor an accepted upload proves that Apple's processing, privacy metadata or tester distribution is complete.

The beta contact path is the administrator who provisions accounts. Before wider distribution, add the operator's appropriate contact details and confirm the service's retention and backup handling. Do not invent a retention period or claim end-to-end encryption.

## Archive and upload

Keep archives, exports, provisioning data, logs and symbols outside the OneDrive checkout, under a host-local release directory. Archives include the central URL from ignored `ios/Configuration/Local.xcconfig`. Never put that value in tracked release metadata.

With Xcode signed into the selected paid Developer team:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios/MoneyTrack.xcodeproj -scheme MoneyTrack -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$SPENDIE_ARCHIVE_PATH" \
  -allowProvisioningUpdates archive

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -exportArchive -archivePath "$SPENDIE_ARCHIVE_PATH" \
  -exportPath "$SPENDIE_EXPORT_PATH" \
  -exportOptionsPlist ios/Configuration/TestFlightExport.plist \
  -allowProvisioningUpdates
```

`SPENDIE_ARCHIVE_PATH` and `SPENDIE_EXPORT_PATH` are caller-supplied absolute paths outside the checkout. The export configuration uploads using App Store Connect, includes symbols and allows Xcode to manage build numbers. It does not restrict the binary to internal testing, allowing later external beta review. Initial distribution should be to an internal tester group. An upload being accepted is separate from Apple's processing and the build becoming available for testing.

Verify the archive contains the Spendie display name and icon, `PrivacyInfo.xcprivacy`, `privacy.json`, the configured HTTPS server, and the intended bundle ID. Do not reset or remove local stores to resolve signing or upload problems.

References: [required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [encryption declaration](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption), [TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Income import release

Version 0.2.0 adds personal income, API v5 and SwiftData V6, retaining the completed Quick Entry refinements. Existing prepared changes and store contents are migrated without resets. Accounts with income require this update before syncing; budgets are not funded automatically by income. See [ADR 0019](adr/0019-personal-income-bookings.md). Build numbers may be raised by Xcode during export.

## Version 0.2.2

Spendie uses a universal iPhone and iPad build. The iPad layout shows the selected detail beside the list in wide windows and switches to a single column in narrow windows. Test Quick Entry in portrait and landscape and at accessibility text sizes. The app and web companion support English and German, including the privacy notices. Check each language and a German comma-decimal entry before distributing the beta.
