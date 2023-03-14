#!/bin/sh

set -e

# disable the restart dialogue and install several packages
sudo sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
sudo apt update
# sudo apt upgrade -y
sudo apt install wget git python3 python3-venv build-essential net-tools -y

# install CUDA (from https://developer.nvidia.com/cuda-downloads)
cd /tmp
sudo -u ubuntu wget https://developer.download.nvidia.com/compute/cuda/12.0.0/local_installers/cuda_12.0.0_525.60.13_linux.run
sudo sh cuda_12.0.0_525.60.13_linux.run --silent
sudo -u ubuntu rm cuda_12.0.0_525.60.13_linux.run

cd /home/ubuntu
sudo -u ubuntu git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git 
sudo -u ubuntu wget https://huggingface.co/stabilityai/stable-diffusion-2-1-base/resolve/main/v2-1_512-ema-pruned.ckpt -P stable-diffusion-webui/models/Stable-diffusion/
sudo -u ubuntu wget https://raw.githubusercontent.com/Stability-AI/stablediffusion/main/configs/stable-diffusion/v2-inference.yaml -P stable-diffusion-webui/models/Stable-diffusion/ -O v2-1_512-ema-pruned.yaml 

cat <<EOF | sudo tee /usr/lib/systemd/system/sdwebgui.service
[Unit]
Description=Stable Diffusion AUTOMATIC1111 Web UI service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=ubuntu
WorkingDirectory=/home/ubuntu/stable-diffusion-webui/
ExecStart=/usr/bin/env bash /home/ubuntu/stable-diffusion-webui/webui.sh
StandardOutput=append:/var/log/sdwebui.log
StandardError=append:/var/log/sdwebui.log

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable sdwebgui
sudo systemctl start sdwebgui
