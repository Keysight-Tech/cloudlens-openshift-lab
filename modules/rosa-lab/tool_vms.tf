# ============================================================================
# TOOL VMs - Traffic capture and analysis
# ============================================================================

resource "aws_instance" "tool" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.tool_linux_instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.egress.id
  vpc_security_group_ids      = [aws_security_group.tool.id]
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y tcpdump tshark iperf3 curl wget net-tools nmap wireshark-common
    # Allow non-root users to capture packets
    echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections
    dpkg-reconfigure -f noninteractive wireshark-common
    usermod -aG wireshark ubuntu
    echo "Linux tool VM ready" > /tmp/ready
  EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    delete_on_termination = true
    encrypted             = true
    tags                  = merge(local.common_tags, { Name = "${local.tool_name}-root" })
  }

  tags = merge(local.common_tags, { Name = local.tool_name, Role = "Tool" })
}

resource "aws_instance" "tool_windows" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.tool_windows_instance_type
  key_name                    = var.key_pair_name
  subnet_id                   = aws_subnet.egress.id
  vpc_security_group_ids      = [aws_security_group.tool.id]
  associate_public_ip_address = true
  get_password_data           = true

  user_data = base64encode(<<-EOF
    <powershell>
    # Install Wireshark and Npcap silently
    $wiresharkUrl = "https://2.na.dl.wireshark.org/win64/Wireshark-latest-x64.exe"
    $wiresharkPath = "C:\\Windows\\Temp\\wireshark.exe"
    Invoke-WebRequest -Uri $wiresharkUrl -OutFile $wiresharkPath
    Start-Process -FilePath $wiresharkPath -ArgumentList "/S" -Wait
    Write-Host "Windows tool VM ready"
    </powershell>
  EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 60
    delete_on_termination = true
    encrypted             = true
    tags                  = merge(local.common_tags, { Name = "${local.tool_windows_name}-root" })
  }

  tags = merge(local.common_tags, { Name = local.tool_windows_name, Role = "Tool" })
}
