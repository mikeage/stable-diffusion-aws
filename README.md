# Stable Diffusion on AWS

## Quick Start

### Launching

#### Create the spot instance request (which will create the instance after a few seconds)

```bash {name=launch-an-instance}
export AMI_ID="ami-0a9d5908c7201e91d"  # Debian 11 in us-east-1
export SECURITY_GROUP_ID="sg-0ba8468ab13683325"  # SSH only
export KEY_NAME="StableDiffusionKey"  # Your SSH keypair

aws ec2 run-instances \
    --no-cli-pager \
    --image-id $AMI_ID \
    --instance-type g4dn.xlarge \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=50,VolumeType=gp3}' \
    --user-data file://setup.sh \
    --tag-specifications 'ResourceType=spot-instances-request,Tags=[{Key=creator,Value=stable-diffusion-aws}]' \
    --instance-market-options 'MarketType=spot,SpotOptions={MaxPrice=0.20,SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}'

```

#### Configure the node to automatically register with duckdns (optional)

```bash {name=register-with-duckdns}
# First, export DUCKDNS_TOKEN and DUCKDNS_SUBDOMAIN

export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
export PUBLIC_IP="$(aws ec2 describe-instances --instance-id $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicIpAddress')"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@$PUBLIC_IP "echo '#"\!"/bin/sh' | sudo tee /etc/rc.local && echo 'curl '\''https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&verbose=true'\' | sudo tee -a /etc/rc.local && sudo chmod +x /etc/rc.local && sudo systemctl daemon-reload && sudo systemctl start rc-local && systemctl status rc-local"
```

#### Create an Alarm to stop the instance after 15 minutes of idling (optional)

```bash {name=create-cloudwatch-alarm}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"

aws cloudwatch put-metric-alarm \
    --alarm-name stable-diffusion-aws-stop-when-idle \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --statistic Maximum \
    --period 300  \
    --evaluation-periods 3 \
    --threshold 5 \
    --comparison-operator LessThanThreshold \
    --unit Percent \
    --dimensions "Name=InstanceId,Value=$INSTANCE_ID" \
    --alarm-actions arn:aws:automate:$AWS_REGION:ec2:stop
```

#### Connect

```bash {name=connect-via-ssh}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
export PUBLIC_IP="$(aws ec2 describe-instances --instance-id $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicIpAddress')"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -L7860:localhost:7860 -L9090:localhost:9090 admin@$PUBLIC_IP

# Wait about 10 minutes from the first creation

# Open http://localhost:7860 or http://localhost:9090
```

Alternatively, if you used the DuckDNS configuration above, adding this to your `~/.ssh/config` might be easier:

```
Host YOUR_NICKNAME
    User admin
    Hostname YOUR_NICKNAME.duckdns.org
    IdentityFile ~/.ssh/StableDiffusionKey.pem
    UserKnownHostsFile /dev/null
    StrictHostKeyChecking no
    LocalForward 7860 localhost:7860
    LocalForward 9090 localhost:9090
```

### Lifecycle Management

#### Stop

```bash {name=stop-the-instance}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
aws ec2 stop-instances --instance-ids $INSTANCE_ID
```

#### Start

```bash {name=start-the-instance}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=disabled' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
aws ec2 start-instances --instance-ids $INSTANCE_ID
```

#### Delete

```bash {name=cleanup-everything}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open,disabled' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws cloudwatch delete-alarms --alarm-names stable-diffusion-aws-stop-when-idle
```

## Full Explanation

This repository makes it easy to run your own Stable Diffusion instance on AWS. The are two options for frontends; the first is the GUI at https://github.com/AUTOMATIC1111/stable-diffusion-webui, and the second is https://github.com/invoke-ai/InvokeAI. By default, both are installed, but only Invoke-AI is started. There is insufficient RAM to run both at the same time, as model loading + image generation will take up slightly more than 16GB of RAM. There are environment variables at the beginning of setup.sh which can be used to set which are installed and/or started. Systemd services are installed for both, and they can be started or stopped at runtime freely. The names are `sdwebgui.service` and `invokeai.service`. 

Some parts of the script are based on https://github.com/marshmellow77/stable-diffusion-webui .

It is assumed that you have basic familiarity with AWS services, including setting up the CLI for use (whether via access keys or a profile or any other method).

Before starting, go to https://us-east-1.console.aws.amazon.com/servicequotas/home/services/ec2/quotas and open a support case to raise the maximum number of vCPUs for "All G and VT Spot Instance Requests" to 4 (each g4dn.xlarge machine is 4 vCPUs).

The Quick Start section contains snippets to create a spot instance request that will launch one spot instance. The retail price of a g4dn.xlarge is $0.52/hour, but the spot market currently fluctuates around $0.17, for a 65% savings. These instructions set a price limit of $0.20; if you need better reliability, you can remove `MaxPrice=0.20,` and it will allow it to cost up to the full on-demand price.

This spot instance can be stopped and started like a regular instance. When stopped, the only cost is $0.40/month for the EBS volume. When removing all traces of this, note that terminating the instance will cause the SpotInstanceRequest to launch a new instances, but conversely, canceling the SpotInstanceRequest will not automatically terminated the instances that it spawned. As such, the SpotInstanceRequest must be canceled first, and then the instance explicitly terminated.

There is approximately 10GB free on the root partition. This should be sufficient for basic operation, but if you need more space temporarily, you can use `/mnt/ephemeral`, which is a 125GB (115 GB) instance volume. It is a high performance SSD, but will be wiped on every stop/start of the EC2 instance. It also contains an 8GB swapfile.

To save costs, the instance will automatically be shutdown if the CPU Utilization (sampled every 5 minutes) is less than 20% for 3 consecutive checks. This can be skipped if desired.

There is no protection on the GUI, so it is not exposed to the world. Instead, create an ssh tunnel and connect via either http://localhost:7860 for automatic1111 or http://localhost:9090 for Invoke-AI.
