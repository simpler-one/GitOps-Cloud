module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "gitops-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = aws_iam_openid_connect_provider.eks_oidc.arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  values = [
    yamlencode({
      clusterName = aws_eks_cluster.eks.name
      region      = "ap-south-1"       # 👈 CRITICAL FIX
      vpcId       = aws_vpc.vpc.id      # 👈 CRITICAL FIX
      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.iam_role_arn
        }
      }
    })
  ]

  # 👈 Prevents Helm deletion failures during terraform destroy
  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.private_nodes,
  ]

}

resource "helm_release" "argocd" {

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd" # Replace with your target chart (e.g., argo-rollouts, argo-workflows)
  version          = "7.7.0"   # Specify your desired chart version
  namespace        = "argocd"
  create_namespace = true

  # Attach values from a local YAML file
  values = [
    file("${path.module}/configs/argo-config.yaml")
  ]

}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.3" # match your desired chart version
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "crds.enabled"
    value = "true"
  }

  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.private_nodes,
  ]
}

resource "helm_release" "actions_runner_controller" {

  name             = "actions-runner-controller"
  repository       = "https://actions-runner-controller.github.io/actions-runner-controller"
  chart            = "actions-runner-controller"
  namespace        = "actions-runner-system"
  create_namespace = true
  wait             = true # equivalent to --wait

  # Attach your values YAML file here
  values = [
    file("${path.module}/configs/runner-config.yaml")
  ]

  # Equivalent to --set=authSecret.create=true and --set=authSecret.github_token=...
  set {
    name  = "authSecret.create"
    value = "true"
  }

  set_sensitive {
    name  = "authSecret.github_token"
    value = var.github_runner_token 
  }

  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.private_nodes,
  ]
}