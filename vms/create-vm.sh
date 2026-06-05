#!/usr/bin/env bash
# create-vm.sh — codified Flatcar VM creation for bluespeed fleet
# Usage: just create-vm NAME HOST=user@ip RAM=16384 VCPUS=8 DISK=60G
set -euo pipefail

VM_NAME="${1:?Usage: create-vm.sh <vm-name> <host> <ram-mb> <vcpus> <disk-gb>}"
HOST="${2:?Host required (user@ip)}"
RAM="${3:-16384}"
VCPUS="${4:-8}"
DISK_GB="${5:-60}"
IGNITION_CONFIG="vms/ignition/${VM_NAME}.ign"
IMAGE_DIR="/var/mnt/flatcar-images"
DISK_PATH="${IMAGE_DIR}/${VM_NAME}.qcow2"

echo "→ Creating Flatcar VM: ${VM_NAME}"
echo "  Host:    ${HOST}"
echo "  RAM:     ${RAM}MB"
echo "  vCPUs:   ${VCPUS}"
echo "  Disk:    ${DISK_GB}G"
echo "  Path:    ${DISK_PATH}"
echo ""

# Ensure image directory exists on remote host
ssh "${HOST}" "mkdir -p ${IMAGE_DIR}"

# Generate Ignition config from butane if not already present
if [[ ! -f "${IGNITION_CONFIG}" ]]; then
    BUTANE_CONFIG="vms/ignition/${VM_NAME}.bu"
    if [[ -f "${BUTANE_CONFIG}" ]]; then
        echo "→ Converting butane config to ignition..."
        if ! command -v butane &>/dev/null; then
            echo "butane not found, installing..."
            sudo dnf install -y butane 2>/dev/null || brew install butane 2>/dev/null
        fi
        butane --pretty --strict "${BUTANE_CONFIG}" > "${IGNITION_CONFIG}"
    else
        echo "→ No ignition config found at ${IGNITION_CONFIG} or ${BUTANE_CONFIG}"
        echo "  Create one first with: just ignition-template ${VM_NAME}"
        exit 1
    fi
fi

# Create disk image if it doesn't exist
ssh "${HOST}" "if [[ ! -f ${DISK_PATH} ]]; then \
    echo '→ Creating ${DISK_GB}G qcow2 disk...'; \
    qemu-img create -f qcow2 ${DISK_PATH} ${DISK_GB}G; \
fi"

# Copy ignition config to remote
scp "${IGNITION_CONFIG}" "${HOST}:${IMAGE_DIR}/${VM_NAME}.ign"

# Define the VM
ssh "${HOST}" "virt-install \
    --name ${VM_NAME} \
    --memory ${RAM} \
    --vcpus ${VCPUS} \
    --disk path=${DISK_PATH},format=qcow2 \
    --os-variant generic \
    --import \
    --graphics none \
    --console pty,target_type=serial \
    --network bridge=virbr0,model=virtio \
    --qemu-commandline='-fw_cfg name=opt/org.flatcar-linux/config,file=${IMAGE_DIR}/${VM_NAME}.ign'"

echo ""
echo "✓ VM '${VM_NAME}' created."
echo "  Connect: ssh ${HOST} virsh console ${VM_NAME}"
