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



resource "aws_iam_role" "external_dns" {
  name = "${local.name}-pod-role-for-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",

        Principal = {
          Federated = "arn:aws:iam::367241114876:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}"
        },

        Condition = {
          StringEquals = {
            "oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}:aud" = "sts.amazonaws.com",
            "oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}:sub" = "system:serviceaccount:default:external-dns"
          }
        }
      }
    ]
  })

  inline_policy {
    name = "parameter-store"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Sid    = "Route53Access",
          Effect = "Allow",

          Action = [
            "route53:*"
          ],

          Resource = "*"
        }
      ]
    })
  }
}


resource "aws_iam_role" "cluster_autoscaler" {
  name = "${local.name}-pod-role-for-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",

        Principal = {
          Federated = "arn:aws:iam::367241114876:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}"
        },

        Condition = {
          StringEquals = {
            "oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}:aud" = "sts.amazonaws.com",
            "oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}:sub" = "system:serviceaccount:default:my-release-aws-cluster-autoscaler"
          }
        }
      }
    ]
  })

  inline_policy {
    name = "cluster-autoscaler-policy"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Sid    = "Route53Access",
          Effect = "Allow",

          Action = [
            "autoscaling:DescribeAutoScalingGroups",
            "autoscaling:DescribeAutoScalingInstances",
            "autoscaling:DescribeLaunchConfigurations",
            "autoscaling:DescribeScalingActivities",
            "autoscaling:SetDesiredCapacity",
            "autoscaling:TerminateInstanceInAutoScalingGroup",
            "eks:DescribeNodegroup",
            "ec2:DescribeLaunchTemplateVersions"
          ],

          Resource = "*"
        }
      ]
    })
  }
}

variable "components" {
  default = ["frontend", "cart", "catalogue", "user", "shipping", "payment"]
}

resource "aws_iam_role" "app_ssm" {
  count = length(var.components)
  name = "${local.name}-pod-role-for-${var.components[count.index]}-ssm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sts:AssumeRoleWithWebIdentity",

        Principal = {
          Federated = "arn:aws:iam::367241114876:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}"
        },

        Condition = {
          StringEquals = {
            "oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}:aud" = "sts.amazonaws.com",
            "oidc.eks.us-east-1.amazonaws.com/id/${local.cluster_issuer_id}:sub" = "system:serviceaccount:default:${var.components[count.index]}"
          }
        }
      }
    ]
  })

  inline_policy {
    name = "${var.components[count.index]}-parameter-store"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Sid    = "Route53Access",
          Effect = "Allow",

          Action = [
            "ssm:DescribeParameters",
            "ssm:GetParameterHistory",
            "ssm:GetParametersByPath",
            "ssm:GetParameters",
            "ssm:GetParameter",
            "kms:Decrypt"
          ],

          Resource = "*"
        }
      ]
    })
  }
}