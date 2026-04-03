terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.17.0"
    }
  }
}
resource "aws_iam_role" "main" {
  name = "${local.name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = ["sts:AssumeRole"]
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "eks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "main-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "main-eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role" "node" {
  name = "${local.name}-node-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_policy" "node-extra-policy" {
  name        = "${local.name}-node-role-extra-policy"
  path        = "/"
  description = "${local.name}-node-role-extra-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "ssm:DescribeParameters",
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath",
          "ssm:GetParameters",
          "ssm:GetParameter",
          "kms:Decrypt"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "main-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "main-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "main-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "extra-policy-attach" {
  policy_arn = aws_iam_policy.node-extra-policy.arn
  role       = aws_iam_role.node.name
}

resource "aws_eks_cluster" "main" {
  name     = "${var.env}-eks"
  role_arn = aws_iam_role.main.arn

  vpc_config {
    subnet_ids = var.subnet_ids
  }

}

resource "aws_launch_template" "main" {
  for_each        = var.node_groups
  name_prefix     = "${local.name}-${each.key}-ng"

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name}-${each.key}-ng"
    }
  }
}

resource "aws_eks_node_group" "main" {
  for_each        = var.node_groups
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name}-${each.key}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  instance_types  = each.value["instance_types"]
  capacity_type   = each.value["capacity_type"]

  launch_template {
    version = "$Latest"
    id      = lookup(lookup(aws_launch_template.main, each.key, null), "id", null)
  }

  scaling_config {
    desired_size = each.value["size"]
    max_size     = each.value["size"] + 5
    min_size     = each.value["size"]

  }
  tags = {
    name = "${local.name}-${each.key}-ng"
  }

}
