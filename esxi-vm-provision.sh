#!/bin/bash

# Default variables
path='/vmfs/volumes/datastore1'
image='/vmfs/volumes/datastore1/template.tar.gz'
vm_netmask='255.255.255.0'

# Print usage
usage() {
  echo -n "$(basename $0) -n name [OPTIONS]

Creates a new Virtual Machine on a VMWare ESXi Host based on a template.

 Options:
  -n, --name        Name of the new Virtual Machine
  -u, --username    Username to create
  -p, --password    Password for the created user
  -H, --hostname    Set hostname
  -s, --size        Resizes main disk to n MB
  -x, --size_aux    Password for the created user
  -P, --path        Path in ESXi Host to store VM files (defaults to /vmfs/volumes/datastore1)
  -I, --image       Path to a template image (defaults to /vmfs/volumes/datastore1/template.tar.gz)
  -i, --ip          IP address for the new VM
  -N, --netmask     Netmask for the new VM (default is 255.255.255.0)
  -g, --gateway     Gateway IP address for the new VM
  -D, --dns         DNS Server IP address
  -m, --memory      Reconfigures the amount of RAM 
  -k, --public_key  Defines a new publick key to register on new machine
  -d, --debug       Print debugging information
  -h, --help        Display this help and exit
"
}

while [[ ! -z "$1" ]]; do
  case $1 in
    -n|--name) shift; vm_name=$1 ;;
    -u|--username) shift; vm_user=$1 ;;
    -p|--password) shift; vm_pass=$1 ;;
	-H|--hostname) shift; hostname=$1 ;;
    -s|--size) shift; size=$1 ;;
    -x|--size_aux) shift; size_aux=$1 ;;
    -P|--path) shift; path=$1 ;;
    -I|--image) shift; image=$1 ;;
    -i|--ip) shift; VM_IP=$1 ;;
    -N|--netmask) shift; vm_netmask=$1 ;;
    -g|--gateway) shift; vm_gateway=$1 ;;
    -D|--dns) shift; vm_dns=$1 ;;
    -m|--memory) shift; RAM=$1 ;;
    -k|--public_key) shift; pub_key=$1 ;;
    -d|--debug) debug="1" ;;
    -h|--help) usage >&2; exit 1 ;;
    --endopts) shift; break ;;
    *) echo "invalid option: $1" ; exit 1 ; usage ;;
  esac
  shift
done

# Print debuging information
if [[ $debug ]]; then
	echo "VM_NAME = $vm_name"
	echo "VM_HOSTNAME = $hostname"
	echo "DISK_SIZE = $size"
	echo "RAM = $RAM"
	echo "AUX_DISK_SIZE = $size_aux"
	echo "VM_USER = $vm_user"
	echo "VM_PASSWORD = $vm_pass"
	echo "VM_IP = $VM_IP"
	echo "VM_NETMASK = $vm_netmask"
	echo "VM_GATEWAY = $vm_gateway"
	echo "VM_DNS = $vm_dns"
	echo "PUB_KEY = $pub_key"
	echo "PATH = $path"
	echo "IMAGE = $image"
fi

# Only name parameter is required
if [[ -z "$vm_name" ]] ; then
	echo "Error: At least the name must be defined"
	exit 1
fi

# If has a username must have a password
if [[ ! -z "$vm_user" ]]; then
	if [[ -z "$vm_pass" ]]; then
		echo "Error: Password must be defined if there is a username"
		exit 1;
	fi
fi
# If has a ip addres defined must have also netmask, gateway and dns
if [[ ! -z "$VM_IP" ]]; then
	if [[ -z "$vm_gateway" ]]; then
		echo "Error: With ip address gateway must also be defined"
		exit 1;
	fi
	if [[ -z "$vm_dns" ]]; then
		echo "Error: With ip address dns server must also be defined"
		exit 1;
	fi
fi

cd $path

if [ -d "$path/$vm_name" ]; then
	ls "$path/$vm_name" -lha | grep ".lck$" > /dev/null
	if [[ $? = 0 ]]; then
		echo "VM '$vm_name' already exists, and is running."
		echo "Try another name, or stop the VM and try again."
		exit
	else
		DATE=`date +%Y-%m-%d-%H-%M-%S`
		echo "Directory '$path/$vm_name' already exists, but its VM is not running."
		echo "Renaming old '$path/$vm_name' to '$path/$vm_name.$DATE'"
		mv "$path/$vm_name" "$path/$vm_name.$DATE"
	fi
fi

# Verifies if there is a VM registered with the same name
if [[ $(vim-cmd vmsvc/getallvms | egrep -v "^Vmid" | grep "$vm_name" | wc -l) -ne 0 ]]; then
	echo "There is already a VM with this name: '$vm_name'"	
	exit
fi	

# Extracts the template
echo "extracting VM from $image"
tar -zxf $image

# Renames the template to the new name provided by the user
echo "moving VM files from $path/template to $path/$vm_name"
mv $path/Template "$path/$vm_name"

# Resizes the main vmdk
if [[ ! -z "$size" ]]; then
	vmkfstools -X "${size}m" "$path/$vm_name"/Template.vmdk
fi

# If there is a defined amount of memory set it on the vmx file
if [[ ! -z "$RAM" ]]; then
	sed "s/memsize = .*/memsize = \"$RAM\"/" -i "$path/$vm_name"/Template.vmx
fi

# Register the .vmx as a VM on ESXi
# Its required on the .vmx the following parameters:
#
# uuid.bios = ""
# uuid.action = "change"
#
# To avoid the user's input when starting the VM

echo "registering VM at ESXi server"
VM_ID=$(vim-cmd solo/registervm "$path/$vm_name/Template.vmx" "$vm_name" | tail -n 1 )

# If there is a second disk size specified creates the vmdk file and adds it to the registered VM
if [[ ! -z "$size_aux" ]]; then
	echo "adding $size_aux""MB disk to VM"
	vim-cmd vmsvc/device.diskadd $VM_ID $(( $size_aux * 1024 )) 1000 1 "datastore1"
fi

# Starting the virtual machine
echo "The new vmid on ESXi is $VM_ID "
vim-cmd vmsvc/power.on $VM_ID

# Wait until Wmware Guest Tools reports itself as ready
wait_to_boot(){

	echo -n "Waiting for VM to boot"
    sleep 2
    guest_ok=1
    timeout=0
	while [[ ! $guest_ok = 0 ]]; do
		echo -n "."
		vim-cmd vmsvc/get.guest $VM_ID | grep "guestOperationsReady = true" > /dev/null
		guest_ok=$?
		timeout=$((timeout+1))
		if [[ $timeout = 60 ]]; then
			echo "There was a problem starting the virtual machine, no VMWare Guest Tools response was detected within 60 seconds."
			exit 1
		fi
		sleep 1
	done

	echo "done"

}

wait_for_ip(){

	echo -n "Waiting for IP to connect"

	vm_ip=""
    timeout=0
	while [[ -z "$vm_ip" ]]; do
		echo -n "."
		vm_ip=$( vim-cmd vmsvc/get.guest $VM_ID |grep -m 1 "ipAddress = \"" | sed "s/.*ipAddress = \"\(.*\..*\..*\..*\)\".*/\1/g" )
		timeout=$((timeout+1))
		if [[ $timeout = 60 ]]; then
			echo "There was a problem getting virtual machine IP address within 60 seconds."
			exit 1
		fi
		sleep 1
	done

	echo "done"
	echo "Current VM IP is: $vm_ip"

}

wait_to_boot

wait_for_ip

# In ESXi 5.5 the internal firewall blocks outgoing ssh connections
# This command allows it so we can connect to the newly created VM
esxcli network firewall ruleset set --enabled 1 -r sshClient

# Unsecure private key allows that must be allowed root access on template
echo "-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAx21+kglbJYsYDM4tgkzrI4SEpdWrqw7Z+EmgBeABjVCnecYM
Kf9EbklAntpk0wB3XqjZfguSF8zz0fs8a1hBpBcPQte8BwC7MKZlCfYmxHyE70V1
LzyfcQD8uQEQY34ZZGWr+9t/f4SwqNTJ8zB7viopbny+dHuXuiSkhYv0o5A8Ntdd
DYAp4/OoEwT+/N/1/bGSHRx9KKRwt89AqcXTpdhQc0yemPbjSEoHZoB2wIz77FsB
5cXMYVdX21B5idCf4SK1cOpJkh4cRFAcSAOjpPkKWqtpFjnNCncORJ9RxffQZwAk
EZIC1y4UQzOeCwklbO2Y/limrAxt4EXjwEFSoQIDAQABAoIBAC8KmfeSs2hYthSX
Mc7xm+ml4bBIhZT1DN9vZorcOyF9a/Pijo39g8PMDa0q8OuAyaePhrYfvpdUphLb
A3aCvAEb22K2BslUF9Oy/FRsNtrUUHssVCcPUsDSLcrqAFansQ+ol/fx39JRl2ZL
w1NVFWtXAKzqSfaqDLFA4XoK+Gr4OKrFbqFlZeT0EePNrcC0u7xwwS31JILU56rH
TxUZpgshFVgS395dU/cJSLDENTrmfbrU09sw1vZFLqOjPPLGo0I5XDWdUvUlYR/q
WFDZyDq8LE43a7+Zi0CQzEW0Xgamlng+q9EFx0mqjRBkdpQB2bXW1B6wfbJHMKcd
oZHcHQ0CgYEA/Htu+csf2sRpjHGvPu/r4HtDNw7oEO0vmqPpFV6vRQ8c6rl8zQAq
4Wy+6Iggn+EKHk+darquLBJfYT/7Z8hXwr8zD3QXkX2qBDvSeuLDzVRCFnKpnZfI
vo3jafNzIFIH+NJiUMvXHtYagoPJ3FocMlPS3g0mmtmHtiQOEQ4CsXcCgYEAyjTS
1A1EnbX4cwkfilLlAdVa53BVZwQsJXzjtDh6rQvTQJzHUw73H7WIxgpTfFaQrsrA
XHaLXG1vvigtMyxoDg2KZM7ghUQoNjeQF0hNDPiXtBgq9qYUzbxILlG5npUhH1qj
Sf7gdcHi67PDQ3apH/KPfri/xri4TZS8BrPwYqcCgYEAjNYZkFMjALghHEtp8tSI
Id8AHl09S/vSWxNleBsp736/pZs0J3IZeUdcsn8Em8o/B6tnZtqdP048UBYNmdWi
Rqq6w7sBTpHnXZc1EIEfsZB3kOgC/zpkqw6gtUAsjvHTKpPIbcNWywepH/Z9imHl
aplhfaWeTDBdSFeSVScYj38CgYB2Sk6ntJdWd7S/fy/PWM0VtH24dPPRDxTQXW5L
6NqDTy6nVtAYW+Hfz/ASgsnyLCX5yyybKtI+INtE7/X5QNoilnNGo+ueqo+nn/uQ
U0CX/PmqZpUDs4bqEGJdjnu7NNyqnfh2ej9PRDx+zKvHVKx9vwWJCYVPOJLA9+jD
NxLCcwKBgQC+ZFUwsDMHEGCS1z8MKZzYIHJL97484MfrcqIbmrDPNLRNzP7niSKv
tdSVxxs/ytiXWCO3JDCesTSWAEMD0qAUfJlMBJEgPLpyLj/5GYe9js/r7ejatpiP
K05dxjZv/xZDv/TaPTbJgz1+tb3WHcGFoNqwBVATO8IXZKA0LcC8CA==
-----END RSA PRIVATE KEY-----" > /tmp/template-rsa-private-key
chmod 600 /tmp/template-rsa-private-key

# Runs a ssh remote command
ssh_vm(){
	if [[ $debug ]]; then
		ssh -o "StrictHostKeyChecking no" -i /tmp/template-rsa-private-key root@$vm_ip "$@"
	else
		ssh -o "StrictHostKeyChecking no" -i /tmp/template-rsa-private-key root@$vm_ip "$@" > /dev/null
	fi
	
}

# Creates a new disk
create_new_disk(){
	echo "creating partition on disk at $1"
	ssh_vm "fdisk $1 <<< 'n
	p



	t
	83
	w'"

	echo "formatting disk at $1"
	ssh_vm mkfs.ext3 $1'1' -F

	echo "creating folder at $2"
	ssh_vm mkdir -p $2

	echo "mounting $1 at $2"
	ssh_vm mount $1'1' $2

	echo "setting up automatic mounting on system start"
	
	ssh_vm "echo \"UUID=\`blkid | grep $1 | sed \\\"s/.*UUID=\\\\\\\"\\([^\\\\\\\"]*\\)\\\\\\\".*/\\\\1/i\"\`	$2	auto	rw,user,auto,exec	0	0\" >> /etc/fstab"
}

# Creates a new user
create_user(){
	echo "creating user $1"
	ssh_vm adduser --disabled-password --gecos "\"\"" $1
	ssh_vm adduser $1 sudo

	echo "setting password"
	ssh_vm "echo '$1:$2' | chpasswd"
}

# Change the VM hostname
change_hostname(){
	
	echo "changing hostname to $1"

	# Updates the hostname
	ssh_vm hostname "$1"
	ssh_vm "echo $1 > /etc/hostname"

	# Add the new hostname to hosts file
	ssh_vm "sed -i 's/127.0.0.1/127.0.0.1\t$1/' /etc/hosts"
}

cleanup_known_hosts(){
	known_hosts_file="~/.ssh/known_hosts"
	if [ -f "$known_hosts_file" ]; then
		egrep -v "^$1" $known_hosts_file > /tmp/known_hosts && mv /tmp/known_hosts $known_hosts_file
	fi
}

# Cleanup the knows_hosts file on the host to prevents ssh key problems
cleanup_known_hosts $vm_ip

# If there is a new size to the vm's main partition we now resize this partition
# to occupy all the avaiable space on disk
if [[ ! -z "$size" ]]; then

	echo "preparing new partition table for main disk."

	ssh_vm "fdisk /dev/sda <<< \"d
n
p



w
\""
	
	# Restarts to update partition table
	echo "rebooting."
    ssh_vm /sbin/reboot

    # Waits for a reboot
    wait_to_boot

	# Extends the filesystem
	ssh_vm resize2fs /dev/sda1
	
fi

# If there is a auxiliary new disk mounts it
if [[ ! -z "$size_aux" ]]; then
	create_new_disk /dev/sdb /dados
fi

# Create the specified user
if [[ ! -z "$vm_user" ]]; then
	create_user $vm_user $vm_pass
fi

# Changes the virtual machine hostname
if [[ ! -z "$hostname" ]]; then
	echo "setting up new hostname as $hostname"
	change_hostname $hostname
fi

# Adds a public key to access
if [[ ! -z "$pub_key" ]]; then
	echo "installing public key"
	ssh_vm "echo \"$pub_key\" >> ~/.ssh/authorized_keys"
fi

# Sets a new IP Address 
if [[ ! -z "$VM_IP" ]]; then
	
	echo "setting $VM_IP as machine IP"
	
	# Cleanup ssh local hosts keys
	cleanup_known_hosts $VM_IP

	# 
	ssh_vm echo "\"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address $VM_IP
    netmask $vm_netmask
    gateway $vm_gateway
    dns-nameservers $vm_dns\" > /etc/network/interfaces"
    
    echo "New machine IP will be set as $VM_IP and machine will reboot NOW"
    
    # Restarts to use new ip address
    ssh_vm /sbin/reboot

    # Wait for boot again
    wait_to_boot

	wait_for_ip
fi

rm /tmp/template-rsa-private-key

echo "VM IP is:"
echo $vm_ip
