#!/bin/bash
set -uo pipefail

# Quick Start Script - Bypasses preflight and runs complete setup
# Use this if preflight-fixes.sh fails due to missing dependencies

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                    Quick Start Setup                        ║
║       Bypassing preflight checks for fresh machines         ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo -e "${YELLOW}This script will run the complete setup without preflight checks${NC}"
echo -e "${YELLOW}Use this if preflight-fixes.sh failed due to missing dependencies${NC}"
echo ""

if ! command -v curl &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} curl is required but not installed"
    echo ""
    echo "Please install curl first:"
    echo "  Ubuntu/Debian: sudo apt update && sudo apt install -y curl"
    echo "  RHEL/CentOS:   sudo yum install -y curl"
    echo "  Fedora:        sudo dnf install -y curl"
    exit 1
fi

read -p "Continue with complete setup? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled"
    exit 0
fi

# Make sure the complete setup script exists and is executable
if [ ! -f "complete-setup.sh" ]; then
    echo -e "${RED}[ERROR]${NC} complete-setup.sh not found in current directory"
    echo "Please run this script from the project root directory"
    exit 1
fi

chmod +x complete-setup.sh

echo -e "${BLUE}[INFO]${NC} Running complete setup..."
exec ./complete-setup.sh