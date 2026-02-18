# ============================================================================
# ELASTIC IPs (conditional on use_elastic_ips)
# ============================================================================

resource "aws_eip" "clms" {
  count    = var.use_elastic_ips ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.clms.id
  tags     = merge(local.common_tags, { Name = "${local.clms_name}-eip" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "kvo" {
  count    = var.use_elastic_ips ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.kvo.id
  tags     = merge(local.common_tags, { Name = "${local.kvo_name}-eip" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "vpb" {
  count                     = var.vpb_enabled && var.use_elastic_ips ? 1 : 0
  domain                    = "vpc"
  network_interface         = aws_network_interface.vpb_management[0].id
  associate_with_private_ip = aws_network_interface.vpb_management[0].private_ip
  tags                      = merge(local.common_tags, { Name = "${local.vpb_name}-eip" })
  depends_on                = [aws_internet_gateway.main]
}

resource "aws_eip" "tapped_ubuntu_1" {
  count    = var.ubuntu_workload_enabled && var.use_elastic_ips ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.tapped_ubuntu_1[0].id
  tags     = merge(local.common_tags, { Name = "${local.tapped_1_name}-eip" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "tapped_windows" {
  count    = var.use_elastic_ips ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.tapped_windows.id
  tags     = merge(local.common_tags, { Name = "${local.windows_name}-eip" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "tapped_rhel" {
  count    = var.rhel_enabled && var.use_elastic_ips ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.tapped_rhel[0].id
  tags     = merge(local.common_tags, { Name = "${local.rhel_name}-eip" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "tool" {
  count    = var.use_elastic_ips ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.tool.id
  tags     = merge(local.common_tags, { Name = "${local.tool_name}-eip" })
  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "tool_windows" {
  count    = var.use_elastic_ips ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.tool_windows.id
  tags     = merge(local.common_tags, { Name = "${local.tool_windows_name}-eip" })
  depends_on = [aws_internet_gateway.main]
}
