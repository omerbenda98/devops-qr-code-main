from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import qrcode
import boto3
import os
import time
from io import BytesIO
from fastapi import Query, Response
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from botocore.exceptions import ClientError

# Loading Environment variable (AWS Access Key and Secret Key)
from dotenv import load_dotenv
load_dotenv()

app = FastAPI()

# Define metrics
qr_requests_total = Counter(
    'qr_requests_total', 
    'Total number of QR code generation requests',
    ['status', 'method']
)

qr_request_duration = Histogram(
    'qr_request_duration_seconds',
    'Time spent generating QR codes',
    buckets=(0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
)

qr_codes_generated = Counter(
    'qr_codes_generated_total',
    'Total QR codes successfully generated'
)

qr_generation_errors = Counter(
    'qr_generation_errors_total',
    'Total QR code generation errors',
    ['error_type']
)

active_requests = Gauge(
    'qr_active_requests',
    'Number of active QR generation requests'
)

s3_upload_duration = Histogram(
    'qr_s3_upload_duration_seconds',
    'Time spent uploading QR codes to S3'
)

# App info metric
app_info = Gauge('qr_app_info', 'Application info', ['version', 'environment'])
app_info.labels(version='1.1.0', environment=os.getenv('ENV', 'dev')).set(1)

# Allowing CORS for local testing
origins = [
    "http://localhost:3000",
    "http://localhost:30000",
    "http://192.168.49.2:30000",  # Add NodePort frontend URL
    "*"  # Temporarily for testing
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# AWS S3 Configuration
s3 = boto3.client(
    's3',
    aws_access_key_id=os.getenv("AWS_ACCESS_KEY"),
    aws_secret_access_key=os.getenv("AWS_SECRET_KEY")
)

bucket_name = os.environ.get('S3_BUCKET_NAME', 'my-qr-project-bucket') 

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "qr-generator"}

@app.post("/api/generate-qr/")
async def generate_qr(url: str = Query(...)):
    # Start timing and increment active requests
    start_time = time.time()
    active_requests.inc()
    
    try:
        # Count the request as processing
        qr_requests_total.labels(status='processing', method='POST').inc()
        
        # Generate QR Code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(url)
        qr.make(fit=True)

        img = qr.make_image(fill_color="black", back_color="white")
        
        # Save QR Code to BytesIO object
        img_byte_arr = BytesIO()
        img.save(img_byte_arr, format='PNG')
        img_byte_arr.seek(0)

        # Generate file name for S3
        file_name = f"qr_codes/{url.split('//')[-1]}.png"

        # Time S3 upload separately
        s3_start = time.time()
        
        # Upload to S3
        s3.put_object(
            Bucket=bucket_name, 
            Key=file_name, 
            Body=img_byte_arr, 
            ContentType='image/png'
        )
        
        # Record S3 upload time
        s3_upload_duration.observe(time.time() - s3_start)
        
        # Generate the S3 URL
        s3_url = f"https://{bucket_name}.s3.amazonaws.com/{file_name}"
        
        # Success metrics
        qr_codes_generated.inc()
        qr_requests_total.labels(status='success', method='POST').inc()
        
        return {"qr_code_url": s3_url}
        
    except ClientError as e:
        # S3-specific errors
        qr_generation_errors.labels(error_type='s3_error').inc()
        qr_requests_total.labels(status='error', method='POST').inc()
        raise HTTPException(status_code=500, detail=f"S3 upload failed: {str(e)}")
        
    except Exception as e:
        # General errors
        qr_generation_errors.labels(error_type='general_error').inc()
        qr_requests_total.labels(status='error', method='POST').inc()
        raise HTTPException(status_code=500, detail=f"QR generation failed: {str(e)}")
        
    finally:
        # Record total request time and decrement active requests
        qr_request_duration.observe(time.time() - start_time)
        active_requests.dec()