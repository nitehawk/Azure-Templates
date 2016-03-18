#!/bin/bash

# This script is run on the master node only by the deployment script.   It is downloaded from the azure storage system.
# $0 <storageacct> <storagecontainer> <storagekey>

# This script would be customized as needed for any given install.    Additional storage account info could be hardcoded into it if needed.

## Get our parameters
STACCT=$1
STCONT=$2
STKEY=$3

## Get our current path to call fileget script
EXPATH=`pwd`

### Setup master host for ansys

# License server
echo 127.0.0.1 xcatmn >> /etc/hosts

# Apps paths
mkdir -p /share/data/apps/ansys
ln -s /share/data/apps/ansys /ansys_inc

# Download fluent installer
mkdir /mnt/resource/ansys
cd /mnt/resource/ansys
${EXPATH}/azfileget.sh $STACCT $STCONT $STKEY FLUIDS_170_LINX64.tar
tar xvf FLUIDS_170_LINX64.tar
./INSTALL -silent -install_dir /ansys_inc -licserverinfo 2325:1055:xcatmn
