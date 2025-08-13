# Complete SRE Assignment Setup Guide

## One-Command Setup (Recommended)

For a completely fresh machine, run:

```bash
./complete-setup.sh
```

This script will:
- ✅ Detect your OS (Ubuntu, CentOS, RHEL, Fedora)
- ✅ Install all required packages (Docker, kubectl, Minikube, Helm)
- ✅ Configure Docker for private registry
- ✅ Set up all project configurations
- ✅ Run the full deployment with user confirmations

## What Gets Installed

### System Packages
- `curl`, `wget`, `jq` - Network tools
- `net-tools` - For netstat command
- `bc` - Calculator for version comparisons
- `apache2-utils`/`httpd-tools` - For htpasswd

### Kubernetes Tools
- **Docker CE** - Container runtime
- **kubectl** - Kubernetes CLI
- **Minikube** - Local Kubernetes cluster
- **Helm** - Kubernetes package manager (optional)

## Step-by-Step Process

The `complete-setup.sh` script follows this process:

1. **System Check** - Verifies OS, RAM (8GB+), CPU (2+ cores), disk (20GB+)
2. **Network Test** - Checks connectivity to required sites
3. **Package Installation** - Installs missing system packages
4. **Docker Setup** - Installs Docker and configures insecure registries
5. **Kubernetes Tools** - Installs kubectl and Minikube
6. **Project Configuration** - Sets up config files and permissions
7. **Deployment** - Runs the enhanced deployment script

## User Confirmations

The script will ask for confirmation before:
- Installing system packages
- Installing Docker
- Restarting Docker daemon
- Installing kubectl/Minikube
- Installing Helm (optional)
- Cleaning existing Minikube clusters
- Running the deployment

## Alternative Options

### If you prefer manual control:

```bash
# 1. Install prerequisites only
./scripts/preflight-fixes.sh

# 2. Run standard deployment
./start.sh

# 3. Or run enhanced deployment
./start-fresh.sh
```

### For existing setups:

```bash
# Clean start (removes existing cluster)
CLEAN_START=true ./start-fresh.sh

# Health checks only
./scripts/health-checks.sh

# Verify deployment
./scripts/verify-deployment.sh
```

## Expected Timeline

- **Fresh Ubuntu VM**: ~20-30 minutes (including downloads)
- **Existing system with Docker**: ~15-20 minutes
- **Just deployment** (tools already installed): ~10-15 minutes

## Troubleshooting

### If the script fails:
```bash
# Check what's running
kubectl get pods --all-namespaces

# View logs
kubectl logs -l app=<service-name> -n production

# Run health checks
./scripts/health-checks.sh
```

### Common issues:
- **Docker permission denied**: Logout/login after installation
- **Port conflicts**: Check `netstat -tlnp | grep :<port>`
- **Low memory**: Reduce Minikube memory in `config/config.env`
- **Network issues**: Check firewall and internet connectivity

## Access Information

After successful deployment:

- **Frontend**: http://YOUR_IP:30004
- **Grafana**: http://YOUR_IP:30030 (admin/admin123)
- **Prometheus**: http://YOUR_IP:30090
- **Registry**: http://YOUR_IP:30500

## Support

If you encounter issues:

1. Run `./scripts/health-checks.sh` for detailed status
2. Check `kubectl get events --all-namespaces` for errors
3. View service logs with `kubectl logs -l app=<service> -n production`

The enhanced scripts provide detailed error messages and recovery suggestions.