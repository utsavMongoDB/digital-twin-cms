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
# npm install -g atlas-app-services-cli

# # Update AWS Account ID
# cd ../atlas-backend/Connected-Vehicle/triggers
# sed -i "s/<ACCOUNT_ID>/979559056307/" eventbridge_publish_battery_telemetry.json
# sed -i "s/<REGION>/us-east-1/" eventbridge_publish_battery_telemetry.json
# # rm eventbridge_publish_battery_telemetry.json1  


# cd ../../
# echo "Logging in to Atlas..."

# appservices login --api-key=aeewzbjo --private-api-key=20cd1330-cfb4-4ddc-8c96-49ffb3cee1be

# echo "Pushing Connected-Vehicle app to Atlas...This may take a while!"
# #TODO: Fix this for Appservices CLI

# app_id_info=$(appservices push --local ./Connected-Vehicle --remote Connected-Vehicle -y | tee output.log | tail -1)
# app_id=$(echo $app_id_info | cut -d' ' -f 5)

# echo "-------------------------------------------------"
# echo "|         App Id: $app_id    |"
# echo "-------------------------------------------------"

# echo "Creating a user for the app..."
# appservices users create --type email --email demo --password demopw --app $app_id

# echo "Below are the apps in your account..."
# appservices apps list

# cd ../vehicle-ts/src/realm
# sed -i "s/connected-vehicle-.*/"$app_id"\"/" config.ts
# cd ../..
# npm install
# npm run build
# echo "Starting the web-app..."
# npm start
# # nohup npm start > start.log 2>&1 &
# echo "Web-app started successfully!"

echo "---------------------- AWS SETUP ----------------------------"

echo "Setting up AWS services!"
echo "Please enter the following details to setup AWS : "
## Input for Sagemaker Endpoint and MongoDB URI
sagemakerEndpoint=$SAGEMAKER_ENDPOINT
mongoURI=$MONGODB_URI

pwd
cd ../aws-sagemaker
## Create AWS ECR Repository 
echo "Creating ECR Repositories..."
# aws ecr create-repository --repository-name cli_connected_vehicle_atlas_to_sagemaker --region $awsRegion
# aws ecr create-repository --repository-name cli_connected_vehicle_sagemaker_to_atlas --region $awsRegion
# echo "ECR Repositories created for storing Lambda functions!"

cd code/pull_from_mdb
## Update the Sagemaker Endpoint and Eventbus
sed -i "s/<SAGEMAKER_ENDPOINT>/$sagemakerEndpoint/" app.py
sed -i "s/<REGION>/$awsRegion/" app.py

echo "Building and pushing the image to ECR..."

# aws ecr get-login-password --region $awsRegion | docker login --username AWS --password-stdin $awsID.dkr.ecr.$awsRegion.amazonaws.com
docker build -t cli_connected_vehicle_atlas_to_sagemaker .
docker tag cli_connected_vehicle_atlas_to_sagemaker:latest $awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_atlas_to_sagemaker:latest
docker push $awsID.dkr.ecr.$awsRegion.amazonaws.com/cli_connected_vehicle_atlas_to_sagemaker:latest
