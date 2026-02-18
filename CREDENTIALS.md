# Default Credentials - CloudLens OpenShift Visibility Lab

> **Change all passwords immediately after first login.**

## Keysight Products

| Product | URL | Username | Password |
|---------|-----|----------|----------|
| CloudLens Manager (CLMS) | `https://<clms_public_ip>` | `admin` | `Cl0udLens@dm!n` |
| Keysight Vision One (KVO) | `https://<kvo_public_ip>` | `admin` | `admin` |
| Virtual Packet Broker (vPB) | SSH only | `admin` | `ixia` |
| CyPerf Controller | `https://<cyperf_public_ip>` | `admin` | `CyPerf&Keysight#1` |

## OpenShift / ROSA

| Access | Command |
|--------|---------|
| Get cluster admin password | `rosa describe admin -c <cluster-name>` |
| OpenShift Console | `rosa describe cluster -c <cluster-name> \| grep console` |
| oc login | `oc login <api-url> --username cluster-admin --password <password>` |

## VM Access (SSH Key)

| VM | Username | Auth |
|----|----------|------|
| Ubuntu Workload | `ubuntu` | SSH key (key_pair_name) |
| RHEL Workload | `ec2-user` | SSH key |
| Linux Tool VM | `ubuntu` | SSH key |
| Windows Workload | `Administrator` | Decrypt: `terraform output -raw windows_password` |
| Windows Tool VM | `Administrator` | Decrypt: `terraform output -raw tool_windows_password` |

## Retrieve Credentials

```bash
# Get all URLs and IPs
terraform -chdir=terraform output

# Get cluster login command
terraform -chdir=terraform output -raw rosa_login_command

# Get ROSA admin password
rosa describe admin -c $(terraform -chdir=terraform output -raw rosa_cluster_name)
```
