#!/usr/bin/env bash
# Generates the native platform folders and applies app-specific patches.
# Usage: tools/scaffold.sh android,ios,windows,web
set -euo pipefail
PLATFORMS="${1:-android}"

flutter create --project-name calculator --org com.solarplanner --platforms="$PLATFORMS" --no-pub .
rm -f test/widget_test.dart

if [[ "$PLATFORMS" == *android* ]]; then
python3 - <<'PY'
import re, os

# ---- manifest: internet access, link opening, app name ----
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()
s = re.sub(r'android:label="[^"]*"', 'android:label="Solar Planner"', s, count=1)
extra = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
    </queries>'''
if 'android.permission.ACCESS_COARSE_LOCATION' not in s:
    s = re.sub(r'(<manifest[^>]*>)', lambda m: m.group(1) + extra, s, count=1)
open(p, 'w', encoding='utf-8').write(s)

# ---- signing: one fixed key for every build so updates install over old versions ----
kts = 'android/app/build.gradle.kts'
groovy = 'android/app/build.gradle'
if os.path.exists(kts):
    with open(kts, 'a', encoding='utf-8') as f:
        f.write('''

android {
    signingConfigs {
        getByName("debug") {
            storeFile = rootProject.file("../signing/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
}
''')
elif os.path.exists(groovy):
    s = open(groovy, encoding='utf-8').read()
    s = s.replace('android {\n', """android {
    signingConfigs {
        debug {
            storeFile rootProject.file('../signing/debug.keystore')
            storePassword 'android'
            keyAlias 'androiddebugkey'
            keyPassword 'android'
        }
    }
""", 1)
    open(groovy, 'w', encoding='utf-8').write(s)
else:
    raise SystemExit('No android/app/build.gradle(.kts) found')
print('android patched')
PY
fi

if [[ "$PLATFORMS" == *web* ]]; then
  sed -i.bak 's#<title>calculator</title>#<title>Solar Planner \& Calculator</title>#' web/index.html || true
fi

if [[ "$PLATFORMS" == *ios* ]]; then
python3 - <<'PY'
p = 'ios/Runner/Info.plist'
s = open(p, encoding='utf-8').read()
if 'NSLocationWhenInUseUsageDescription' not in s:
    s = s.replace('</dict>\n</plist>', '\t<key>NSLocationWhenInUseUsageDescription</key>\n\t<string>Your location is used to show local sunlight, tariffs and the right grid.</string>\n</dict>\n</plist>')
    open(p, 'w', encoding='utf-8').write(s)
PY
fi
