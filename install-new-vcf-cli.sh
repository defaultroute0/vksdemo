#!/bin/bash
# install_vcf_cli_clean.sh
# Installs Broadcom VCF CLI for Ubuntu AMD64 with safety checks and pauses
#holuser
#VMware123!VMware123!
##
#su - 
#VMware123!VMware123!
##
## chmo d + x this file guys, and make sure we are using ELF 64-bit LSB executable x86_64 version 

# Helper function to pause and show message
pause() {
    echo ""
    echo "==> Waiting for $1 seconds..."
    sleep $1
    echo ""
}

echo "=== Checking OS version ==="
lsb_release -a
pause 2

echo "=== Checking CPU info ==="
lscpu
pause 2

echo "=== Removing any old /usr/local/bin/vcf binary (if exists) ==="
sudo rm -f /usr/local/bin/vcf
pause 1

echo "=== Updating and upgrading system packages ==="
sudo apt-get update && sudo apt-get upgrade -y
pause 3

echo "=== Installing curl via snap (fallback to apt if snap fails) ==="
if ! sudo snap install curl; then
    echo "Snap failed, installing curl via apt..."
    sudo apt install -y curl
fi
pause 2

echo "=== Installing required certificates and GPG ==="
sudo apt install -y ca-certificates gpg
pause 2

echo "=== Creating keyrings directory ==="
sudo mkdir -p /etc/apt/keyrings
pause 1

echo "=== Adding Broadcom GPG keys ==="
curl -fsSL https://packages.broadcom.com/artifactory/vcfcli-debian/tools/keys/BROADCOM-PACKAGING-GPG-RSA-KEY.pub \
    | sudo tee /etc/apt/keyrings/broadcom-key.pub >/dev/null

curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/PackagesKey/public \
    | gpg --dearmor | sudo tee /etc/apt/keyrings/vcf-archive-keyring.gpg >/dev/null
pause 2

echo "=== Adding Broadcom repository ==="
echo "deb [signed-by=/etc/apt/keyrings/vcf-archive-keyring.gpg] https://packages.broadcom.com/artifactory/vcfcli-debian noble main" \
    | sudo tee /etc/apt/sources.list.d/vcf.list
pause 1

echo "=== Updating apt sources ==="
sudo apt update
pause 2

echo "=== Installing VCF CLI ==="
sudo apt install -y vcf-cli
pause 2

echo "=== Refreshing terminal environment so new vcf command is available ==="
hash -r
pause 1

echo "=== Verifying VCF CLI binary architecture ==="
file "$(which vcf)"
pause 2

echo "=== Displaying VCF CLI help ==="
vcf -h

echo ""
echo "=== Installation complete! ==="
echo "VCF CLI should now be ready to use."
