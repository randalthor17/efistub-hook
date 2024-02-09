#!/bin/bash

usage() {
	printf "Usage: $0 [-h|--help]\n[-c|--create] [-R|--enable-swap-resume]\n\t[-r|--root-device <device>]\n\t[-s|--swap-device <device>]\n\t[-b|--boot-device <device>]\n\t[--rpm <kernel-xxx>][-k|--kernel <vmlinuz-xxx-xxx>]\n\t[-i|--initrd <initramfs-xxx.img>]\n[-d|--remove] [-k|--kernel <vmlinuz-xxx-xxx>]\n\t[--rpm <kernel-xxx>]\n[-p|--pretend]\n"
}
#
# Find the mounted root device
ROOTDEV=$(df -P / | tail -1 | awk '{print $1}')
# Find the swapfile if it exists
SWAPDEV=$(swapon --show=NAME --noheadings --raw | awk '!/zram/ {print $1}' | tail -1)
# Find the boot partition
BOOTDEV=$(findmnt -n -M /boot -r | awk '{print $2}')

# Set up the getopt options
OPTS=$(getopt -o "hcdRr:s:b:k:i:p" --long "help,create,remove,enable-swap-resume,root-device:,swap-device:,boot-device:,kernel:,initrd:,rpm:,pretend" -- "$@")
eval set -- "$OPTS"
unset OPTS

# parse the options
while true; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	-c | --create)
		CREATE=true
		shift
		;;
	-d | --remove)
		REMOVE=true
		shift
		;;
	-s | --swap-device)
		SWAPDEV=$2
		shift 2
		;;
	-r | --root-device)
		ROOTDEV=$2
		shift 2
		;;
	-b | --boot-device)
		BOOTDEV=$2
		shift 2
		;;
	-R | --enable-swap-resume)
		ENABLE_SWAP_RESUME=true
		shift
		;;
	-k | --kernel)
		KERNEL=$2
		shift 2
		;;
	-i | --initrd)
		INITRD=$2
		shift 2
		;;
	--rpm)
		RPM=$2
		shift 2
		;;
	-p | --pretend)
		PRETEND=true
		shift
		;;
	--)
		shift
		break
		;;
	*)
		echo "Unexpected option: $1"
		exit 1
		;;
	esac
done

#check if RPM package name has been supplied, and create kernel and initrd names from them
if [ ! -z "${RPM}" ]; then
	KERNEL=${RPM/kernel/vmlinuz}
	INITRD=${RPM/kernel/initramfs}.img
fi

# check if kernel and initramfs have been supplied as arguments
if [ -z "${KERNEL}" ] || [ -z "${INITRD}" ]; then
	usage
	exit 1
fi

# check if create and remove options have been supplied, or that both havent been supplied at the same time
if [[ ${CREATE} == ${REMOVE} ]]; then
	usage
	exit 1
fi

create() {
	# check if the kernel and initrd files exist
	if [ ! -f "/boot/${KERNEL}" ]; then
		echo "Kernel file not found: ${KERNEL}"
		exit 1
	fi
	if [ ! -f "/boot/${INITRD}" ]; then
		echo "Initrd file not found: ${INITRD}"
		exit 1
	fi

	# find uuid for the root and swapfiles
	ROOTUUID=$(blkid -s UUID -o value ${ROOTDEV})
	SWAPUUID=$(blkid -s UUID -o value ${SWAPDEV})
	# find the physical device from boot device id
	BOOTPHYSDEV=${BOOTDEV%?}
	BOOTDEVNUM=${BOOTDEV:0-1}
	# get boot device label
	BOOTDEVLABEL=$(blkid -s LABEL -o value ${BOOTDEV})

	# get os name from /etc/os-release
	OS_NAME=$(grep -oP '(?<=^NAME=).+' /etc/os-release | tr -d '"')
	# generate label for the efibootmgr entry
	LABEL="${OS_NAME} ${KERNEL} from ${BOOTDEVLABEL}"

	# generate the command to run
	CMD="efibootmgr --create --disk ${BOOTPHYSDEV} --part ${BOOTDEVNUM} --label \"${LABEL}\" --loader /${KERNEL}"
	if [[ ${ENABLE_SWAP_RESUME} == true ]]; then
		CMD="${CMD} --unicode 'root=UUID=${ROOTUUID} resume=UUID=${SWAPUUID} rw quiet splash initrd=\\${INITRD}'"
	else
		CMD="${CMD} --unicode 'root=UUID=${ROOTUUID} rw quiet splash initrd=\\${INITRD}'"
	fi
}

remove() {
	BOOTID=$(efibootmgr | grep "${KERNEL}" | tr -d "Boot" | head -c 4)
	CMD="efibootmgr -Bb ${BOOTID}"
}

if [[ ${CREATE} == true ]]; then
	create
elif [[ ${REMOVE} == true ]]; then
	remove
fi

printf "Generated Command: ${CMD}\n"
if [[ ${PRETEND} == true ]]; then
	exit 0
fi
eval ${CMD}
