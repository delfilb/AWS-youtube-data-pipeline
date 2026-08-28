# Data directory

This project uses the **YouTube Trending Video Dataset** (Kaggle) as historical
backfill/test data for the Bronze layer.

Only the **CA** (Canada) sample is committed to this repo as a working example:

- `CAvideos.csv`
- `CA_category_id.json`

## Getting the full dataset

Download the remaining regions (US, GB, DE, FR, IN, JP, KR, MX, RU) from:

https://www.kaggle.com/datasets/datasnaek/youtube-new/data

Place the extracted files directly in this `data/` directory, keeping the
original names (`<REGION>videos.csv` and `<REGION>_category_id.json`). They are
gitignored, so they will not be committed.

## Uploading to S3

Once the files are in place, seed the Bronze bucket with:

```bash
python scripts/ingest_kaggle_data.py            # all regions
python scripts/ingest_kaggle_data.py --regions CA US   # subset
python scripts/ingest_kaggle_data.py --dry-run  # preview
```
