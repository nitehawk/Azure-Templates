#!/bin/bash
# Based on MS Azure Slurm on sles12 deployment script

set -xeuo pipefail

if [[ $(id -u) -ne 0 ]] ; then
    echo "Must be run as root"
    exit 1
fi

if [ $# != 5 ]; then
    echo "Usage: $0 <MasterHostname> <WorkerHostnamePrefix> <WorkerNodeCount> <HPCUserName> <TemplateBaseUrl>"
    exit 1
fi

# Set user args
MASTER_HOSTNAME=$1
WORKER_HOSTNAME_PREFIX=$2
WORKER_COUNT=$3
TEMPLATE_BASE_URL="$5"
LAST_WORKER_INDEX=$(($WORKER_COUNT - 1))

# Shares
SHARE_HOME=/share/home
SHARE_DATA=/share/data
SHARE_OPT=/opt


# Hpc User
HPC_USER=$4
HPC_UID=7007
HPC_GROUP=users


# Returns 0 if this node is the master node.
#
is_master()
{
    hostname | grep "$MASTER_HOSTNAME"
    return $?
}

# Add the SLES 12 SDK repository which includes all the
# packages for compilers and headers.
#
add_sdk_repo()
{
    repoFile="/etc/zypp/repos.d/SMT-http_smt-azure_susecloud_net:SLE-SDK12-Pool.repo"
	
    if [ -e "$repoFile" ]; then
        echo "SLES 12 SDK Repository already installed"
        return 0
    fi
	
	wget $TEMPLATE_BASE_URL/sles12sdk.repo
	
	cp sles12sdk.repo "$repoFile"

    # init new repo
    zypper -n search nfs > /dev/null 2>&1
}

# Installs all required packages.
#
install_pkgs()
{
    pkgs="libbz2-1 libz1 openssl libopenssl-devel gcc gcc-c++ nfs-client rpcbind"

    if is_master; then
        pkgs="$pkgs nfs-kernel-server"
    fi

    zypper -n install $pkgs
}

# Partitions all data disks attached to the VM and creates
# a RAID-0 volume with them.
#
setup_data_disks()
{
    mountPoint="$1"
	createdPartitions=""

    # Loop through and partition disks until not found
    #16:  for disk in sdc sdd sde sdf sdg sdh sdi sdj sdk sdl sdm sdn sdo sdp sdq sdr; do
    for disk in sdc sdd; do
        fdisk -l /dev/$disk || break
        fdisk /dev/$disk << EOF
n
p
1


t
fd
w
EOF
        createdPartitions="$createdPartitions /dev/${disk}1"
	done

    # Create RAID-0 volume
    if [ -n "$createdPartitions" ]; then
        devices=`echo $createdPartitions | wc -w`
        mdadm --create /dev/md10 --level 0 --raid-devices $devices $createdPartitions
	    mkfs -t ext4 /dev/md10
	    echo "/dev/md10 $mountPoint ext4 defaults,nofail 0 2" >> /etc/fstab
	    mount /dev/md10
    fi
}

# Creates and exports two shares on the master nodes:
#
# /share/home (for HPC user)
# /share/data
#
# These shares are mounted on all worker nodes.
#
setup_shares()
{
    mkdir -p $SHARE_HOME
    mkdir -p $SHARE_DATA
    mkdir -p $SHARE_OPT

    if is_master; then
	    setup_data_disks $SHARE_DATA
        echo "$SHARE_HOME    *(rw,async)" >> /etc/exports
        echo "$SHARE_DATA    *(rw,async)" >> /etc/exports
        echo "$SHARE_OPT     *(rw,async)" >> /etc/exports
        service nfsserver status && service nfsserver reload || service nfsserver start
    else
        echo "master:$SHARE_HOME $SHARE_HOME    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
        echo "master:$SHARE_DATA $SHARE_DATA    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
        echo "master:$SHARE_OPT $SHARE_OPT    nfs4    rw,auto,_netdev 0 0" >> /etc/fstab
        mount -a
        mount | grep "^master:$SHARE_HOME"
        mount | grep "^master:$SHARE_DATA"
        mount | grep "^master:$SHARE_OPT"
    fi
}


# Adds a common HPC user to the node and configures public key SSh auth.
# The HPC user has a shared home directory (NFS share on master) and access
# to the data share.
#
setup_hpc_user()
{
    if is_master; then
        useradd -c "HPC User" -g $HPC_GROUP -d $SHARE_HOME/$HPC_USER -s /bin/bash -m -u $HPC_UID $HPC_USER

        # Configure public key auth for the HPC user
        sudo -u $HPC_USER ssh-keygen -t rsa -f $SHARE_HOME/$HPC_USER/.ssh/id_rsa -q -P ""
        cat $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub > $SHARE_HOME/$HPC_USER/.ssh/authorized_keys

        echo "Host *" > $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    StrictHostKeyChecking no" >> $SHARE_HOME/$HPC_USER/.ssh/config
        echo "    UserKnownHostsFile /dev/null" >> $SHARE_HOME/$HPC_USER/.ssh/config
		echo "    PasswordAuthentication no" >> $SHARE_HOME/$HPC_USER/.ssh/config

        chown $HPC_USER:$HPC_GROUP $SHARE_HOME/$HPC_USER/.ssh/authorized_keys
        chown $HPC_USER:$HPC_GROUP $SHARE_HOME/$HPC_USER/.ssh/config
        chown $HPC_USER:$HPC_GROUP $SHARE_DATA

	# Load SGE config
	echo "source /opt/sge/default/common/settings.sh" >> $SHARE_HOME/$HPC_USER/.bashrc
    else
        useradd -c "HPC User" -g $HPC_GROUP -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER
    fi

    # Don't require password for HPC user sudo
    echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
}

# Sets all common environment variables and system parameters.
#
setup_env()
{
    # Set unlimited mem lock
    echo "$HPC_USER hard memlock unlimited" >> /etc/security/limits.conf
	echo "$HPC_USER soft memlock unlimited" >> /etc/security/limits.conf

	# Intel MPI config for IB
    echo "# IB Config for MPI" > /etc/profile.d/hpc.sh
	echo "export I_MPI_FABRICS=shm:dapl" >> /etc/profile.d/hpc.sh
	echo "export I_MPI_DAPL_PROVIDER=ofa-v2-ib0" >> /etc/profile.d/hpc.sh
	echo "export I_MPI_DYNAMIC_CONNECTION=0" >> /etc/profile.d/hpc.sh
}

setup_hosts()
{
	
	# Master
	echo `host ${MASTER_HOSTNAME} | cut -d" " -f 4` $MASTER_HOSTNAME >> /etc/hosts

	#Compute
	for i in `seq 0 $LAST_WORKER_INDEX`;
	do
		CNAME=${WORKER_HOSTNAME_PREFIX}${i}
		echo `host ${CNAME} | cut -d" " -f 4` $CNAME >> /etc/hosts
	done
}

setup_sge()
{
    pkgs="xterm db48-utils xorg-x11-fonts xorg-x11-fonts-core libXm4"
    zypper -n install $pkgs

    if is_master; then
	    # Master node
	    # Install SGE RPMs
	    # Download RPMs from repo
	    wget $TEMPLATE_BASE_URL/rpm/gridengine-execd-8.1.8-1.x86_64.rpm
	    wget $TEMPLATE_BASE_URL/rpm/gridengine-8.1.8-1.x86_64.rpm
	    wget $TEMPLATE_BASE_URL/rpm/libhwloc5-1.9-13.1.x86_64.rpm 
	    wget $TEMPLATE_BASE_URL/rpm/hwloc-data-1.9-13.1.x86_64.rpm
	    wget $TEMPLATE_BASE_URL/rpm/gridengine-qmaster-8.1.8-1.x86_64.rpm
	    wget $TEMPLATE_BASE_URL/rpm/gridengine-qmon-8.1.8-1.x86_64.rpm 
	    rpm -ivh gridengine-execd-8.1.8-1.x86_64.rpm gridengine-8.1.8-1.x86_64.rpm libhwloc5-1.9-13.1.x86_64.rpm  hwloc-data-1.9-13.1.x86_64.rpm gridengine-qmaster-8.1.8-1.x86_64.rpm gridengine-qmon-8.1.8-1.x86_64.rpm
	    # Configure qmaster
	    wget $TEMPLATE_BASE_URL/sge.conf
	    cat sge.conf | sed -e 's/xxCUREXECHOSTxx//' > /opt/sge/sge.master.conf
	    pushd /opt/sge
	    /opt/sge/install_qmaster -auto sge.master.conf
	    popd

	    # Use a temporary environment file during install
	    wget $TEMPLATE_BASE_URL/sge-installer-env
	    source sge-installer-env

	    # Add worker nodes as admin hosts
	    for i in `seq 0 $LAST_WORKER_INDEX`; do qconf -ah ${WORKER_HOSTNAME_PREFIX}${i}; done
	    
    else
	    # Worker node
	    # RPM install unneeded - shared /opt
	    # Configure execd
	    HOST=`hostname`
	    wget $TEMPLATE_BASE_URL/sge.conf
	    cat sge.conf | sed -e "s/xxCUREXECHOSTxx/${HOST}/" > /tmp/sge.${HOST}.conf
	    pushd /opt/sge
	    /opt/sge/install_execd -auto /tmp/sge.${HOST}.conf
	    popd
	    # Use a temporary environment file during install
	    wget $TEMPLATE_BASE_URL/sge-installer-env
	    source sge-installer-env

    fi
}

add_sdk_repo
install_pkgs
setup_shares
setup_hpc_user
setup_env
setup_hosts
setup_sge
