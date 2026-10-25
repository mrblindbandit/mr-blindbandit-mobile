#!/usr/bin/env python3
"""Upload a signed AAB to Google Play. Requires PLAY_SERVICE_ACCOUNT_JSON file path via argv[1] and AAB glob argv[2].

Track from env PLAY_TRACK (default: production). Valid: production, internal, alpha, beta.
Optional PLAY_RELEASE_STATUS (default: completed). Use draft to upload without rolling out.
"""
import glob
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

VALID_TRACKS = {"production", "internal", "alpha", "beta"}


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
    track = (os.environ.get("PLAY_TRACK") or "production").strip().lower()
    if track not in VALID_TRACKS:
        print(f"invalid PLAY_TRACK={track!r}; want one of {sorted(VALID_TRACKS)}", file=sys.stderr)
        return 2
    status = (os.environ.get("PLAY_RELEASE_STATUS") or "completed").strip().lower()
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
        track=track,
        body={
            "track": track,
            "releases": [{"versionCodes": [str(vc)], "status": status, "name": f"{vn} ({vc})"}],
        },
    ).execute()
    service.edits().commit(editId=edit_id, packageName=pkg).execute()
    print(f"Uploaded versionCode={vc} name={vn} to {track} track (status={status})")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"### Play Console\n")
            f.write(f"- Uploaded **{vn}** (versionCode **{vc}**) to **{track}** ({status})\n")
            f.write(f"- Package `net.mrblindbandit.app`\n")
            f.write(f"- https://play.google.com/console → Release → {track}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
