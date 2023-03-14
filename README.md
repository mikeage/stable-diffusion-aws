# Stable Diffusion on AWS

## Launching

```bash
export AMI_ID="ami-0574da719dca65348"  # Ubuntu 22.04 in us-east-1
export SECURITY_GROUP_ID="sg-0ba8468ab13683325"  # SSH only
export KEY_NAME="MikeMiller"  # Your SSH keypair

aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type g4dn.xlarge \
    --key-name $KEY_NAME \
    --security-group-ids $SECURITY_GROUP_ID \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=30,VolumeType=gp3}' \
    --user-data file://setup.sh \
    --instance-market-options 'MarketType=spot,SpotOptions={MaxPrice=0.20,SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}'

# Wait about 15 minutes
ssh -L7860:localhost:7860 ubuntu@...

# Open http://localhost:7860
```

## Stop / Start

### Stop

```bash
aws ec2 stop-instances --instance-ids $INSTANCE_ID
```

### Start

```bash
aws ec2 start-instances --instance-ids $INSTANCE_ID

aws ec2 describe-instances --instance-id $INSTANCE_ID | jq '.Reservations[].Instances[].PublicIpAddress'
```

## Deleting

### Spot Instances only

```bash
aws ec2 cancel-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST
aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq '.SpotInstanceRequests[].InstanceId'
```

### Both Spot and On-Demand

```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```
