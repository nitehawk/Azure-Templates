#!/bin/bash
# Create resource group and launch template
#
# Assume we have a valid login, but verify we are in proper mode

# Create group
GROUP=${1-democluster}
SITE=${2-West US}

# Create deployment
azure group deployment create --template-uri https://raw.githubusercontent.com/nitehawk/Azure-Templates/master/sge-on-sles12/azuredeploy.json -g $GROUP -e ../../democlusuter.parameters.json -n demodeployment
