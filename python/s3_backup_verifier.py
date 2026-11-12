#!/usr/bin/env python3
"""
s3_backup_verifier.py
EN: Audits an Amazon S3 corporate backup bucket to verify daily backup SLA freshness
    per server and reports storage consumption across S3 Storage Classes.
PT: Audita um bucket de backup corporativo no Amazon S3 para validar se os backups
    diários estão em dia (SLA) e sumariza o uso por classe de armazenamento.
"""

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import boto3


def format_bytes(size_bytes: int) -> str:
    """Formats raw bytes into human-readable MB/GB/TB."""
    size = float(size_bytes)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024.0:
            return f"{size:.2f} {unit}"
        size /= 1024.0
    return f"{size:.2f} PB"


def audit_s3_backups(bucket: str, prefix: str, max_age_hours: int) -> None:
    s3 = boto3.client("s3")
    paginator = s3.get_paginator("list_objects_v2")
    now = datetime.now(timezone.utc)

    latest_per_host = {}
    storage_class_bytes = defaultdict(int)
    total_objects = 0

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if key.endswith("/") or key.endswith(".sha256"):
                continue

            total_objects += 1
            size = obj["Size"]
            last_modified = obj["LastModified"]
            storage_class = obj.get("StorageClass", "STANDARD")
            storage_class_bytes[storage_class] += size

            # Expected key structure: backups/<hostname>/<YYYY-MM-DD>/<archive>
            parts = key.split("/")
            host = parts[1] if len(parts) > 2 else "root"

            if host not in latest_per_host or last_modified > latest_per_host[host]["last_modified"]:
                latest_per_host[host] = {
                    "key": key,
                    "size": size,
                    "last_modified": last_modified,
                    "storage_class": storage_class,
                }

    print("=" * 78)
    print(f"  AMAZON S3 ENTERPRISE BACKUP SLA AUDITOR | Bucket: s3://{bucket}/{prefix}")
    print("=" * 78)

    if not latest_per_host:
        print("[WARN] No backup archives found under the specified prefix.")
        return

    print("\n[1] LATEST BACKUP STATUS PER SERVER (SLA Threshold: <= " + str(max_age_hours) + "h)")
    for host, info in sorted(latest_per_host.items()):
        age_hours = round((now - info["last_modified"]).total_seconds() / 3600, 1)
        status = "SLA_OK" if age_hours <= max_age_hours else "STALE_ALERT"
        print(
            f"    [{status:<11}] Host: {host:<18} | Age: {age_hours:>5}h | "
            f"Size: {format_bytes(info['size']):<10} | Class: {info['storage_class']}"
        )

    print("\n[2] STORAGE CONSUMPTION BY S3 STORAGE CLASS (FINOPS SUMMARY)")
    for sclass, total_b in sorted(storage_class_bytes.items()):
        print(f"    {sclass:<20} : {format_bytes(total_b)}")
    print(f"    {'TOTAL ARCHIVES':<20} : {total_objects}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Amazon S3 Backup SLA & Storage Tier Auditor")
    parser.add_argument("--bucket", required=True, help="Target S3 backup bucket name")
    parser.add_argument("--prefix", default="backups/", help="Backup key prefix (default: backups/)")
    parser.add_argument("--max-age-hours", type=int, default=26, help="Max hours before alerting stale backup")
    args = parser.parse_args()

    audit_s3_backups(args.bucket, args.prefix, args.max_age_hours)


if __name__ == "__main__":
    main()
