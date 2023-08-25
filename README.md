# Stable Diffusion on AWS

## Quick Start

I use https://github.com/stateful/runme to make it easier to run these snippets; I strongly suggest you do too :-)

### Launching

#### Create the spot instance request (which will create the instance after a few seconds)

```bash {name=launch-an-instance}
export PUBLIC_KEY_PATH="$HOME/.ssh/id_rsa.pub"
export INSTALL_AUTOMATIC1111="true"
export INSTALL_INVOKEAI="true"
export GUI_TO_START="invokeai"
export EBS_SIZE="50"

aws ec2 import-key-pair --key-name stable-diffusion-aws --public-key-material fileb://${PUBLIC_KEY_PATH} --tag-specifications 'ResourceType=key-pair,Tags=[{Key=creator,Value=stable-diffusion-aws}]'

# Get the latest Debian 11 image
export AMI_ID=$(aws ec2 describe-images --owners 136693071363 --query "sort_by(Images, &CreationDate)[-1].ImageId" --filters "Name=name,Values=debian-12-amd64-*" | jq -r .)

export DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
export SG_ID=$(aws ec2 create-security-group --group-name SSH-Only --description "Allow SSH from anywhere" --vpc-id $DEFAULT_VPC_ID --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 create-tags --resources $SG_ID --tags Key=creator,Value=stable-diffusion-aws

aws ec2 run-instances \
    --no-cli-pager \
    --image-id $AMI_ID \
    --instance-type g4dn.xlarge \
    --key-name stable-diffusion-aws \
    --security-group-ids $SG_ID \
    --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=${EBS_SIZE},VolumeType=gp3}" \
    --user-data file://setup.sh \
    --metadata-options "InstanceMetadataTags=enabled" \
    --tag-specifications "ResourceType=spot-instances-request,Tags=[{Key=creator,Value=stable-diffusion-aws}]" "ResourceType=instance,Tags=[{Key=INSTALL_AUTOMATIC1111,Value=$INSTALL_AUTOMATIC1111},{Key=INSTALL_INVOKEAI,Value=$INSTALL_INVOKEAI},{Key=GUI_TO_START,Value=$GUI_TO_START}]" \
    --instance-market-options 'MarketType=spot,SpotOptions={MaxPrice=0.20,SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}'

```

#### Configure the node to automatically register with duckdns (optional)

```bash {name=register-with-duckdns, promptEnv=false}
# First, export DUCKDNS_TOKEN and DUCKDNS_SUBDOMAIN

export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
export PUBLIC_IP="$(aws ec2 describe-instances --instance-id $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicIpAddress')"
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@$PUBLIC_IP "echo '#"\!"/bin/sh' | sudo tee /etc/rc.local && echo 'curl '\''https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&verbose=true'\' | sudo tee -a /etc/rc.local && sudo chmod +x /etc/rc.local && sudo systemctl daemon-reload && sudo systemctl start rc-local && systemctl status rc-local"
```

#### Create an Alarm to stop the instance after 15 minutes of idling (optional)

```bash {name=create-cloudwatch-alarm, promptEnv=false}
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

```bash {name=connect-via-ssh, promptEnv=false}
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

```bash {name=stop-the-instance, promptEnv=false}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
aws ec2 stop-instances --instance-ids $INSTANCE_ID
```

#### Start

```bash {name=start-the-instance, promptEnv=false}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=disabled' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
aws ec2 start-instances --instance-ids $INSTANCE_ID
```

#### Delete

```bash {name=cleanup-everything, promptEnv=false}
export SPOT_INSTANCE_REQUEST="$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open,disabled' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')"
[[ -n $SPOT_INSTANCE_REQUEST ]] && export INSTANCE_ID="$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')"
export SG_ID="$(aws ec2 describe-security-groups --filters 'Name=tag:creator,Values=stable-diffusion-aws' --query 'SecurityGroups[*].GroupId' --output text)"
export KEY_PAIR_NAME="$(aws ec2 describe-key-pairs --filters 'Name=tag:creator,Values=stable-diffusion-aws' --query 'KeyPairs[0].KeyName' --output text)"
[[ -n $SPOT_INSTANCE_REQUEST ]] && aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST
if [[ -n $INSTANCE_ID ]]
then
    VPC_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].VpcId' --output text)
    DEFAULT_SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text)
    aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --groups $DEFAULT_SG_ID
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID
fi

[[ -n $KEY_PAIR_NAME ]] && aws ec2 delete-key-pair --key-name $KEY_PAIR_NAME
[[ -n $SG_ID ]] && aws ec2 delete-security-group --group-id $SG_ID
aws cloudwatch delete-alarms --alarm-names stable-diffusion-aws-stop-when-idle
```

## Full Explanation

This repository makes it easy to run your own Stable Diffusion instance on AWS. The are two options for frontends; the first is the GUI at https://github.com/AUTOMATIC1111/stable-diffusion-webui, and the second is https://github.com/invoke-ai/InvokeAI. By default, both are installed, but only Invoke-AI is started. There is insufficient RAM to run both at the same time, as model loading + image generation will take up slightly more than 16GB of RAM. There are environment variables at the beginning of setup.sh which can be used to set which are installed and/or started. Systemd services are installed for both, and they can be started or stopped at runtime freely. The names are `sdwebgui.service` and `invokeai.service`. 

Some parts of the script are based on https://github.com/marshmellow77/stable-diffusion-webui .

It is assumed that you have basic familiarity with AWS services, including setting up the CLI for use (whether via access keys or a profile or any other method).

Before starting, go to https://us-east-1.console.aws.amazon.com/servicequotas/home/services/ec2/quotas and open a support case to raise the maximum number of vCPUs for "All G and VT Spot Instance Requests" to 4 (each g4dn.xlarge machine is 4 vCPUs).

The Quick Start section contains snippets to create a spot instance request that will launch one spot instance. The retail price of a g4dn.xlarge is $0.52/hour, but the spot market currently fluctuates around $0.17, for a 65% savings. These instructions set a price limit of $0.20; if you need better reliability, you can remove `MaxPrice=0.20,` and it will allow it to cost up to the full on-demand price.

This spot instance can be stopped and started like a regular instance. When stopped, the only cost is $0.40/month for the EBS volume. When removing all traces of this, note that terminating the instance will cause the SpotInstanceRequest to launch a new instances, but conversely, canceling the SpotInstanceRequest will not automatically terminated the instances that it spawned. As such, the SpotInstanceRequest must be canceled first, and then the instance explicitly terminated.

There is approximately 20GB free on the root partition. This should be sufficient for basic operation, but if you need more space temporarily, you can use `/mnt/ephemeral`, which is a 125GB (115 GB) instance volume. It is a high performance SSD, but will be wiped on every stop/start of the EC2 instance. It also contains an 8GB swapfile.

To save costs, the instance will automatically be shutdown if the CPU Utilization (sampled every 5 minutes) is less than 20% for 3 consecutive checks. This can be skipped if desired.

There is no protection on the GUI, so it is not exposed to the world. Instead, create an ssh tunnel and connect via either http://localhost:7860 for automatic1111 or http://localhost:9090 for Invoke-AI.
