import os
import sys
import glob
import subprocess
import uuid
import json
import boto3
from models.svc.vevosing.infer_vevosing_fm import load_inference_pipeline
from models.svc.vevosing.vevosing_utils import *
import random

# AWS Clients
s3 = boto3.client("s3")
region = os.getenv("AWS_REGION", "us-east-1")
dynamodb = boto3.resource("dynamodb", region_name=region)

# Load Environment Variables
TABLE_JOB_QUEUE = os.getenv("TABLE_JOB_QUEUE")
TABLE_USER_MEDIA = os.getenv("TABLE_USER_MEDIA")
TABLE_USER_SETTINGS = os.getenv("TABLE_USER_SETTINGS")
TABLE_BOND_BY_VOICE_USER = os.getenv("TABLE_BOND_BY_VOICE_USER")
BUCKET_NAME = os.getenv("BUCKET_NAME")

MEDIA_ID = os.getenv("MEDIA_ID")
USER_ID = os.getenv("USER_ID")
USER_VOICE_ID = os.getenv("USER_VOICE_ID")
CREATED_AT = os.getenv("CREATED_AT")
JOB_ID = os.getenv("JOB_ID")
PLAYLIST_ID = os.getenv("PLAYLIST_ID", None)  # optional

os.makedirs("/tmp/chunks", exist_ok=True)
os.makedirs("/tmp/output", exist_ok=True)
os.makedirs("/tmp/processed", exist_ok=True)

# Validate important ENV
required_envs = [TABLE_JOB_QUEUE, TABLE_USER_MEDIA, TABLE_USER_SETTINGS, TABLE_BOND_BY_VOICE_USER, BUCKET_NAME, MEDIA_ID, USER_ID, USER_VOICE_ID, CREATED_AT, JOB_ID]
for env_var in required_envs:
    if not env_var:
        print(f"❌ ERROR: Missing required ENV variable.")
        sys.exit(1)

def get_user(user_id):
    table = dynamodb.Table(TABLE_BOND_BY_VOICE_USER)
    response = table.get_item(Key={"id": user_id})
    return response.get("Item")

def update_job_queue_status(job_id, status):
    table = dynamodb.Table(TABLE_JOB_QUEUE)
    table.update_item(
        Key={"id": job_id},
        UpdateExpression="SET #status = :status",
        ExpressionAttributeNames={"#status": "status"},
        ExpressionAttributeValues={":status": status},
    )


def upload_file_to_s3(local_file_path, destination_s3_key):
    """Upload a local file into the S3 bucket."""
    s3.upload_file(local_file_path, BUCKET_NAME, destination_s3_key)
    print(f"✅ Uploaded {local_file_path} to s3://{BUCKET_NAME}/{destination_s3_key}")                

def download_s3_file(s3_key, local_path):
    """Download a single audio/video file from S3 to local path."""
    allowed_extensions = ('.wav', '.mp3', '.flac', '.aac', '.ogg', '.mp4', '.mov', '.avi', '.mkv')
    
    if not s3_key.lower().endswith(allowed_extensions):
        print(f"⚡ Skipping non-audio/video file: {s3_key}")
        return

    s3.download_file(BUCKET_NAME, s3_key, local_path)
    print(f"✅ Downloaded s3://{BUCKET_NAME}/{s3_key} to {local_path}")

def create_user_media(user_id, identity_id, media_id, voice_id, created_at, title="Processed Media"):
    table = dynamodb.Table(TABLE_USER_MEDIA)
    user_media_id = str(uuid.uuid4())

    table.put_item(
        Item={
            "id": user_media_id,
            "userId": user_id,
            "title": title,
            "text": f"Processed media for {media_id}",
            "url": f"private/user-media/{identity_id}/{user_media_id}/",
            "mediaID": media_id,
            "voiceID": voice_id,
            "mediaId": media_id,
            "voiceId": voice_id,
            "createdAt": created_at,
            "updatedAt": created_at
        }
    )
    return user_media_id

def vevosing_fm(inference_pipeline, content_wav_path, reference_wav_path, output_path, shifted_src=True):
    gen_audio = inference_pipeline.inference_fm(
        src_wav_path=content_wav_path,
        timbre_ref_wav_path=reference_wav_path,
        use_shifted_src_to_extract_prosody=shifted_src,
        flow_matching_steps=32,
    )
    save_audio(gen_audio, output_path=output_path)

def run_inference():
    
    user = get_user(USER_ID)
    identity_id = user["identityId"]

    # Build paths
    random_index = random.randint(1, 4)

    output_dir          = f"./processing/{MEDIA_ID}/output"
    processed_dir       = f"./processing/{MEDIA_ID}/processed-segments"    
    final_output_path   = os.path.join(output_dir, "final_output.wav")
    
    # Local paths after downloading
    local_chunks_dir = "/tmp/chunks/"
    local_instrumental_path = "/tmp/instrumental.wav"
    local_reference_wav_path = "/tmp/reference.wav"

    # Make sure local folders exist
    os.makedirs(local_chunks_dir, exist_ok=True)
    
    # Download all chunk files
    chunk_prefix = f"public/media/{MEDIA_ID}/chunks/"
    paginator = s3.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=BUCKET_NAME, Prefix=chunk_prefix)
    for page in pages:
        for obj in page.get('Contents', []):
            chunk_key = obj['Key']
            local_chunk_path = os.path.join("/tmp/chunks", os.path.basename(chunk_key))
            download_s3_file(chunk_key, local_chunk_path)

    # Download reference wav
    reference_s3_key = f"private/voices/{identity_id}/{USER_VOICE_ID}/input_{random_index:03d}.wav"
    print(f"? Downloading s3://{BUCKET_NAME}/{reference_s3_key} to /tmp/reference.wav")
    download_s3_file(reference_s3_key, "/tmp/reference.wav")

    # Download instrumental wav
    instrumental_s3_key = f"public/media/{MEDIA_ID}/instrumental.wav"
    download_s3_file(instrumental_s3_key, "/tmp/instrumental.wav")    

    os.makedirs(processed_dir, exist_ok=True)
    os.makedirs(output_dir, exist_ok=True)

    update_job_queue_status(JOB_ID, "IN_PROGRESS")
    # Load model
    print("Loading Pipeline")
    inference_pipeline = load_inference_pipeline()
    print("PIPELINE LOADED")

    # Inference chunks
    chunk_files = sorted(glob.glob(os.path.join(local_chunks_dir, "output_chunk_*.wav")))
    if not chunk_files:
        print("❌ No audio chunks found to process.")
        update_job_queue_status(JOB_ID, "FAILED")
        sys.exit(1)
    
    for i, chunk_path in enumerate(chunk_files):
        chunk_filename = f"processed_chunk_{i:03d}.wav"
        output_path = os.path.join(processed_dir, chunk_filename)
        print(f"Processing {output_path}")
        vevosing_fm(inference_pipeline, chunk_path, local_reference_wav_path, output_path)
        print(f"Processed {chunk_filename}")

    # Concatenate chunks
    concat_list_path = os.path.join(processed_dir, "concat_list.txt")
    with open(concat_list_path, "w") as f:
        for i in range(len(chunk_files)):
            f.write(f"file 'processed_chunk_{i:03d}.wav'\n")

    subprocess.run([
        "ffmpeg", "-f", "concat", "-safe", "0", "-i", concat_list_path,
        "-c", "copy", final_output_path
    ], check=True)

    # Mix with instrumental
    mixed_output_path = os.path.join(output_dir, "mixed_output.wav")
    subprocess.run([
        "ffmpeg",
        "-i", final_output_path,
        "-i", local_instrumental_path,
        "-filter_complex",
        "[0:a]volume=1.5[a0];[1:a]volume=0.6[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=2",
        "-y",
        mixed_output_path
    ], check=True)
    
    mixed_output_path = os.path.join(output_dir, "mixed_output.wav")
    # Download main video
    media_key = f"public/media/{MEDIA_ID}/md4.mp4"
    download_s3_file(media_key, "/tmp/md4.mp4")    
    
    final_video_output_path = os.path.join(output_dir, "final_output_video.mp4")
    subprocess.run([
        "ffmpeg",
        "-i", "/tmp/md4.mp4",           # input video
        "-i", mixed_output_path,        # input new audio
        "-c:v", "copy",                 # copy video stream without re-encoding
        "-map", "0:v:0",                # map video from first input
        "-map", "1:a:0",                # map audio from second input
        "-shortest",                    # make duration match shortest input
        "-y",                           # overwrite if file exists
        final_video_output_path         # output file
    ], check=True)
        
    #  Copy from local to S3
    user_media_id = create_user_media(USER_ID, identity_id, MEDIA_ID, USER_VOICE_ID, CREATED_AT)
    user_media_path   = f"private/user-media/{identity_id}/{user_media_id}/output.mp4"
    upload_file_to_s3(final_video_output_path, user_media_path)
    
if __name__ == "__main__":
    try:
        print("🚀 Processing AI Task...")
        
        # Run the actual model
        run_inference()

        update_job_queue_status(JOB_ID, "COMPLETED")
        print("✅ Successfully completed job.")

    except Exception as e:
        print(f"❌ ERROR: {str(e)}")
        update_job_queue_status(JOB_ID, "FAILED")
