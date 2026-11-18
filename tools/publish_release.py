"""Publish a HandSpeak Android release so installed apps offer it (Settings > App updates).

1. Raise the version in pubspec.yaml, e.g. `version: 1.0.2+3` (the number after
   + MUST be higher than the installed one; that is what the app compares).
2. Build:  flutter build apk --release
3. Run:    python tools/publish_release.py --key path/to/service-account.json \
               --note "Gesture to Text: translate signs to text and back" \
               --note "Green dot shows friends who are online"
   Add --required to make every older version update (no "Later" button).

It uploads the APK to Firebase Storage (releases/handspeak-<version>.apk) and
writes Firestore app_config/android_release, which the app reads.
Needs: pip install firebase-admin
The service-account key is private: never commit it or share it.
"""
import argparse
import os
import re
import sys
import uuid
from urllib.parse import quote

import firebase_admin
from firebase_admin import credentials, firestore, storage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUCKET = 'handspeak-96d8d.firebasestorage.app'


def pubspec_version():
    text = open(os.path.join(ROOT, 'pubspec.yaml'), encoding='utf-8').read()
    m = re.search(r'^version:\s*([0-9.]+)\+(\d+)\s*$', text, re.M)
    if not m:
        sys.exit('pubspec.yaml has no "version: x.y.z+N" line')
    return m.group(1), int(m.group(2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--key', required=True, help='Firebase service-account JSON')
    ap.add_argument('--apk', default=os.path.join(ROOT, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'))
    ap.add_argument('--note', action='append', default=[], help="a What's new line (repeat for more)")
    ap.add_argument('--required', action='store_true', help='older versions must update')
    args = ap.parse_args()

    name, code = pubspec_version()
    if not os.path.isfile(args.apk):
        sys.exit(f'APK not found: {args.apk}\nRun: flutter build apk --release')
    size = os.path.getsize(args.apk)

    firebase_admin.initialize_app(credentials.Certificate(args.key), {'storageBucket': BUCKET})
    db = firestore.client()
    doc = db.collection('app_config').document('android_release')
    old = doc.get().to_dict() or {}
    if int(old.get('versionCode', 0)) >= code:
        sys.exit(f"Published versionCode is {old.get('versionCode')}; raise the +N in pubspec.yaml above it (now {code}).")

    path = f'releases/handspeak-{name}.apk'
    token = str(uuid.uuid4())
    blob = storage.bucket().blob(path)
    blob.metadata = {'firebaseStorageDownloadTokens': token}
    print(f'Uploading {args.apk} ({size / 1048576:.1f} MB) to {path} ...')
    blob.upload_from_filename(args.apk, content_type='application/vnd.android.package-archive')
    url = f'https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{quote(path, safe="")}?alt=media&token={token}'

    doc.set({
        'versionCode': code,
        'versionName': name,
        'apkUrl': url,
        'sizeBytes': size,
        'notes': args.note,
        'minVersionCode': code if args.required else int(old.get('minVersionCode', 0)),
        'publishedAt': firestore.SERVER_TIMESTAMP,
    })
    print(f'Published {name} (+{code}). Installed apps will offer it on the next start or in Settings > App updates.')


if __name__ == '__main__':
    main()
