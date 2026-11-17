#!/usr/bin/env bash
# Writes a placeholder RoadFix/GoogleService-Info.plist so CI can build the
# app and run the tests without the real Firebase config.
#
# Why a placeholder instead of the real file:
# - The repo is public, so the real config never goes into git.
# - The unit tests don't talk to Firebase, so they don't need it. Using fake
#   values means a test run can never read or write production data.
# - FirebaseApp.configure() only checks that the values are well formed,
#   which is all the app needs to launch for the tests.
#
# Sentry-Info.plist is left out on purpose: without it Sentry stays off
# (see CrashReporting.swift), so CI runs send nothing to Sentry.
set -euo pipefail

target="RoadFix/GoogleService-Info.plist"

if [[ -f "$target" ]]; then
  echo "$target already exists, leaving it as is."
  exit 0
fi

cat > "$target" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>AIzaSyCI000000000000000000000000000000</string>
	<key>GCM_SENDER_ID</key>
	<string>000000000000</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>md.roadfix.RoadFix</string>
	<key>PROJECT_ID</key>
	<string>demo-roadfix-ci</string>
	<key>STORAGE_BUCKET</key>
	<string>demo-roadfix-ci.appspot.com</string>
	<key>IS_ADS_ENABLED</key>
	<false/>
	<key>IS_ANALYTICS_ENABLED</key>
	<false/>
	<key>IS_APPINVITE_ENABLED</key>
	<false/>
	<key>IS_GCM_ENABLED</key>
	<false/>
	<key>IS_SIGNIN_ENABLED</key>
	<true/>
	<key>GOOGLE_APP_ID</key>
	<string>1:000000000000:ios:0000000000000000000000</string>
</dict>
</plist>
PLIST

echo "Wrote placeholder $target (fake values, not a real Firebase project)."
