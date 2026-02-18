# ============================================================================
# WORKLOAD VMs - Ubuntu and Windows tapped traffic sources
# ============================================================================

resource "aws_instance" "tapped_ubuntu_1" {
  count                       = var.ubuntu_workload_enabled ? 1 : 0
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.ubuntu_instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.management.id
  vpc_security_group_ids      = [aws_security_group.workload.id]
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y iperf3 curl wget net-tools nmap tcpdump
    echo "Ubuntu workload VM ready" > /tmp/ready
  EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
    tags                  = merge(local.common_tags, { Name = "${local.tapped_1_name}-root" })
  }

  tags = merge(local.common_tags, { Name = local.tapped_1_name, Role = "Workload" })
}

resource "aws_instance" "tapped_windows" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.windows_instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.management.id
  vpc_security_group_ids      = [aws_security_group.workload.id]
  associate_public_ip_address = true
  get_password_data           = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
    tags                  = merge(local.common_tags, { Name = "${local.windows_name}-root" })
  }

  tags = merge(local.common_tags, { Name = local.windows_name, Role = "Workload" })
}

resource "aws_instance" "tapped_rhel" {
  count                       = var.rhel_enabled ? 1 : 0
  ami                         = data.aws_ami.rhel.id
  instance_type               = var.rhel_instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.management.id
  vpc_security_group_ids      = [aws_security_group.workload.id]
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y iperf3 curl wget net-tools nmap tcpdump
    echo "RHEL workload VM ready" > /tmp/ready
  EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
    tags                  = merge(local.common_tags, { Name = "${local.rhel_name}-root" })
  }

  tags = merge(local.common_tags, { Name = local.rhel_name, Role = "Workload" })
}
