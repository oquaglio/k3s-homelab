#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab Bootstrap Script"
echo "========================================="
echo ""
echo "This script will run both install.sh and setup.sh"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo -e "${RED}Please do not run as root (don't use sudo)${NC}"
   exit 1
fi

# Run install script
if [ -f "./install.sh" ]; then
    echo -e "${YELLOW}Running installation...${NC}"
    ./install.sh
else
    echo -e "${RED}Error: install.sh not found${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Waiting for K3s to stabilize...${NC}"
sleep 5

# Run setup script
if [ -f "./setup.sh" ]; then
    echo -e "${YELLOW}Running setup...${NC}"
    ./setup.sh
else
    echo -e "${RED}Error: setup.sh not found${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Bootstrap complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Your K3s homelab is ready!"
echo ""
echo "Next steps:"
echo "1. Create your secrets: cp secrets.sh.example secrets.sh && vi secrets.sh"
echo "2. Run secrets script: ./secrets.sh"
echo "3. Deploy applications: ./deploy.sh"
echo ""
echo "To access from remote machines:"
echo "1. Run: ./generate-remote-config.sh"
echo "2. Copy the generated config to your laptop"