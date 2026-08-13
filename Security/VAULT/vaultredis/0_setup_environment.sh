#!/bin/bash
# 0_setup_environment.sh

# Step 1: Update system packages
sudo apt update -y

# Step 2: Install MySQL, Python, and pip
sudo apt install -y mysql-server python3 python3-pip

# Step 3: Install Python venv if not available
sudo apt install -y python3.12-venv

# Step 4: Create and activate virtual environment
python3 -m venv myenv
source myenv/bin/activate

# Step 5: Install required Python packages
pip install redis mysql-connector-python
pip install azure-identity azure-mgmt-resource
pip install azure-keyvault-secrets

# Optional repeat (ensures latest versions)
pip install azure-identity azure-keyvault-secrets

echo "✅ Environment setup complete!"
