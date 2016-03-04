#!/bin/bash
# Create resource group and launch template
#
# Assume we have a valid login, but verify we are in proper mode

#azure config mode arm

# Create group
GROUP=${1-democluster}
SITE=${2-West US}
azure group delete $GROUP

