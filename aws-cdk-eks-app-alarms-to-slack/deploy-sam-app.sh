#!/bin/bash

# exit when any command fails
set -e

NC='\033[0m'       # Text Reset
R='\033[0;31m'          # Red
G='\033[0;32m'        # Green
Y='\033[0;33m'       # Yellow
echo -e "${Y}"

# checking environment variables

if [ -z "${CAP_ACCOUNT_ID}" ]; then
    echo -e "${R}env variable CAP_ACCOUNT_ID not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_REGION}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_REGION not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_NAME}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_NAME not set${NC}"; exit 1
fi

if [ -z "${CAP_FUNCTION_NAME}" ]; then
    echo -e "${R}env variable CAP_FUNCTION_NAME not set${NC}"; exit 1
fi

curr_dir=${PWD}

#get Slack Channel name and Incoming webhook

urlRegex='^(https)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$'
read -p "Slack incoming webhook URL: " webhookURL
if [[ $webhookURL =~ $urlRegex ]]
then
    echo -e "This webhook URL will be encrypted and used in Lambda function."
else
    echo -e "${R}Slack incoming webhook URL is invalid. Check the input value and provide a valid full webhook URL along with protocol https://.${NC}"
    exit 1
fi

scRegex='^\S{1,}$'
read -p "Slack channel name: " slackChannel
if [[ $slackChannel =~ $scRegex ]]
then
    echo -e "Notifications will be sent to Slack channel ${slackChannel}."
else
    echo -e "${R}Slack channel name is invalid. Slack channel name should not contain any spaces.${NC}"
    exit 1
fi

#generate EncryptedURL

CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)
EncryptedURL=$(aws kms encrypt --region ${CAP_CLUSTER_REGION} --key-id ${CAP_KMS_KEY_ID} --plaintext `echo ${webhookURL} | base64 -w 0` --query CiphertextBlob --output text --encryption-context LambdaFunctionName=${CAP_FUNCTION_NAME})
#to verify decryption
#aws kms decrypt --region ${CAP_CLUSTER_REGION} --ciphertext-blob ${EncryptedURL} --output text --query Plaintext --encryption-context LambdaFunctionName=${CAP_FUNCTION_NAME} | base64 -d

#deploy Lambda function using SAM
sam deploy --region ${CAP_CLUSTER_REGION} --template templates/sam-template.yaml --resolve-s3  --confirm-changeset --stack-name ${CAP_FUNCTION_NAME}-app --capabilities CAPABILITY_IAM --parameter-overrides "AccountID=${CAP_ACCOUNT_ID} ClusterRegion=${CAP_CLUSTER_REGION} KMSKeyID=${CAP_KMS_KEY_ID} FunctionName=${CAP_FUNCTION_NAME} EncryptedURL=${EncryptedURL} SlackChannel=${slackChannel}"
