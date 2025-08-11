#!/bin/bash

# Ubuntu/Linux Prerequisites Check for SRE Assignment
# This script is optimized for Ubuntu and similar Linux distributions

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Checking Ubuntu/Linux System Requirements...${NC}"

# Check OS
OS=$(uname -s)
echo -e "${YELLOW}Operating System: $OS${NC}"

if [[ "$OS" != "Linux" ]]; then
    echo -e "${RED}❌ This project is optimized for Ubuntu/Linux distributions${NC}"
    echo -e "${YELLOW}For macOS, consider using Docker Desktop or deploy on a Linux VM${NC}"
fi

# Check RAM (Linux-optimized)
TOTAL_RAM=$(free -g | awk 'NR==2{print $2}')
if [[ -z "$TOTAL_RAM" || "$TOTAL_RAM" -eq 0 ]]; then
    # Fallback for different free output formats
    TOTAL_RAM=$(free -h | awk 'NR==2{print $2}' | sed 's/Gi//' | sed 's/G//')
fi

echo -e "Total RAM: ${TOTAL_RAM}GB"
# Use portable comparison (fallback if bc is not available)
if command -v bc &> /dev/null; then
    RAM_CHECK=$(echo "$TOTAL_RAM < 8" | bc -l)
else
    # Fallback: basic integer comparison
    RAM_INT=${TOTAL_RAM%.*}  # Remove decimal part
    if [[ $RAM_INT -lt 8 ]]; then
        RAM_CHECK=1
    else
        RAM_CHECK=0
    fi
fi

if [[ $RAM_CHECK == "1" ]]; then
    echo -e "${RED}⚠️  Warning: Less than 8GB RAM. Minimum 8GB required.${NC}"
    exit 1
else
    echo -e "${GREEN}✓ RAM check passed${NC}"
fi

# Check CPU cores
CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu)
echo -e "CPU Cores: $CORES"
if [[ $CORES -lt 2 ]]; then
    echo -e "${RED}⚠️  Warning: Less than 2 CPU cores${NC}"
    exit 1
else
    echo -e "${GREEN}✓ CPU check passed${NC}"
fi

# Check disk space (Linux-optimized)
DISK_AVAIL=$(df -BG . 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ -z "$DISK_AVAIL" ]]; then
    # Fallback for different df formats
    DISK_AVAIL=$(df -h . | awk 'NR==2 {print $4}' | sed 's/G.*//' | sed 's/[^0-9]//g')
fi
echo -e "Available Disk: ${DISK_AVAIL}GB"
if [[ $DISK_AVAIL -lt 20 ]]; then
    echo -e "${RED}⚠️  Warning: Less than 20GB disk space${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Disk space check passed${NC}"
fi

# Check required tools
echo -e "\n${YELLOW}Checking required tools...${NC}"
REQUIRED_TOOLS=("docker" "minikube" "kubectl" "helm" "jq" "curl")
OPTIONAL_TOOLS=("bc" "wget" "sed" "awk")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        echo -e "${GREEN}✓ $tool is installed${NC}"
        # Check versions for known compatibility issues
        case $tool in
            "docker")
                DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
                if [[ $(echo "$DOCKER_VERSION < 20.0" | bc -l 2>/dev/null || echo "0") == "1" ]]; then
                    echo -e "${YELLOW}  ⚠️  Docker version $DOCKER_VERSION detected. Recommend 20.0+${NC}"
                fi
                ;;
            "minikube")
                MINIKUBE_VERSION=$(minikube version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
                echo -e "${GREEN}  Version: $MINIKUBE_VERSION${NC}"
                ;;
        esac
    else
        echo -e "${RED}✗ $tool is not installed${NC}"
        echo "Please install $tool before continuing"
        case $tool in
            "docker")
                echo "  macOS: brew install --cask docker"
                echo "  Linux: curl -fsSL https://get.docker.com | sh"
                ;;
            "minikube")
                echo "  macOS: brew install minikube"
                echo "  Linux: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
                ;;
            "kubectl")
                echo "  macOS: brew install kubectl"
                echo "  Linux: curl -LO https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                ;;
        esac
        exit 1
    fi
done

# Check optional tools with fallbacks
echo -e "\n${YELLOW}Checking optional tools...${NC}"
for tool in "${OPTIONAL_TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        echo -e "${GREEN}✓ $tool is available${NC}"
    else
        echo -e "${YELLOW}⚠️  $tool not found (fallback will be used)${NC}"
    fi
done

# Check if running in WSL (Windows Subsystem for Linux)
if grep -q microsoft /proc/version 2>/dev/null; then
    echo -e "${YELLOW}WSL detected - ensuring Docker Desktop integration${NC}"
    if ! docker info &> /dev/null; then
        echo -e "${RED}Docker Desktop not running or WSL integration not enabled${NC}"
        echo "Please start Docker Desktop and enable WSL integration"
        exit 1
    fi
fi

echo -e "\n${GREEN}✅ All prerequisites met!${NC}"