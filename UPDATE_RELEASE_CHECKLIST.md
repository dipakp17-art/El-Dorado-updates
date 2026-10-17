# Safe El Dorado update rollout

## Current release discrepancy (audit 2026-10-18)

- `app.json` advertises version 1.96 (versionCode 97).
- `update.json` advertises version 1.13 (versionCode 14).
- **Do not automatically synchronize these files** until the Android app's update-check code is inspected. They may be used by different app versions, and `app.json` includes rollout controls (`rolloutAt`, `hold`, `testers`) absent from `update.json`.
- A public APK URL or version manifest does not prove that the APK works or that every client receives the update.

## Checklist before shipping an APK

1. Confirm which endpoint each installed Android version actually reads: `app.json`, `update.json`, or something else.
2. Verify the APK exists at the advertised URL and compare its bytes against the manifest `sha256` and `size`.
3. Confirm the APK package ID, signing certificate, and versionCode permit upgrading the currently installed version without losing data.
4. Test the call lifecycle on **two physical phones**: ringing continues until answer/cancel; both devices show connected immediately; bidirectional audio starts promptly; decline and missed calls clean up.
5. Verify update checks respect `hold`, `rolloutAt`, and `testers` wherever those fields are used. Never assume legacy clients enforce them.
6. Roll out to test devices first; confirm update installation, messaging, calling, and server compatibility.
7. Only then update the appropriate manifest(s) and announce the release. Keep the previous signed APK available for controlled rollback (Android does not generally allow direct downgrades).

## Evidence needed to fix the calling issue

Provide the Android Studio source code for the call state machine, ringback playback, signaling, and audio initialization. The update/distribution repository alone cannot diagnose the one-ring-then-silent bug.
