resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "eks-pod-identity-agent"
}

# 1. The IAM Role
resource "aws_iam_role" "pod" {
  name = "${local.name}-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })
}

# 2. Attach AdministratorAccess to the Role
resource "aws_iam_role_policy_attachment" "admin_access" {
  role       = aws_iam_role.pod.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 3. Create Associations for both service accounts
resource "aws_eks_pod_identity_association" "main" {
  for_each = toset(["default", "external-dns"])

  cluster_name    = aws_eks_cluster.main.name
  namespace       = "default"
  service_account = each.value
  role_arn        = aws_iam_role.pod.arn
}

resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.name}-pod-role-for-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
      },
    ]
  })

  inline_policy {
    name = "cluster_autoscaler"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeScalingActivities",
            "ec2:DescribeImages",
            "ec2:DescribeInstanceTypes",
            "ec2:DescribeLaunchTemplateVersions",
            "ec2:GetInstanceTypesFromInstanceRequirements",
            "eks:DescribeNodegroup",
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup"
          ]
          Effect   = "Allow"
          Resource = "*"
        },
      ]
    })
  }

}

resource "aws_iam_role_policy_attachment" "cluster_access" {
  role       = aws_iam_role.cluster_autoscaler.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "default"
  service_account = "my-release-aws-cluster-autoscaler"
  role_arn        = aws_iam_role.cluster_autoscaler.arn
  depends_on = [
    aws_eks_addon.pod_identity
  ]
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  namespace  = "default"

  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"

  depends_on = [
    aws_eks_pod_identity_association.cluster_autoscaler
  ]

  set {
    name  = "autoDiscovery.clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "awsRegion"
    value = "us-east-1"
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }
}