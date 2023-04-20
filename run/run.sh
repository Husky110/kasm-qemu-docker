#!/usr/bin/env bash
set -eu

# Docker environment variabeles

: ${BOOT:=''}.                     # URL of the ISO file
: ${DEBUG:=''}.               # Enable debug mode
: ${ALLOCATE:='Y'}       # Preallocate diskspace
: ${CPU_CORES:='1'}     # vCPU count
: ${DISK_SIZE:='16G'}    # Initial disk size
: ${RAM_SIZE:='512M'} # Amount of RAM

echo "Starting QEMU for Docker v${VERSION}..."

STORAGE="/storage"
[ ! -d "$STORAGE" ] && echo "Storage folder (${STORAGE}) not found!" && exit 69
[ ! -f "/run/run.sh" ] && echo "Script must run inside Docker container!" && exit 60

if [ -f "$STORAGE/boot.img" ]; then
  . /run/install.sh
fi

# Initialize disks
. /run/disk.sh

# Initialize network
. /run/network.sh

# Configure shutdown
. /run/power.sh

KVM_OPTS=""

if [ -e /dev/kvm ] && sh -c 'echo -n > /dev/kvm' &> /dev/null; then
  if [[ $(grep -e vmx -e svm /proc/cpuinfo) ]]; then
    KVM_OPTS=",accel=kvm -enable-kvm -cpu host"
  fi
fi

if [ -z "${KVM_OPTS}" ]; then
  echo "Error: KVM acceleration is disabled.."
  [ "$DEBUG" != "Y" ] && exit 88
fi

DEF_OPTS="-nographic -nodefaults"
KVM_OPTS="-machine type=q35,usb=off${KVM_OPTS}"
RAM_OPTS=$(echo "-m ${RAM_SIZE}" | sed 's/MB/M/g;s/GB/G/g;s/TB/T/g')
CPU_OPTS="-smp ${CPU_CORES},sockets=1,cores=${CPU_CORES},threads=1"
SERIAL_OPTS="-serial mon:stdio -device virtio-serial-pci,id=virtio-serial0,bus=pcie.0,addr=0x3"
EXTRA_OPTS="-device virtio-balloon-pci,id=balloon0 -object rng-random,id=rng0,filename=/dev/urandom -device virtio-rng-pci,rng=rng0"
ARGS="${DEF_OPTS} ${CPU_OPTS} ${RAM_OPTS} ${KVM_OPTS} ${MON_OPTS} ${SERIAL_OPTS} ${NET_OPTS} ${DISK_OPTS} ${EXTRA_OPTS}"

set -m
(
  qemu-system-x86_64 ${ARGS} & echo $! > ${_QEMU_PID}
)
set +m

pidwait -F "${_QEMU_PID}" & wait $!
