#!/bin/sh
cat esxi-vm-provision.sh | ssh vmhost "cat > /vmfs/volumes/datastore1/esxi-vm-provision.sh ; chmod +x /vmfs/volumes/datastore1/esxi-vm-provision.sh"
