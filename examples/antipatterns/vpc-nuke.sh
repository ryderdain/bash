#!/bin/bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/freebsd-portupdater @ 95c3d8a
# │ path     : vpc-nuke.sh
# │ pulled   : 2026-08-03
# │ shows    : COUNTER-EXAMPLE: unchecked `aws` calls, unquoted array expansion, substring-match membership test, no preview. Linter fodder
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#

# List of regions you want to KEEP default VPCs in (modify as needed)
KEEP_REGIONS= #("us-east-1" "us-west-2")

# Get all AWS regions
ALL_REGIONS=($(aws ec2 describe-regions --query "Regions[*].RegionName" --output text))

for region in ${ALL_REGIONS[@]}; do
    # Skip regions you want to keep
    if [[ " ${KEEP_REGIONS[@]} " =~ " ${region} " ]]; then
        echo "Keeping default VPC in $region"
        continue
    fi
    
    echo "Processing region: $region"
    
    # Get default VPC ID
    VPC_ID="$(aws ec2 describe-vpcs --region $region --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)"
    
    printf '%s:\t%s\n' "$region" "$VPC_ID"

    if [[ $VPC_ID != "None" && $VPC_ID != "" ]]; then
        echo "Found default VPC $VPC_ID in $region - deleting..."
        
        # Delete all internet gateways
        IGW_IDS=($(aws ec2 describe-internet-gateways --region $region --filters Name=attachment.vpc-id,Values=$VPC_ID --query "InternetGateways[*].InternetGatewayId" --output text))
        for igw in ${IGW_IDS[@]}; do
            echo aws ec2 detach-internet-gateway --region $region --internet-gateway-id $igw --vpc-id $VPC_ID
            echo aws ec2 delete-internet-gateway --region $region --internet-gateway-id $igw
        done
        
        # Delete all subnets
        SUBNET_IDS=($(aws ec2 describe-subnets --region $region --filters Name=vpc-id,Values=$VPC_ID --query "Subnets[*].SubnetId" --output text))
        for subnet in ${SUBNET_IDS[@]}; do
            echo aws ec2 delete-subnet --region $region --subnet-id $subnet
        done
        
        # Delete all security groups (except default)
        SG_IDS=$(aws ec2 describe-security-groups --region $region --filters Name=vpc-id,Values=$VPC_ID --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
        for sg in ${SG_IDS[@]}; do
            echo aws ec2 delete-security-group --region $region --group-id $sg
        done
        
        # Delete the default VPC
        aws ec2 delete-vpc --region $region --vpc-id $VPC_ID
        echo "Default VPC deleted in $region"
    else
        echo "No default VPC found in $region"
    fi
done
