#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab - Full Start"
echo "========================================="
echo ""

# Run setup first
./setup.sh

# Source secrets.sh so environment variables are available to deploy.sh
source ./secrets.sh

# Deploy applications (will use PORTAINER_PASSWORD from secrets.sh)
./deploy.sh
