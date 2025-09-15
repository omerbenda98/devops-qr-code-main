# terraform/main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

# Configure providers
provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}

# Local values
locals {
  name   = var.cluster_name
  region = var.aws_region

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Disable VPC logs for cost optimization in dev environments
  enable_flow_log                      = var.environment == "prod"
  create_flow_log_cloudwatch_iam_role  = var.environment == "prod"
  create_flow_log_cloudwatch_log_group = var.environment == "prod"

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    main = {
      name = "${local.name}-main"

      instance_types = var.node_instance_types
      capacity_type  = var.capacity_type

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      disk_size = var.disk_size

      labels = {
        Environment = var.environment
        NodeGroup   = "main"
      }

      update_config = {
        max_unavailable_percentage = 33
      }

      tags = local.tags
    }
  }

  # aws-auth configmap
  manage_aws_auth_configmap = true

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

# Security group for remote access (only if SSH key is provided)
resource "aws_security_group" "remote_access" {
  count = var.key_pair_name != null ? 1 : 0
  
  name_prefix = "${local.name}-remote-access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-remote-access" })
}

################################################################################
# Kubernetes Add-ons
################################################################################

# AWS Load Balancer Controller
module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name = "${local.name}-aws-load-balancer-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.tags
}

resource "helm_release" "aws_load_balancer_controller" {
  depends_on = [module.eks.eks_managed_node_groups]

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"

  values = [
    yamlencode({
      clusterName = module.eks.cluster_name
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.aws_load_balancer_controller_irsa_role.iam_role_arn
        }
      }
      region = var.aws_region
      vpcId  = module.vpc.vpc_id
    })
  ]
}

# EBS CSI Driver
# module "ebs_csi_driver_irsa_role" {
#   source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   version = "~> 5.20"

#   role_name = "${local.name}-ebs-csi-driver"

#   attach_ebs_csi_policy = true

#   oidc_providers = {
#     ex = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
#     }
#   }

#   tags = local.tags
# }

# resource "aws_eks_addon" "ebs_csi_driver" {
#   cluster_name             = module.eks.cluster_name
#   addon_name               = "aws-ebs-csi-driver"
#   addon_version            = "v1.24.0-eksbuild.1"
#   service_account_role_arn = module.ebs_csi_driver_irsa_role.iam_role_arn

#   tags = local.tags
# }

# Create namespace for your application
resource "kubernetes_namespace" "app" {
  depends_on = [module.eks.eks_managed_node_groups]

  metadata {
    name = var.app_namespace

    labels = {
      name        = var.app_namespace
      environment = var.environment
    }
  }
}
# Backend ConfigMap with S3 bucket name
resource "kubernetes_config_map" "backend_config" {
  depends_on = [kubernetes_namespace.app]

  metadata {
    name      = "backend-config"
    namespace = var.app_namespace
  }

  data = {
    AWS_DEFAULT_REGION = var.aws_region
    S3_BUCKET_NAME     = aws_s3_bucket.qr_codes.bucket
  }
}

# Metrics Server for HPA
# resource "helm_release" "metrics_server" {
#   depends_on = [module.eks.eks_managed_node_groups]

#   name       = "metrics-server"
#   repository = "https://kubernetes-sigs.github.io/metrics-server/"
#   chart      = "metrics-server"
#   namespace  = "kube-system"
#   version    = "3.11.0"

#   values = [
#     yamlencode({
#       args = [
#         "--cert-dir=/tmp",
#         "--secure-port=4443",
#         "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
#         "--kubelet-use-node-status-port",
#         "--metric-resolution=15s"
#       ]
#       resources = {
#         requests = {
#           cpu    = "100m"
#           memory = "200Mi"
#         }
#       }
#     })
#   ]
# }


# Create namespace for monitoring (Prometheus/Grafana)
resource "kubernetes_namespace" "monitoring" {
  depends_on = [module.eks.eks_managed_node_groups]

  metadata {
    name = "monitoring"

    labels = {
      name        = "monitoring"
      environment = var.environment
    }
  }
}
################################################################################
# S3 Bucket and IAM Permissions for QR Code Application
################################################################################

# S3 bucket for storing QR codes
resource "aws_s3_bucket" "qr_codes" {
  bucket = "my-qr-project-bucket-${random_string.bucket_suffix.result}"

  tags = local.tags
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket public access configuration
resource "aws_s3_bucket_public_access_block" "qr_codes" {
  bucket = aws_s3_bucket.qr_codes.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket policy for public read access to QR codes
resource "aws_s3_bucket_policy" "qr_codes_public_read" {
  depends_on = [aws_s3_bucket_public_access_block.qr_codes]
  
  bucket = aws_s3_bucket.qr_codes.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.qr_codes.arn}/*"
      }
    ]
  })
}

# IAM policy for S3 access by EKS nodes
resource "aws_iam_policy" "s3_qr_access" {
  name        = "${local.name}-s3-qr-access"
  description = "S3 access policy for QR code application"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.qr_codes.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.qr_codes.arn
      }
    ]
  })

  tags = local.tags
}

# Attach S3 policy to EKS node group role
resource "aws_iam_role_policy_attachment" "s3_qr_access" {
  role       = module.eks.eks_managed_node_groups.main.iam_role_name
  policy_arn = aws_iam_policy.s3_qr_access.arn
}

# Note: Monitoring stack (Prometheus/Grafana) will be deployed via Ansible
# This keeps Terraform focused on infrastructure