#!/bin/bash
set -e
trap 'catchError $? $LINENO' ERR

catchError() {
    echo "An error occurred on line $2. Exit status: $1"
    exit $1
}

### Add pre-requisites
# -- Docker
# -- AWS CLI
# -- NodeJS
# -- Python3
# -- Atlas app services CLI


echo "Goto atlas and create API key"
# open "https://www.mongodb.com/docs/atlas/app-services/cli/#generate-an-api-key"
apiKey=$API_KEY
pvtApiKey=$PRIVATE_KEY
awsID=$AWS_ACCOUNT_ID
awsRegion=$AWS_REGION
sagemakerEndpoint=$SAGEMAKER_ENDPOINT
mongoURI=$MONGODB_URI

echo "---------------------- MONGODB ATLAS SETUP ----------------------------"
npm install -g atlas-app-services-cli
appservices login --api-key=$API_KEY --private-api-key=$PRIVATE_KEY

# Update AWS Account ID
cd ../atlas-backend/Connected-Vehicle/triggers
sed -i "s/<ACCOUNT_ID>/979559056307/" eventbridge_publish_battery_telemetry.json
sed -i "s/<REGION>/us-east-1/" eventbridge_publish_battery_telemetry.json


cd ../../
echo "Logging in to Atlas..."

echo "Pushing Connected-Vehicle app to Atlas...This may take a while!"
#TODO: Fix this for Appservices CLI

app_id_info=$(appservices push --local ./Connected-Vehicle --remote Connected-Vehicle -y | tee output.log | tail -1)
app_id=$(echo $app_id_info | cut -d' ' -f 5)

echo "-------------------------------------------------"
echo "|         App Id: $app_id    |"
echo "-------------------------------------------------"

echo "Creating a user for the app..."
appservices users create --type email --email demo --password demopw --app $app_id

echo "Below are the apps in your account..."
appservices apps list

cd ../vehicle-ts/src/realm
sed -i "s/connected-vehicle-.*/"$app_id"\"/" config.ts
cd ../..
npm install
npm run build
echo "Starting the web-app..."
# npm start
nohup npm start > start.log 2>&1 &
echo "Web-app started successfully!"

echo "---------------------- AWS SETUP ----------------------------"

echo "Setting up AWS services!"
## Create AWS Eventbus 
echo "Associating Eventbus..."

# Get the trigger ID 
# Login to the MongoDB Cloud API
curl_output=$(curl -s --request POST \
  --header 'Content-Type: application/json' \
  --header 'Accept: application/json' \
  --data "{\"username\": \"$API_KEY\", \"apiKey\": \"$PRIVATE_KEY\"}" \
  https://services.cloud.mongodb.com/api/admin/v3.0/auth/providers/mongodb-cloud/login)

# Extract the access_token using jq
access_token=$(echo "$curl_output" | jq -r '.access_token')
echo "Access Token: $access_token"

# Save in a variable
appservices_output=$(appservices apps list)
echo "$appservices_output" > appservices_output.log 
read -r project_id client_app_id <<< "$(awk -v app_id="$app_id" '$0 ~ app_id {print $2, $3}' appservices_output.log)"
echo "Client App ID: $client_app_id"
echo "Project ID: $project_id"

# Get Trigger ID
curl_output=$(curl -s --request GET \
  --header "Authorization: Bearer $access_token" \
  "https://services.cloud.mongodb.com/api/admin/v3.0/groups/$project_id/apps/$client_app_id/triggers")
echo "Curl output: $curl_output"
triggerId=$(echo "$curl_output" | jq -r '.[] | select(.name == "eventbridge_publish_battery_telemetry") | ._id')
echo "trigger Id : $triggerId" 
aws events create-event-bus --region $awsRegion --event-source-name aws.partner/mongodb.com/stitch.trigger/$triggerId --name aws.partner/mongodb.com/stitch.trigger/$triggerId 

echo "Associated!"


pwd
cd ../aws-sagemaker
## Create AWS ECR Repository 
echo "Creating ECR Repositories..."
aws ecr create-repository --repository-name cli_connected_vehicle_atlas_to_sagemaker --region $awsRegion
aws ecr create-repository --repository-name cli_connected_vehicle_sagemaker_to_atlas --region $awsRegion
echo "ECR Repositories created for storing Lambda functions!"

cd code/pull_from_mdb
## Update the Sagemaker Endpoint and Eventbus
sed -i "s/<SAGEMAKER_ENDPOINT>/$SAGEMAKER_ENDPOINT/" app.py
sed -i "s/<REGION>/$awsRegion/" app.py

## Push to ECR - Image 1
echo "Building and pushing the image to ECR..."
docker login -u AWS -p $(aws ecr get-login-password --region $awsRegion) $awsID.dkr.ecr.$awsRegion.amazonaws.com
docker build -t cli_connected_vehicle_atlas_to_sagemaker .
docker tag cli_connected_vehicle_atlas_to_sagemaker:latest $awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_atlas_to_sagemaker:latest
docker push $awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_atlas_to_sagemaker:latest


## Create a role with permissions to access Sagemaker and Lambda
echo "Creating a role with permissions to access Sagemaker and Lambda..."
sed -i "s/<REGION>/$awsRegion/" role-policy.json
sed -i "s/<ACCOUNT_ID>/$awsID/" role-policy.json

aws iam create-role --role-name cli_connected_vehicle_atlas_to_sagemaker_role --assume-role-policy-document file://role-policy.json --region $awsRegion

# Add a wait for role to be created.
echo "Waiting for the role to be created..."
counter=0
while true; do
    if aws iam get-role --role-name cli_connected_vehicle_atlas_to_sagemaker_role > /dev/null 2>&1; then
        echo "Role Created Successfully!"
        break
    else
        echo "Role not yet created, waited for $counter sec"
        sleep 5
        let counter+=5
    fi
done

sleep 5s

## Create Lambda Function using ECR Image and Role
echo "Creating Lambda function using the ECR Image..."
aws lambda create-function --function-name sagemaker-pull-partner-cli --role arn:aws:iam::$awsID:role/cli_connected_vehicle_atlas_to_sagemaker_role --region $awsRegion --code ImageUri=$awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_atlas_to_sagemaker:latest --package-type Image

# Push to ECR - Image 2
pwd
cd ../push_to_mdb
sed -i "s/<MONGODB_URI>/$mongoURI/" write_to_mdb.py

echo "Building and pushing second image to ECR..."
docker build -t cli_connected_vehicle_sagemaker_to_atlas .
docker tag cli_connected_vehicle_sagemaker_to_atlas:latest $awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_sagemaker_to_atlas:latest
docker push $awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_sagemaker_to_atlas:latest

echo "Creating Lambda function using the ECR Image..."
aws lambda create-function --function-name sagemaker-push-partner-cli --role arn:aws:iam::$awsID:role/cli_connected_vehicle_atlas_to_sagemaker_role --region $awsRegion --code ImageUri=$awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_sagemaker_to_atlas:latest --package-type Image

# Create Rule for AWS event bus
echo "Creating a rule for the event bus..."
aws events put-rule --name sagemaker-pull \
    --event-pattern '{"source": [{"prefix": "aws.partner/mongodb.com"}]}' \
    --event-bus-name aws.partner/mongodb.com/stitch.trigger/$triggerId \
    --region $awsRegion 

aws events put-targets --rule sagemaker-pull \
    --targets "Id"="1","Arn"="arn:aws:lambda:$awsRegion:$awsID:function:sagemaker-pull-partner-cli" \
    --region $awsRegion \
    --event-bus-name aws.partner/mongodb.com/stitch.trigger/$triggerId


echo "Associating eventbridge with lambda function..."
aws lambda add-permission \
--function-name sagemaker-pull-partner-cli \
--statement-id trigger-event \
--action 'lambda:InvokeFunction' \
--principal events.amazonaws.com \
--source-arn arn:aws:events:$awsRegion:$awsID:rule/aws.partner/mongodb.com/stitch.trigger/$triggerId/sagemaker-pull \
--region $awsRegion


# Create Event bus for Sagemaker to Atlas
echo "Creating Event bus for Sagemaker to Atlas..."
aws events create-event-bus --name cli_pushing_to_mongodb --region $awsRegion  

## Create rule for Sagemaker to Atlas
echo "Creating a rule for Sagemaker to Atlas..."
aws events put-rule --name push_to_lambda \
    --event-pattern '{"source": ["user-event"], "detail-type": ["user-preferences"]}' \
    --event-bus-name cli_pushing_to_mongodb \
    --region $awsRegion

aws events put-targets --rule push_to_lambda \
    --targets "Id"="1","Arn"="arn:aws:lambda:$awsRegion:$awsID:function:sagemaker-push-partner-cli" \
    --region $awsRegion \
    --event-bus-name cli_pushing_to_mongodb


echo "Associating eventbridge with lambda function..."
aws lambda add-permission \
--function-name cli_pushing_to_mongodb \
--statement-id trigger-event \
--action 'lambda:InvokeFunction' \
--principal events.amazonaws.com \
--source-arn arn:aws:events:$awsRegion:$awsID:rule/push_to_lambda \
--region $awsRegion


echo "------------------  AWS setup completed successfully!  ------------------"
