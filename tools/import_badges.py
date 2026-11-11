"""Uploads docs/badges_seed.json to the Firestore `badges` collection.

One document per badge (document id = the key in the JSON, e.g.
"alphabet_explorer"). Existing documents are updated (merge), so it is safe
to run again; fields edited by faculty on the web are overwritten only if
they are in the JSON.

Run once from the project folder:
    pip install firebase-admin
    python tools/import_badges.py path/to/service-account-key.json

The key: Firebase console > Project settings > Service accounts >
Generate new private key. Keep it private (never commit it).
"""
import json
import os
import sys

import firebase_admin
from firebase_admin import credentials, firestore


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit('Usage: python tools/import_badges.py <service-account-key.json>')
    here = os.path.dirname(os.path.abspath(__file__))
    seed_path = os.path.join(here, '..', 'docs', 'badges_seed.json')
    with open(seed_path, encoding='utf-8') as f:
        badges = json.load(f)

    firebase_admin.initialize_app(credentials.Certificate(sys.argv[1]))
    db = firestore.client()

    batch = db.batch()
    for badge_id, data in badges.items():
        batch.set(db.collection('badges').document(badge_id), data, merge=True)
    batch.commit()
    print(f'Uploaded {len(badges)} badges to Firestore "badges".')


if __name__ == '__main__':
    main()
