#!/bin/bash

# This script is run on the master node only by the deployment script.   It is downloaded from the azure storage system.
# $0 <storageacct> <storagecontainer> <storagekey>

# This script would be customized as needed for any given install.    Additional storage account info could be hardcoded into it if needed.

## Get our parameters
MASTER=$1
STACCT=$2
STCONT=$3
STKEY=$4

## Get our current path to call fileget script
EXPATH=`pwd`

### Setup master host for ansys

# License server
echo `host ${MASTER} | cut -d" " -f 4` xcatmn >> /etc/hosts

# Apps paths
ln -s /share/data/apps/ansys /ansys_inc

