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
```

## Deleting

### Spot Instances only

```bash
aws ec2 cancel-spot-instance-requests $SPOT_INSTANCE_REQUEST
aws ec2 describe-spot-instance-requests --spot-instance-request-ids $SPOT_INSTANCE_REQUEST | jq '.SpotInstanceRequests[].InstanceId'
```

### Spot and on-demand

```bash
aws ec2 terminate-instances --instance-ids i-xxxxxxx
```
