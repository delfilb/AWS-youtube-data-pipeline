"""
Lambda: JSON Reference Data → Silver Layer (Parquet)
────────────────────────────────────────────────────
Triggered by S3 event when new JSON lands in the Bronze bucket
under the reference_data prefix.

Improvements over original:
  - Data validation before writing
  - Deduplication of category records
  - Proper error handling with dead-letter alerting
  - Idempotent writes (overwrites partition, not append)
  - Structured logging

Environment Variables:
    S3_BUCKET_SILVER            — Target bucket for cleansed data
    GLUE_DB_SILVER              — Glue catalog database name
    GLUE_TABLE_REFERENCE        — Glue catalog table name
    SNS_ALERT_TOPIC_ARN         — SNS topic for alerts (optional)
"""

import json
import os
import logging
from datetime import datetime, timezone
from urllib.parse import unquote_plus

import boto3
import awswrangler as wr
import pandas as pd

# ── Logging ──────────────────────────────────────────────────────────────────
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ── Config ───────────────────────────────────────────────────────────────────
SILVER_BUCKET = os.environ["S3_BUCKET_SILVER"]
GLUE_DB = os.environ.get("GLUE_DB_SILVER", "yt_pipeline_silver_dev")
GLUE_TABLE = os.environ.get("GLUE_TABLE_REFERENCE", "clean_reference_data")
SNS_TOPIC = os.environ.get("SNS_ALERT_TOPIC_ARN", "")
SILVER_PATH = f"s3://{SILVER_BUCKET}/youtube/reference_data/"

# Used when the function is invoked directly (Step Functions) rather than by an
# S3 event — it then discovers the current reference files itself.
BRONZE_BUCKET = os.environ.get("S3_BUCKET_BRONZE", "")
BRONZE_REFERENCE_PREFIX = os.environ.get(
    "BRONZE_REFERENCE_PREFIX", "youtube/raw_statistics_reference_data/"
)

s3_client = boto3.client("s3")
sns_client = boto3.client("sns")


def read_json_from_s3(bucket: str, key: str) -> dict:
    """
    Read raw JSON from S3 using boto3 instead of awswrangler.
    awswrangler.s3.read_json() fails on the Kaggle/YouTube category JSON
    because it has mixed types (strings + nested arrays), which pandas
    can't parse directly into a DataFrame.
    """
    response = s3_client.get_object(Bucket=bucket, Key=key)
    content = response["Body"].read().decode("utf-8")
    return json.loads(content)


def validate_category_data(df: pd.DataFrame) -> pd.DataFrame:
    """
    Validate and clean the category reference data.
    Returns cleaned DataFrame or raises ValueError.
    """
    if df.empty:
        raise ValueError("Empty DataFrame — no category items found")

    required_cols = {"id", "snippet.title"}
    actual_cols = set(df.columns)
    missing = required_cols - actual_cols
    if missing:
        # Try alternate column names from different API versions
        logger.warning(f"Missing expected columns: {missing}. Available: {actual_cols}")

    # Drop duplicate categories (same id)
    before = len(df)
    if "id" in df.columns:
        df = df.drop_duplicates(subset=["id"], keep="last")
    after = len(df)
    if before != after:
        logger.info(f"  Removed {before - after} duplicate categories")

    return df


def send_alert(subject: str, message: str):
    if SNS_TOPIC:
        sns_client.publish(TopicArn=SNS_TOPIC, Subject=subject[:100], Message=message)


def _newest_key_under(bucket: str, prefix: str) -> str:
    """
    Return the lexicographically-greatest .json key under `prefix`, or "".
    Reference keys embed a sortable date (.../date=2026-08-27/...), so the
    greatest key under a region prefix is that region's most recent file.
    """
    paginator = s3_client.get_paginator("list_objects_v2")
    newest = ""
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key.endswith(".json") and key > newest:
                newest = key
    return newest


def keys_for_regions(bucket: str, prefix: str, regions: list) -> list:
    """Newest reference file per region, for an explicit region list."""
    keys = []
    for region in regions:
        newest = _newest_key_under(bucket, f"{prefix}region={region}/")
        if newest:
            keys.append(newest)
        else:
            logger.warning(f"No reference file found under region={region}")
    return keys


def discover_all_reference_keys(bucket: str, prefix: str) -> list:
    """Newest reference file per region across the whole prefix (no region list)."""
    paginator = s3_client.get_paginator("list_objects_v2")
    latest: dict = {}
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".json"):
                continue
            region = "unknown"
            for part in key.split("/"):
                if part.startswith("region="):
                    region = part.split("=", 1)[1]
                    break
            if region not in latest or key > latest[region]:
                latest[region] = key
    return sorted(latest.values())


def lambda_handler(event, context):
    """
    Transform YouTube category reference JSON (Bronze) into the Silver
    clean_reference_data table.

    Invocation modes:
      - S3 event               — process the object(s) in the event.
      - Step Functions         — event carries {"regions": [...]}; process the
                                 newest Bronze file for each of those regions.
                                 This is the pipeline's in-band path.
      - Direct / manual        — no regions given; rescan the whole Bronze
                                 reference prefix and reprocess the latest file
                                 per region.
    """

    records = event.get("Records", [])
    if not records and "s3" in event:
        records = [event]
    elif not records:
        if not BRONZE_BUCKET:
            logger.warning("Direct invocation but S3_BUCKET_BRONZE is unset — nothing to process")
        else:
            regions = [
                str(r).strip().upper()
                for r in (event.get("regions") or [])
                if str(r).strip()
            ]
            if regions:
                logger.info(
                    f"Step Functions invocation — ingestion_id={event.get('ingestion_id')}, "
                    f"regions={regions}"
                )
                keys = keys_for_regions(BRONZE_BUCKET, BRONZE_REFERENCE_PREFIX, regions)
            else:
                logger.info(
                    f"Direct invocation — rescanning "
                    f"s3://{BRONZE_BUCKET}/{BRONZE_REFERENCE_PREFIX}"
                )
                keys = discover_all_reference_keys(BRONZE_BUCKET, BRONZE_REFERENCE_PREFIX)
            logger.info(f"Reprocessing {len(keys)} reference file(s)")
            records = [
                {"s3": {"bucket": {"name": BRONZE_BUCKET}, "object": {"key": k}}}
                for k in keys
            ]

    processed = []
    errors = []

    for record in records:
        try:
            s3_info = record["s3"]
            bucket = s3_info["bucket"]["name"]
            key = unquote_plus(s3_info["object"]["key"])

            logger.info(f"Processing: s3://{bucket}/{key}")

            # ── Read raw JSON ────────────────────────────────────────────
            # We use boto3 + json.loads instead of wr.s3.read_json() because
            # the category JSON has mixed types (strings like "kind"/"etag"
            # alongside a nested "items" array) which causes pandas to fail
            # with: "Mixing dicts with non-Series may lead to ambiguous ordering"
            raw_data = read_json_from_s3(bucket, key)

            # The YouTube/Kaggle JSON has { "kind": "...", "items": [...] }
            # We only care about the items array
            if "items" in raw_data and isinstance(raw_data["items"], list):
                df = pd.json_normalize(raw_data["items"])
            else:
                # Fallback: try to normalize the entire object
                df = pd.json_normalize(raw_data)

            logger.info(f"  Raw shape: {df.shape}")

            # ── Validate ─────────────────────────────────────────────────
            df = validate_category_data(df)

            # ── Add metadata columns ─────────────────────────────────────
            # _ingestion_timestamp must reflect when the data was collected from
            # YouTube, NOT when this transform ran — otherwise reprocessing a
            # stale Bronze file would hide an ingestion outage from the DQ
            # freshness check. Carry the source timestamp through; fall back to
            # now() only for legacy files with no pipeline metadata.
            meta = raw_data.get("_pipeline_metadata", {}) if isinstance(raw_data, dict) else {}
            df["_ingestion_timestamp"] = (
                meta.get("ingestion_timestamp") or datetime.now(timezone.utc).isoformat()
            )
            df["_transformed_at"] = datetime.now(timezone.utc).isoformat()
            df["_source_file"] = key

            # Extract region from the S3 key (e.g., region=US)
            region = "unknown"
            for part in key.split("/"):
                if part.startswith("region="):
                    region = part.split("=")[1]
                    break
            df["region"] = region

            logger.info(f"  Clean shape: {df.shape}, region: {region}")

            # ── Write to Silver layer as Parquet ─────────────────────────
            wr_response = wr.s3.to_parquet(
                df=df,
                path=SILVER_PATH,
                dataset=True,
                database=GLUE_DB,
                table=GLUE_TABLE,
                partition_cols=["region"],
                mode="overwrite_partitions",  # Idempotent per region
                schema_evolution=True,
            )

            logger.info(f"  Written to Silver: {SILVER_PATH}")
            processed.append({"key": key, "region": region, "rows": len(df)})

        except Exception as e:
            logger.error(f"Error processing record: {e}", exc_info=True)
            errors.append({"key": key if "key" in dir() else "unknown", "error": str(e)})

    # ── Summary ──────────────────────────────────────────────────────────
    if errors:
        send_alert(
            subject="[YT Pipeline] Silver reference transform failed",
            message=json.dumps(errors, indent=2),
        )

    # Surface failures to the caller. Step Functions only inspects the Lambda
    # invocation's success/failure, not the payload — returning 200 here would
    # let the orchestrator proceed to the DQ gate as if the Silver reference
    # data had been refreshed. Raise whenever any record failed so the
    # state machine's Catch fires and the run stops.
    if errors:
        raise RuntimeError(
            f"Reference transform failed for {len(errors)}/{len(records)} file(s); "
            f"processed {len(processed)}. First error: {errors[0]['error']}"
        )

    return {
        "statusCode": 200,
        "processed": processed,
        "errors": errors,
    }