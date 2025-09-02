# terraform/terraform.tfvars.example
# Copy this file to terraform.tfvars and modify the values as needed

# AWS Configuration
aws_region = "us-east-1"

# Cluster Configuration
cluster_name     = "qr-cluster"
environment      = "dev"
project_name     = "qr"
kubernetes_version = "1.28"

# Node Group Configuration
node_instance_types = ["t3.medium"]
capacity_type      = "ON_DEMAND"  # or "SPOT" for cost savings
min_size           = 1
max_size           = 5
desired_size       = 2
disk_size          = 30

# SSH Key for worker nodes (optional)
# key_pair_name = "my-key-pair"

# Networking
single_nat_gateway = true  # Set to false for production for high availability

# Application
app_namespace = "my-app"