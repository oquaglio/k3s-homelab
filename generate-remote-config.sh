#!/bin/bash
set -e

echo "========================================="
echo "Generate Remote K3s Config"
echo "========================================="
echo ""

# Get the local IP address
LOCAL_IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n1)

if [ -z "$LOCAL_IP" ]; then
    echo "Error: Could not determine local IP address"
    exit 1
fi

echo "Detected local IP: $LOCAL_IP"
echo ""

# Create configs directory
mkdir -p ~/k3s-homelab/configs

# Copy and modify the config
sudo cp /etc/rancher/k3s/k3s.yaml ~/k3s-homelab/configs/k3s-remote.yaml
sudo chown $USER:$USER ~/k3s-homelab/configs/k3s-remote.yaml

# Replace 127.0.0.1 with actual IP
sed -i "s/127.0.0.1/$LOCAL_IP/g" ~/k3s-homelab/configs/k3s-remote.yaml

echo "Remote config generated at: ~/k3s-homelab/configs/k3s-remote.yaml"
echo ""
echo "To use from your laptop:"
echo ""
echo "1. Copy the config:"
echo "   scp otto@$LOCAL_IP:~/k3s-homelab/configs/k3s-remote.yaml ~/.kube/config-homelab"
echo ""
echo "2. On your laptop, use it:"
echo "   export KUBECONFIG=~/.kube/config-homelab"
echo "   kubectl get nodes"
echo ""
echo "Or display the config to copy manually:"
cat ~/k3s-homelab/configs/k3s-remote.yaml
