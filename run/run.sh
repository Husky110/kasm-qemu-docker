#!/usr/bin/env bash
set -eu

# Docker environment variables

: ${BOOT:=''}             # URL of the ISO file
: ${DEBUG:='N'}         # Enable debug mode
: ${ALLOCATE:='Y'}      # Preallocate diskspace
: ${CPU_CORES:='1'}     # Amount of CPU cores
: ${DISK_SIZE:='16G'}   # Initial data disk size
: ${RAM_SIZE:='512M'}   # Maximum RAM amount

echo "Starting QEMU for Docker v${VERSION}..."

STORAGE="/storage"
KERNEL=$(uname -r | cut -b 1)

trap 'echo >&2 "Error - exited with status $? at line $LINENO:"; 
         pr -tn $0 | tail -n+$((LINENO - 3)) | head -n7 >&2' ERR

[ ! -d "$STORAGE" ] && echo "Storage folder (${STORAGE}) not found!" && exit 69
[ ! -f "/run/run.sh" ] && echo "Script must run inside Docker container!" && exit 60

if [ ! -f "$STORAGE/boot.img" ]; then
  . /run/install.sh
fi

# Initialize disks
. /run/disk.sh

# Initialize network
. /run/network.sh

# Configure shutdown
. /run/power.sh

KVM_ERR=""
KVM_OPTS=""

if [ -e /dev/kvm ] && sh -c 'echo -n > /dev/kvm' &> /dev/null; then
  if ! grep -q -e vmx -e svm /proc/cpuinfo; then
    KVM_ERR="(cpuinfo $(grep -c -e vmx -e svm /proc/cpuinfo))"
  fi
else
  [ -e /dev/kvm ] && KVM_ERR="(no write access)" || KVM_ERR="(device file missing)"
fi

if [ -n "${KVM_ERR}" ]; then
  echo "ERROR: KVM acceleration not detected ${KVM_ERR}, please enable it."
  [ "$DEBUG" != "Y" ] && exit 88
else
  KVM_OPTS=",accel=kvm -enable-kvm -cpu host"
fi

DEF_OPTS="-nographic -nodefaults -display none"
RAM_OPTS=$(echo "-m ${RAM_SIZE}" | sed 's/MB/M/g;s/GB/G/g;s/TB/T/g')
CPU_OPTS="-smp ${CPU_CORES},sockets=1,dies=1,cores=${CPU_CORES},threads=1"
MAC_OPTS="-machine type=q35,usb=off,dump-guest-core=off,hpet=off${KVM_OPTS}"
SERIAL_OPTS="-serial mon:stdio -device virtio-serial-pci,id=virtio-serial0,bus=pcie.0,addr=0x3"
EXTRA_OPTS="-device virtio-balloon-pci,id=balloon0 -object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0"

ARGS="${DEF_OPTS} ${CPU_OPTS} ${RAM_OPTS} ${MAC_OPTS} ${MON_OPTS} ${SERIAL_OPTS} ${NET_OPTS} ${DISK_OPTS} ${EXTRA_OPTS}"
ARGS=$(echo "$ARGS" | sed 's/\t/ /g' | tr -s ' ')

trap - ERR

set -m
(
  [ "$DEBUG" = "Y" ] && set -x
  qemu-system-x86_64 ${ARGS:+ $ARGS} & echo $! > "${_QEMU_PID}"
  { set +x; } 2>/dev/null
)
set +m

if (( KERNEL > 4 )); then
  pidwait -F "${_QEMU_PID}" & wait $!
else
  tail --pid "$(cat "${_QEMU_PID}")" --follow /dev/null & wait $!
fi
