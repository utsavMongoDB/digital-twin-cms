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


# apiKey="aeewzbjo"
# pvtApiKey="20cd1330-cfb4-4ddc-8c96-49ffb3cee1be"
# awsID="979559056307"
# awsRegion="us-east-1"


echo "---------------------- MONGODB ATLAS SETUP ----------------------------"

# Update AWS Account ID
cd ../atlas-backend/Connected-Vehicle/triggers
sed -i 1 "s/<ACCOUNT_ID>/$awsID/" eventbridge_publish_battery_telemetry.json
sed -i 1 "s/<REGION>/$awsRegion/" eventbridge_publish_battery_telemetry.json
rm eventbridge_publish_battery_telemetry.json1  


cd ../../
echo "Logging in to Atlas..."

appservices login --api-key=$apiKey --private-api-key=$pvtApiKey

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
sed -i 1 "s/connected-vehicle-.*/"$app_id"\"/" config.ts
cd ../..
npm install
npm run build
echo "Starting the web-app..."
# nohup npm start > start.log 2>&1 &
# echo "Web-app started successfully!"
