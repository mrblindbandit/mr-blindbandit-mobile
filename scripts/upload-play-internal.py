#!/usr/bin/env python3
"""Upload a signed AAB to Google Play internal testing. Requires PLAY_SERVICE_ACCOUNT_JSON file path via argv[1] and AAB glob argv[2]."""
import glob
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

def main() -> int:
    if len(sys.argv) < 3:
        print("usage: upload-play-internal.py <service-account.json> <aab-glob>", file=sys.stderr)
        return 2
    sa, pattern = sys.argv[1], sys.argv[2]
    aabs = sorted(glob.glob(pattern))
    if not aabs:
        print(f"no AAB matched {pattern}", file=sys.stderr)
        return 1
    aab = aabs[-1]
    creds = service_account.Credentials.from_service_account_file(
        sa, scopes=["https://www.googleapis.com/auth/androidpublisher"]
    )
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    pkg = "net.mrblindbandit.app"
    edit = service.edits().insert(body={}, packageName=pkg).execute()
    edit_id = edit["id"]
    media = MediaFileUpload(aab, mimetype="application/octet-stream", resumable=True)
    bundle = service.edits().bundles().upload(editId=edit_id, packageName=pkg, media_body=media).execute()
    vc = bundle["versionCode"]
    vn = os.environ.get("VERSION_NAME", str(vc))
    service.edits().tracks().update(
        editId=edit_id,
        packageName=pkg,
        track="internal",
        body={
            "track": "internal",
            "releases": [{"versionCodes": [str(vc)], "status": "completed", "name": f"{vn} ({vc})"}],
        },
    ).execute()
    service.edits().commit(editId=edit_id, packageName=pkg).execute()
    print(f"Uploaded versionCode={vc} name={vn} to internal track")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"### Play Console\n")
            f.write(f"- Uploaded **{vn}** (versionCode **{vc}**) to **internal** testing\n")
            f.write(f"- Package `net.mrblindbandit.app`\n")
            f.write(f"- https://play.google.com/console → Testing → Internal testing\n")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
