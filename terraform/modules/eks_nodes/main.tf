# -----------------------------------------------------------------------------
# Security Group
# Allows ingress from the load balancer.
# This security group will be added to cluster nodes.
# -----------------------------------------------------------------------------
resource "aws_security_group" "load_balancer_ingress" {
  name        = "${var.cluster_name}-AllowIngressFromLoadBalancer"
  description = "Allows incoming traffic from a load balancer."
  vpc_id      = var.vpc_id
  ingress {
    description     = "Allow all traffic form load balancer"
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [var.load_balancer_security_group_id]
  }
}

# -----------------------------------------------------------------------------
# EKS Node Group
# Multi-AZ
# -----------------------------------------------------------------------------
resource "aws_eks_node_group" "multi_az_node_group" {
  cluster_name         = var.cluster_name
  node_role_arn        = var.cluster_node_role_arn
  force_update_version = true
  scaling_config {
    desired_size = var.eks_cluster_worker_nodes_desired_size
    max_size     = var.eks_cluster_worker_nodes_max_size
    min_size     = var.eks_cluster_worker_nodes_min_size
  }
  lifecycle {
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }
  subnet_ids = [
    var.private_subnet_1a_id,
    var.private_subnet_1b_id
  ]
  ami_type        = "CUSTOM"
  node_group_name = "eks-${var.cluster_name}-multi-az-node-group"
  launch_template {
    id      = aws_launch_template.eks_worker_node_template.id
    version = aws_launch_template.eks_worker_node_template.default_version
  }
}

# -----------------------------------------------------------------------------
# EC2 Launch Template
# -----------------------------------------------------------------------------
resource "aws_launch_template" "eks_worker_node_template" {
  name = "${var.cluster_name}-eks-worker-node-template"
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 100 # change 20 to 100 due to storage errors
      iops                  = 3000
      throughput            = 125
      delete_on_termination = true
      encrypted             = true
      kms_key_id            = "arn:aws:kms:${var.region}:${var.account_number}:key/${var.ebs_kms_key_id}"
    }
  }
  credit_specification {
    cpu_credits = "standard"
  }
  ebs_optimized = true
  image_id      = var.worker_node_base_ami
  instance_type = var.eks_cluster_worker_node_instance_type
  monitoring {
    enabled = false
  }
  vpc_security_group_ids = [
    var.base_access_security_group_id,
    var.cluster_security_group_id,
    aws_security_group.load_balancer_ingress.id
  ]
  tag_specifications {
    resource_type = "instance"
    tags = {
      "Name" : "eks-${var.cluster_name}-node",
      "8872_NWS_Project" : var.nws_project_tag,
      "8872_NWS_PERSISTENCE_TYPE" : "TRANSIENT",
      "8872_NWS_POC" : var.project_contacts
    }
  }
  tag_specifications {
    resource_type = "volume"
    tags = {
      "Name" : "eks-${var.cluster_name}-node",
      "8872_NWS_Project" : var.nws_project_tag
    }
  }
  user_data = base64encode(templatefile("${path.module}/user_data.tftpl", {
    cluster_name        = var.cluster_name,
    cluster_certificate = base64decode(var.cluster_certificate_authority_data),
    api_server_url      = var.cluster_endpoint
  }))
  update_default_version = true
}