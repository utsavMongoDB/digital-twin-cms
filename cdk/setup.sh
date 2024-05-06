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

echo "---------------------- MONGODB ATLAS SETUP ----------------------------"
npm install -g atlas-app-services-cli
appservices login --api-key=$API_KEY --private-api-key=$PRIVATE_KEY

# Update AWS Account ID
cd ../atlas-backend/Connected-Vehicle/triggers
sed -i "s/<ACCOUNT_ID>/979559056307/" eventbridge_publish_battery_telemetry.json
sed -i "s/<REGION>/us-east-1/" eventbridge_publish_battery_telemetry.json
# rm eventbridge_publish_battery_telemetry.json1  


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
echo "Please enter the following details to setup AWS : "
## Input for Sagemaker Endpoint and MongoDB URI
sagemakerEndpoint=$SAGEMAKER_ENDPOINT
mongoURI=$MONGODB_URI

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
read -r project_id client_app_id <<< "$(awk '/connected-vehicle-xnbjimf/ {print $2, $3}' appservices_output.log)"
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

