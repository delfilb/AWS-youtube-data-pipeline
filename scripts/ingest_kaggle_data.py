#!/usr/bin/env python3
"""
Upload historical Kaggle data to the Bronze S3 bucket.

For each region it uploads:

    data/<REGION>videos.csv        -> s3://<bucket>/youtube/raw_statistics/region=<REGION>/<REGION>videos.csv
    data/<REGION>_category_id.json  -> s3://<bucket>/youtube/raw_statistics_reference_data/region=<REGION>/<REGION>_category_id.json

This is a one-time / legacy backfill. The live pipeline ingests from the
YouTube Data API via the youtube-ingestion Lambda; this script just seeds the
Bronze layer with the historical Kaggle dataset for testing and backfill.

Usage:
    python scripts/ingest_kaggle_data.py                       # upload all regions
    python scripts/ingest_kaggle_data.py --regions US GB CA    # subset
    python scripts/ingest_kaggle_data.py --dry-run             # print what would happen
    python scripts/ingest_kaggle_data.py --bucket my-bucket --data-dir ./data

Requires: boto3, and AWS credentials in the environment / shared config.
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError

DEFAULT_BUCKET = "aws-yt-data-pipeline-bronze-us-east-2-dev"
DEFAULT_REGIONS = ["CA", "DE", "FR", "GB", "IN", "JP", "KR", "MX", "RU", "US"]

STATS_PREFIX = "youtube/raw_statistics"
REFERENCE_PREFIX = "youtube/raw_statistics_reference_data"

CONTENT_TYPES = {".csv": "text/csv", ".json": "application/json"}

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger("ingest_kaggle_data")


def planned_uploads(regions: list[str], data_dir: Path) -> list[tuple[Path, str]]:
    """Build the (local_path, s3_key) list for the given regions."""
    uploads: list[tuple[Path, str]] = []
    for region in regions:
        uploads.append((
            data_dir / f"{region}videos.csv",
            f"{STATS_PREFIX}/region={region}/{region}videos.csv",
        ))
        uploads.append((
            data_dir / f"{region}_category_id.json",
            f"{REFERENCE_PREFIX}/region={region}/{region}_category_id.json",
        ))
    return uploads


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bucket", default=DEFAULT_BUCKET, help=f"target S3 bucket (default: {DEFAULT_BUCKET})")
    parser.add_argument("--regions", nargs="+", default=DEFAULT_REGIONS, help="region codes to upload (default: all 10)")
    parser.add_argument("--data-dir", type=Path, default=Path("data"), help="local directory holding the CSV/JSON files")
    parser.add_argument("--dry-run", action="store_true", help="print the planned uploads without calling S3")
    args = parser.parse_args(argv)

    regions = [r.strip().upper() for r in args.regions]
    uploads = planned_uploads(regions, args.data_dir)

    s3 = None if args.dry_run else boto3.client("s3")

    uploaded = 0
    missing = 0
    failed = 0

    for local_path, key in uploads:
        target = f"s3://{args.bucket}/{key}"

        if not local_path.is_file():
            logger.warning("SKIP  %s (not found)", local_path)
            missing += 1
            continue

        if args.dry_run:
            logger.info("DRYRUN %s -> %s", local_path, target)
            uploaded += 1
            continue

        extra_args = {}
        content_type = CONTENT_TYPES.get(local_path.suffix.lower())
        if content_type:
            extra_args["ContentType"] = content_type

        try:
            s3.upload_file(str(local_path), args.bucket, key, ExtraArgs=extra_args or None)
            logger.info("OK    %s -> %s", local_path, target)
            uploaded += 1
        except (BotoCoreError, ClientError) as exc:
            logger.error("FAIL  %s -> %s: %s", local_path, target, exc)
            failed += 1

    logger.info("")
    logger.info("Done. uploaded=%d missing=%d failed=%d", uploaded, missing, failed)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
