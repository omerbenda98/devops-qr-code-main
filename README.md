# devops-qr-code

This is the sample application for the DevOps Capstone Project.
It generates QR Codes for the provided URL, the front-end is in NextJS and the API is written in Python using FastAPI.

## Application

**Front-End** - A web application where users can submit URLs.

**API**: API that receives URLs and generates QR codes. The API stores the QR codes in cloud storage(AWS S3 Bucket).

## Running locally

### API

The API code exists in the `api` directory. You can run the API server locally:

- Clone this repo
- Make sure you are in the `api` directory
- Create a virtualenv by typing in the following command: `python -m venv .venv`
- Install the required packages: `pip install -r requirements.txt`
- Create a `.env` file, and add you AWS Access and Secret key, check `.env.example`
- Also, change the BUCKET_NAME to your S3 bucket name in `main.py`
- Run the API server: `uvicorn main:app --reload`
- Your API Server should be running on port `http://localhost:8000`

### Front-end

The front-end code exits in the `front-end-nextjs` directory. You can run the front-end Server locally:

- Clone this repo
- Make sure you are in the `front-end-nextjs` directory
- Install the dependencies: `npm install`
- Run the NextJS Server: `npm run dev`
- Your Front-end Server should be running on `http://localhost:3000`

## Running on Minikube

This application is configured to run on Minikube using Kubernetes. Follow these steps to run the application:

### Prerequisites

- Minikube installed
- kubectl installed
- Docker installed

### Steps to Run

1. Start Minikube:

minikube start

2. Apply the Kubernetes configurations:

# Apply ConfigMaps

kubectl apply -f backend-configmap.yaml
kubectl apply -f frontend-configmap.yaml

# Apply Services

kubectl apply -f backend-service.yaml
kubectl apply -f frontend-service.yaml

# Apply Deployments

kubectl apply -f backend-deployment.yaml
kubectl apply -f frontend-deployment.yaml

3. Set up port forwarding for the backend service (keep this terminal window open):

kubectl port-forward service/backend-service 8000:8000

4. In a new terminal, expose the frontend service (keep this terminal window open):

minikube service frontend-service --url

5. Access the application:
   Use the URL provided by the minikube service command to access the frontend
   The backend API will be accessible on http://localhost:8000
