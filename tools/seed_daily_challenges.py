"""Upload the app's daily quest conditions to Firestore `daily_challenges`
(one document per quest, like `badges`), so the web dashboard can list,
edit and analyse them.

1. Export the app's built-in quests:
       flutter test test/export_daily_challenges_test.dart
   (writes tools/daily_challenges.json)
2. Upload:
       python tools/seed_daily_challenges.py --key path/to/service-account.json

Existing documents are NOT overwritten (edits made on the web are kept);
add --overwrite to replace them with the app's defaults.
Needs: pip install firebase-admin
The service-account key is private: never commit it or share it.
"""
import argparse
import json
import os
import sys

import firebase_admin
from firebase_admin import credentials, firestore

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--key', required=True, help='Firebase service-account JSON')
    ap.add_argument('--file', default=os.path.join(ROOT, 'tools', 'daily_challenges.json'))
    ap.add_argument('--overwrite', action='store_true', help='replace documents that already exist')
    args = ap.parse_args()

    if not os.path.isfile(args.file):
        sys.exit(f'{args.file} not found. Run: flutter test test/export_daily_challenges_test.dart')
    quests = json.load(open(args.file, encoding='utf-8'))

    firebase_admin.initialize_app(credentials.Certificate(args.key))
    db = firestore.client()
    col = db.collection('daily_challenges')
    added = kept = replaced = 0
    for q in quests:
        ref = col.document(q['id'])
        exists = ref.get().exists
        if exists and not args.overwrite:
            kept += 1
            continue
        data = {k: v for k, v in q.items() if k != 'id'}
        data['updatedAt'] = firestore.SERVER_TIMESTAMP
        ref.set(data)
        if exists:
            replaced += 1
        else:
            added += 1
    print(f'daily_challenges: {added} added, {replaced} replaced, {kept} kept (already there).')


if __name__ == '__main__':
    main()
