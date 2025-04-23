provider "aws" {
  region = "us-east-1"
}

# ------------------------
# IAM Role for EKS Control Plane
# ------------------------
resource "aws_iam_role" "eks_master" {
  name = "veera-eks-master129"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_master.name
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.eks_master.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_master.name
}

# ------------------------
# IAM Role for Worker Nodes
# ------------------------
resource "aws_iam_role" "eks_worker" {
  name = "veera-eks-worker1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "autoscaler" {
  name = "veera-eks-autoscaler-policy19"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeTags",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "worker_eks_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_role_policy_attachment" "worker_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_role_policy_attachment" "worker_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_role_policy_attachment" "worker_ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_role_policy_attachment" "worker_s3_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_role_policy_attachment" "worker_autoscaler" {
  policy_arn = aws_iam_policy.autoscaler.arn
  role       = aws_iam_role.eks_worker.name
}

resource "aws_iam_instance_profile" "worker" {
  depends_on = [aws_iam_role.eks_worker]
  name       = "veera-eks-worker-profile1"
  role       = aws_iam_role.eks_worker.name
}

# ------------------------
# VPC, Subnets, SG Data Sources
# ------------------------
data "aws_vpc" "main" {
  tags = {
    Name = "Jumphost-vpc"
  }
}

data "aws_subnet" "subnet_1" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = ["Jumphost-subnet1"]
  }
}

data "aws_subnet" "subnet_2" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = ["Jumphost-subnet2"]
  }
}

data "aws_security_group" "selected" {
  vpc_id = data.aws_vpc.main.id
  filter {
    name   = "tag:Name"
    values = ["Jumphost-sg"]
  }
}

# ------------------------
# EKS Cluster
# ------------------------
resource "aws_eks_cluster" "eks" {
  name     = "project-eks"
  role_arn = aws_iam_role.eks_master.arn
  version  = "1.29"  # Explicit version

  vpc_config {
    subnet_ids = [
      data.aws_subnet.subnet_1.id,
      data.aws_subnet.subnet_2.id
    ]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = {
    Name = "MyEKS"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy,
    aws_iam_role_policy_attachment.eks_vpc_controller
  ]
}

# ------------------------
# EKS Managed Node Group
# ------------------------
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "project-node-group"
  node_role_arn   = aws_iam_role.eks_worker.arn
  subnet_ids      = [
    data.aws_subnet.subnet_1.id,
    data.aws_subnet.subnet_2.id
  ]
  capacity_type   = "ON_DEMAND"
  disk_size       = 20
  instance_types  = ["t2.small"]

  remote_access {
    ec2_ssh_key               = "n.virgina" # Replace with your real EC2 key name
    source_security_group_ids = [data.aws_security_group.selected.id]
  }

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    env = "dev"
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_eks_policy,
    aws_iam_role_policy_attachment.worker_cni_policy,
    aws_iam_role_policy_attachment.worker_ecr_readonly,
    aws_iam_instance_profile.worker
  ]
}
