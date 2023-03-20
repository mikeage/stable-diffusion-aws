#!/bin/sh

set -e

CUDA_VERSION="12.1.0"
CUDA_FULL_VERSION="12.1.0_530.30.02"

sudo apt update
# sudo apt upgrade -y
sudo apt install git python3-venv build-essential net-tools linux-headers-cloud-amd64 -y

cat <<EOF | sudo tee /usr/lib/systemd/system/instance-storage.service
[Unit]
Description=Format and mount ephemeral storage
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/sbin/mkfs.ext4 /dev/nvme1n1
ExecStart=/usr/bin/mkdir -p /mnt/ephemeral
ExecStart=/usr/bin/mount /dev/nvme1n1 /mnt/ephemeral
ExecStart=/usr/bin/chmod 777 /mnt/ephemeral
ExecStart=dd if=/dev/zero of=/mnt/ephemeral/swapfile bs=1G count=8
ExecStart=chmod 600 /mnt/ephemeral/swapfile
ExecStart=mkswap /mnt/ephemeral/swapfile
ExecStart=swapon /mnt/ephemeral/swapfile
ExecStop=swapoff /mnt/ephemeral/swapfile
ExecStop=/usr/bin/umount /mnt/ephemeral

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable instance-storage
sudo systemctl start instance-storage

# install CUDA (from https://developer.nvidia.com/cuda-downloads)
cd /mnt/ephemeral
sudo -u admin wget --no-verbose https://developer.download.nvidia.com/compute/cuda/$CUDA_VERSION/local_installers/cuda_${CUDA_FULL_VERSION}_linux.run
sudo sh cuda_${CUDA_FULL_VERSION}_linux.run --silent
sudo -u admin rm cuda_${CUDA_FULL_VERSION}_linux.run

cd /home/admin
sudo -u admin git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git
sudo -u admin wget --no-verbose https://huggingface.co/stabilityai/stable-diffusion-2-1-base/resolve/main/v2-1_512-ema-pruned.ckpt -P stable-diffusion-webui/models/Stable-diffusion/
sudo -u admin wget --no-verbose https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/v2-1_768-ema-pruned.ckpt -P stable-diffusion-webui/models/Stable-diffusion/
sudo -u admin wget --no-verbose https://raw.githubusercontent.com/Stability-AI/stablediffusion/main/configs/stable-diffusion/v2-inference.yaml -O stable-diffusion-webui/models/Stable-diffusion/v2-1_512-ema-pruned.yaml
sudo -u admin wget --no-verbose https://raw.githubusercontent.com/Stability-AI/stablediffusion/main/configs/stable-diffusion/v2-inference-v.yaml -O stable-diffusion-webui/models/Stable-diffusion/v2-1_768-ema-pruned.yaml

cat <<EOF | sudo tee /usr/lib/systemd/system/sdwebgui.service
[Unit]
Description=Stable Diffusion AUTOMATIC1111 Web UI service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=admin
WorkingDirectory=/home/admin/stable-diffusion-webui/
ExecStart=/usr/bin/env bash /home/admin/stable-diffusion-webui/webui.sh
StandardOutput=append:/var/log/sdwebui.log
StandardError=append:/var/log/sdwebui.log

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable sdwebgui
sudo systemctl start sdwebgui
