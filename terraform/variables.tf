# terraform/variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "my-app-cluster"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "my-app"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.28"
}

# Node Group Configuration
variable "node_instance_types" {
  description = "List of instance types for the EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "Type of capacity associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
  default     = "ON_DEMAND"
  
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "Capacity type must be ON_DEMAND or SPOT."
  }
}

variable "min_size" {
  description = "Minimum number of nodes in the node group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes in the node group"
  type        = number
  default     = 3
}

variable "desired_size" {
  description = "Desired number of nodes in the node group"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 30
}

variable "key_pair_name" {
  description = "Name of the AWS key pair for SSH access to worker nodes"
  type        = string
  default     = null
}

# Networking
variable "single_nat_gateway" {
  description = "Should be true to provision a single shared NAT Gateway across all private networks"
  type        = bool
  default     = true
}

# Application Configuration
variable "app_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "default"
}