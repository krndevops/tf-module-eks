locals {
  name = "${var.env}-${var.project_name}-${var.component}"
  issuer = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
