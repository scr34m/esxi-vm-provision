ESXi-vm-provision
=================

Simple script to provision a new Virtual Machine on a ESXi Host 5.0+

Example
-------

1. enable SSH on ESXi

	http://pubs.vmware.com/vsphere-50/index.jsp?topic=%2Fcom.vmware.vcli.migration.doc_50%2Fcos_upgrade_technote.1.4.html

2. download template to datastore (default is /vmfs/volumes/datastore1/template.tar.gz)

	```
	wget URL_TEMPLATE -O /tmp/template.tar.gz
	scp /tmp/template.tar.gz vmhost:/vmfs/volumes/datastore1/
	```

3. download script to host and set execution permission, e.g.

	```
	curl "https://raw.githubusercontent.com/eramo-software/esxi-vm-provision/master/esxi-vm-provision.sh" | ssh vmhost "cat > /vmfs/volumes/datastore1/esxi-vm-provision.sh ; chmod +x /vmfs/volumes/datastore1/esxi-vm-provision.sh"
	```

4. execute script

	```
	ssh vmhost "sh /vmfs/volumes/datastore1/esxi-vm-provision.sh --name Robin --ip 192.168.0.100 --gateway 192.168.0.1 --dns 192.168.0.150 --hostname robin"
	```

Usage
-----

```
esxi-vm-provision.sh -n name [OPTIONS]

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
```

Creating a template VM
----------------------

It's simply a linux virtual machine with VMWare Guest Tools, the SSH server and the insecure key (included on the repository and hard-coded into the main script file).

1. create new VM with name Template (ESXi has some limitations on disk types, so it's better to create this VM on a ESXi server itself)

2. install VMWare Tools:

    1. Activate the installation on the host 
    2. Inside VM, execute:

		```
	    sudo mount /dev/cdrom /media/cdrom
	    tar xzvf /media/cdrom/VMwareTools*.tar.gz -C /tmp/
	    cd /tmp/vmware-tools-distrib/
	    sudo ./vmware-install.pl -d
	    ```

3. put the insecure key with root access on vm, as root execute:

	```
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDHbX6SCVslixgMzi2CTOsjhISl1aurDtn4SaAF4AGNUKd5xgwp/0RuSUCe2mTTAHdeqNl+C5IXzPPR+zxrWEGkFw9C17wHALswpmUJ9ibEfITvRXUvPJ9xAPy5ARBjfhlkZav7239/hLCo1MnzMHu+KilufL50e5e6JKSFi/SjkDw2110NgCnj86gTBP783/X9sZIdHH0opHC3z0CpxdOl2FBzTJ6Y9uNISgdmgHbAjPvsWwHlxcxhV1fbUHmJ0J/hIrVw6kmSHhxEUBxIA6Ok+Qpaq2kWOc0Kdw5En1HF99BnACQRkgLXLhRDM54LCSVs7Zj+WKasDG3gRePAQVKh template" > ~/.ssh/authorized_keys
    ```

Packaging
---------

The only requirements in packaging are:

1. edit .vmx to remove bios info and set uuid.action to 'change'

	```
    sed -i "s/uuid\.bios = \"[^\"]*\"/uuid.bios = \"\"/" Template.vmx
    echo "uuid.action = \"change\"" >> Template.vmx
    ```

2. compress vm with .tar.gz

	```
    tar -zcf template.tar.gz Template/
    ```
	


