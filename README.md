# Stable Diffusion on AWS

## Quick Start

### Launching

```bash
export AMI_ID="ami-0574da719dca65348"  # Ubuntu 22.04 in us-east-1
export SECURITY_GROUP_ID="sg-0ba8468ab13683325"  # SSH only
export KEY_NAME="MikeMiller"  # Your SSH keypair

aws ec2 run-instances \
    --no-cli-pager \
    --image-id $AMI_ID \
    --instance-type g4dn.xlarge \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3}' \
    --user-data file://setup.sh \
    --tag-specifications 'ResourceType=spot-instances-request,Tags=[{Key=creator,Value=stable-diffusion-aws}]' \
    --instance-market-options 'MarketType=spot,SpotOptions={MaxPrice=0.20,SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}'

sleep 5

export SPOT_INSTANCE_REQUEST=$(aws ec2 describe-spot-instance-requests --filters 'Name=tag:creator,Values=stable-diffusion-aws' 'Name=state,Values=active,open' | jq -r '.SpotInstanceRequests[].SpotInstanceRequestId')
export INSTANCE_ID=$(aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq -r '.SpotInstanceRequests[].InstanceId')

aws cloudwatch put-metric-alarm \
    --alarm-name stable-diffusion-aws-stop-when-idle \
    --namespace AWS/EC2 \
    --metric-name CPUUtilization \
    --statistic Maximum \
    --period 300  \
    --evaluation-periods 3 \
    --threshold 10 \
    --comparison-operator LessThanThreshold \
    --unit Percent \
    --dimensions "Name=InstanceId,Value=$INSTANCE_ID" \
    --alarm-actions arn:aws:automate:$AWS_REGION:ec2:stop

export PUBLIC_IP=$(aws ec2 describe-instances --instance-id $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicIpAddress')

ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -L7860:localhost:7860 ubuntu@$PUBLIC_IP

# Wait about 15 minutes

# Open http://localhost:7860
```

### Lifecycle Management

#### Stop

```bash
aws ec2 stop-instances --instance-ids $INSTANCE_ID
```

#### Start

```bash
aws ec2 start-instances --instance-ids $INSTANCE_ID
export PUBLIC_IP=$(aws ec2 describe-instances --instance-id $INSTANCE_ID | jq -r '.Reservations[].Instances[].PublicIpAddress')
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -L7860:localhost:7860 ubuntu@$PUBLIC_IP
```

#### Delete

```bash
aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws cloudwatch delete-alarms --alarm-names stable-diffusion-aws-stop-when-idle
```

## Full Explanation

This repository makes it easy to run your own Stable Diffusion instance on AWS. It uses the excellent GUI at https://github.com/AUTOMATIC1111/stable-diffusion-webui, and is somewhat based on the code at https://github.com/marshmellow77/stable-diffusion-webui .

It is assumed that you have basic familiarity with AWS services, including setting up the CLI for use (whether via access keys or a profile or any other method).

Before starting, go to https://us-east-1.console.aws.amazon.com/servicequotas/home/services/ec2/quotas and open a support case to raise the maximum number of vCPUs for "All G and VT Spot Instance Requests" to 4 (each g4dn.xlarge machine is 4 vCPUs).

The Quick Start section contains snippets to create a spot instance request that will launch one spot instance. The retail price of a g4dn.xlarge is $0.52/hour, but the spot market currently fluctuates around $0.17, for a 65% savings. These instructions set a price limit of $0.20; if you need better reliability, you can remove `MaxPrice=0.20,` and it will allow it to cost up to the full on-demand price.

This spot instance can be stopped and started like a regular instance. When stopped, the only cost is $0.24/month for the EBS volume. When removing all traces of this, note that terminating the instance will cause the SpotInstanceRequest to launch a new instances, but conversely, canceling the SpotInstanceRequest will not automatically terminated the instances that it spawned. As such, the SpotInstanceRequest must be canceled first, and then the instance explicitly terminated.

To save costs, the instance will automatically be shutdown if the CPU Utilization (sampled every 5 minutes) is less than 20% for 3 consecutive checks. This can be skipped if desired.

There is no protection on the GUI, so it is not exposed to the world. Instead, create an ssh tunnel and connect via http://localhost:7860. 
