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