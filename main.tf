# structure 

resource "aws_vpc" "vpc"{
  
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "terraform-gitops-eks"
  }

}

resource "aws_subnet" "subnets"{
  
  for_each = var.subnet_config
  
  vpc_id = aws_vpc.vpc.id
  cidr_block = each.value.cidr
  availability_zone = each.value.az

  tags = merge(
    {
        Name = "terraform-gitops-eks"
        "kubernetes.io/cluster/pulseops-cluster" = "shared"
    },
    each.value.type == "public" ? { "kubernetes.io/role/elb" = "1" } : {},
    each.value.type == "private" ? { "kubernetes.io/role/internal-elb" = "1" } : {}, 
  )

}

resource "aws_internet_gateway" "igw"{
    
    vpc_id = aws_vpc.vpc.id
    tags = {
        Name = "terraform-gitops-eks"
    }

}

## route tables configurations

resource "aws_route_table" "public_1_rt"{

    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "10.0.0.0/16"
        gateway_id = "local"
    }

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    } 

    tags = {
        Name = "terraform-gitops-eks"
    }

}

resource "aws_route_table_association" "public_1_a"{

    subnet_id = aws_subnet.subnets["public_1"].id
    route_table_id = aws_route_table.public_1_rt.id

}

resource "aws_route_table" "public_2_rt"{

    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "10.0.0.0/16"
        gateway_id = "local"
    }

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    } 

    tags = {
        Name = "terraform-gitops-eks"
    }

}

resource "aws_route_table_association" "public_2_a"{

    subnet_id = aws_subnet.subnets["public_2"].id
    route_table_id = aws_route_table.public_2_rt.id

}

resource "aws_route_table" "private_1_rt"{

    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "10.0.0.0/16"
        gateway_id = "local"
    }

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "RNAT"
    }

    tags = {
        Name = "terraform-gitops-eks"
    }

}

resource "aws_route_table_association" "private_1_a"{

    subnet_id = aws_subnet.subnets["private_1"].id
    route_table_id = aws_route_table.private_1_rt.id

}

resource "aws_route_table" "private_2_rt"{

    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "10.0.0.0/16"
        gateway_id = "local"
    }

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "RNAT"
    }

    tags = {
        Name = "terraform-gitops-eks"
    }

}

resource "aws_route_table_association" "private_2_a"{

    subnet_id = aws_subnet.subnets["private_2"].id
    route_table_id = aws_route_table.private_2_rt.id

}

# routing componenets (RNAT, Bastion)

resource "aws_nat_gateway" "rnat" {

  vpc_id            = aws_vpc.vpc.id
  availability_mode = "regional"

}

resource "aws_security_group" "bastion_sg" {

    vpc_id = aws_vpc.vpc.id

    ingress{

        description = "user connection to instance"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]

    }

    egress{
        
        
        description = "connection to the private subnet/resources from bastion"
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]

    }

    tags = {
        Name = "terraform-gitops-eks"
    }

}

resource "aws_instance" "bastion" {

  ami                         = "ami-0931307dcdc2a28c9" # Amazon Linux 2023 (Verify for your region)
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.subnets["public_1"].id # Assumes a public subnet resource
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = "linuxkey" # Assumes you have created a Key Pair
  associate_public_ip_address = true

  tags = {
    Name = "terraform-gitops-eks"
  }

}

# EKS cluster and node group setup (role, policy, creation) 

## Control Plane
resource "aws_iam_role" "eks_cluster_role" {
  name = "gitops-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "terraform-gitops-eks"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

resource "aws_eks_cluster" "eks" {
    
  name     = "gitops-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.subnets["private_1"].id,
      aws_subnet.subnets["private_2"].id
    ]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "terraform-gitops-eks"
  }

}

## Node Group

resource "aws_iam_role" "eks_node_group_role" {

  name = "gitops-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "terraform-gitops-eks"
  }

}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group_role.name

}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group_role.name

}

# resource "aws_iam_role_policy_attachment" "eks_container_registry_read_only" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#   role       = aws_iam_role.eks_node_group_role.name
# }

# EBS CSI Driver Policy for Node Group (Allows disk attachments for Postgres PV)
# resource "aws_iam_role_policy_attachment" "eks_ebs_csi_policy" {
  
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
#   role       = aws_iam_role.eks_node_group_role.name

# }

resource "aws_eks_node_group" "private_nodes" {
  
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "gitops-private-node-group"
  node_role_arn   = aws_iam_role.eks_node_group_role.arn

  subnet_ids = [
    aws_subnet.subnets["private_1"].id,
    aws_subnet.subnets["private_2"].id
  ]

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    # aws_iam_role_policy_attachment.eks_container_registry_read_only,
    # aws_iam_role_policy_attachment.eks_ebs_csi_policy
  ]

  tags = {
    Name = "terraform-gitops-eks"
  }

}

# data section

# / this generates cluster's bearer token which can be passed on to 
# / resources (kubectl_manifest, helm_release(actually their providers)) for linkage.
data "aws_eks_cluster_auth" "cluster" {

  name = aws_eks_cluster.eks.name

}


data "tls_certificate" "eks_tls" {

  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer

}

# OIDC setup

resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_tls.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer

  tags = {
    Name = "terraform-gitops-eks"
  }
}

# Access of kubectl by GHA, to delete the argo components

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.eks.name
  principal_arn = var.github_actions_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = aws_eks_cluster.eks.name
  principal_arn = aws_eks_access_entry.github_actions.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}