#!/bin/bash
set -e

echo "========================================="
echo "K3s Homelab - Full Start"
echo "========================================="
echo ""

# Run all setup steps in order
./setup.sh && ./secrets.sh && ./deploy.sh
