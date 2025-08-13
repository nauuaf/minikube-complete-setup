#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Testing Start Script Syntax${NC}"
echo -e "${BLUE}========================================${NC}"

# Test bash syntax
echo -e "${YELLOW}Testing bash syntax...${NC}"
if bash -n start.sh; then
    echo -e "${GREEN}✅ Start script syntax is valid${NC}"
else
    echo -e "${RED}❌ Start script has syntax errors${NC}"
    exit 1
fi

# Test that all required files exist
echo -e "\n${YELLOW}Checking required files...${NC}"
required_files=(
    "config/config.env"
    "prereq-check.sh"
    "scripts/registry-auth.sh"
    "scripts/update-registry-refs.sh"
    "scripts/import-dashboards.sh"
    "scripts/health-checks.sh"
    "scripts/verify-deployment.sh"
    "stop.sh"
)

missing_files=0
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅ $file exists${NC}"
    else
        echo -e "${RED}❌ $file is missing${NC}"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -gt 0 ]; then
    echo -e "\n${RED}Missing $missing_files required files${NC}"
else
    echo -e "\n${GREEN}All required files present${NC}"
fi

# Check Docker
echo -e "\n${YELLOW}Checking Docker...${NC}"
if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Docker is running${NC}"
    
    # Check Docker configuration
    if docker info 2>/dev/null | grep -q "localhost:30500"; then
        echo -e "${GREEN}✅ Docker insecure registry configured${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker insecure registry not configured (will be fixed during start)${NC}"
    fi
else
    echo -e "${RED}❌ Docker is not running${NC}"
fi

# Check Minikube
echo -e "\n${YELLOW}Checking Minikube...${NC}"
if command -v minikube >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Minikube is installed${NC}"
    
    if minikube status >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Minikube is already running (will be restarted)${NC}"
    else
        echo -e "${GREEN}✅ Minikube is not running (ready to start)${NC}"
    fi
else
    echo -e "${RED}❌ Minikube is not installed${NC}"
fi

# Check kubectl
echo -e "\n${YELLOW}Checking kubectl...${NC}"
if command -v kubectl >/dev/null 2>&1; then
    echo -e "${GREEN}✅ kubectl is installed${NC}"
else
    echo -e "${RED}❌ kubectl is not installed${NC}"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}   Summary${NC}"
echo -e "${BLUE}========================================${NC}"

if [ $missing_files -eq 0 ]; then
    echo -e "${GREEN}Script is ready to run!${NC}"
    echo -e "\nTo start the platform, run:"
    echo -e "  ${YELLOW}./start.sh${NC}"
else
    echo -e "${RED}Please fix the missing files before running start.sh${NC}"
fi