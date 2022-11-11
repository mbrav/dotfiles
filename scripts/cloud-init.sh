#!/bin/bash

# cd /mnt/pve/store/cloud-images/
# qm create 1000 --memory 2048 --name ubuntu-22.04-cloud --net0 virtio,bridge=vmbr0
# qm importdisk 1000 jammy-server-cloudimg-amd64.img store
# qm set 1000 --scsihw virtio-scsi-pci --scsi0 store:1000/vm-1000-disk-0.raw
# qm set 1000 --ide2 store:cloudinit
# qm set 1000 --boot c --bootdisk scsi0
# qm set 1000 --serial0 socket --vga serial0
