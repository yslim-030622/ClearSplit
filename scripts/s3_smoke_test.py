import os
import boto3
from dotenv import load_dotenv

# Load .env
load_dotenv()

bucket = os.environ["S3_BUCKET_NAME"]
region = os.environ.get("AWS_REGION", "us-east-2")

s3 = boto3.client("s3", region_name=region)

key = "receipts/smoke-test.txt"

# Upload test file
s3.put_object(
    Bucket=bucket,
    Key=key,
    Body=b"hello clearsplit",
    ContentType="text/plain",
)

# Generate presigned GET URL
url = s3.generate_presigned_url(
    "get_object",
    Params={"Bucket": bucket, "Key": key},
    ExpiresIn=60,
)

print("Uploaded:", key)
print(" Presigned GET URL (valid 60s):")
print(url)