#!/bin/bash
set -euo pipefail

REGION="us-east-1"
QUEUE_URL="https://sqs.us-east-1.amazonaws.com/767397735342/process-jobs-queue"
ECR_IMAGE="bondbyvoice-amphion"
LOG_FILE="/var/log/job_processor.log"
CACHE_DIR="/opt/hf-cache"

# Ensure Hugging Face cache directory exists and is writable
mkdir -p "$CACHE_DIR"
chmod 777 "$CACHE_DIR"

echo "🚀 Job processor started at $(date)" | tee -a "$LOG_FILE"

while true; do
  echo "⏳ Checking queue..." | tee -a "$LOG_FILE"

  JOB=$(aws sqs receive-message \
    --queue-url "$QUEUE_URL" \
    --max-number-of-messages 1 \
    --wait-time-seconds 20 \
    --region "$REGION")

  RECEIPT=$(echo "$JOB" | jq -r '.Messages[0].ReceiptHandle // empty')
  BODY=$(echo "$JOB" | jq -r '.Messages[0].Body // empty')

  if [[ -z "$RECEIPT" || -z "$BODY" ]]; then
    echo "⚠️  No message received or empty payload." | tee -a "$LOG_FILE"
    continue
  fi

  # Extract job fields
  JOB_ID=$(echo "$BODY" | jq -r '.job_id // empty')
  TABLE_JOB_QUEUE=$(echo "$BODY" | jq -r '.table_job_queue // empty')
  TABLE_USER_MEDIA=$(echo "$BODY" | jq -r '.table_user_media // empty')
  TABLE_USER_SETTINGS=$(echo "$BODY" | jq -r '.table_user_settings // empty')
  TABLE_BOND_BY_VOICE_USER=$(echo "$BODY" | jq -r '.table_bond_by_voice_user // empty')
  BUCKET_NAME=$(echo "$BODY" | jq -r '.s3_bucket_path // empty')
  MEDIA_ID=$(echo "$BODY" | jq -r '.media_id // empty')
  USER_ID=$(echo "$BODY" | jq -r '.user_id // empty')
  USER_VOICE_ID=$(echo "$BODY" | jq -r '.user_voice_id // empty')
  CREATED_AT=$(echo "$BODY" | jq -r '.created_at // empty')
  PLAYLIST_ID=$(echo "$BODY" | jq -r '.playlist_id // empty')

  echo "📦 Processing job: $JOB_ID" | tee -a "$LOG_FILE"

  TTY_FLAG=""
  if [ -t 1 ]; then
   TTY_FLAG="-t"
  fi

  DOCKER_CMD="docker run -i \
    --cpus=8.0 \
    --memory=30g \
    --rm \
    --name job-$JOB_ID \
    -v $CACHE_DIR:/root/.cache/huggingface \
    -e PYTHONUNBUFFERED=1 \
    -e HF_HOME=/root/.cache/huggingface \
    -e AWS_DEFAULT_REGION=$REGION \
    -e TABLE_JOB_QUEUE=$TABLE_JOB_QUEUE \
    -e TABLE_USER_MEDIA=$TABLE_USER_MEDIA \
    -e TABLE_USER_SETTINGS=$TABLE_USER_SETTINGS \
    -e TABLE_BOND_BY_VOICE_USER=$TABLE_BOND_BY_VOICE_USER \
    -e BUCKET_NAME=$BUCKET_NAME \
    -e JOB_ID=$JOB_ID \
    -e MEDIA_ID=$MEDIA_ID \
    -e USER_ID=$USER_ID \
    -e USER_VOICE_ID=$USER_VOICE_ID \
    -e CREATED_AT=$CREATED_AT \
    -e PLAYLIST_ID=$PLAYLIST_ID \
    $ECR_IMAGE"

  echo "🔧 Running Docker container for job $JOB_ID..." | tee -a "$LOG_FILE"
  echo "$DOCKER_CMD" | tee -a "$LOG_FILE"

  bash -c "$DOCKER_CMD" 2>&1 | tee -a "$LOG_FILE"

  echo "✅ Job $JOB_ID completed at $(date)" | tee -a "$LOG_FILE"

  aws sqs delete-message \
    --queue-url "$QUEUE_URL" \
    --receipt-handle "$RECEIPT" \
    --region "$REGION"

  echo "🧹 Deleted job $JOB_ID from SQS" | tee -a "$LOG_FILE"
done