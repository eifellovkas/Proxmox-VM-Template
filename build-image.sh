#!/usr/bin/env bash

# This script will download and modify the desired image to prep for template build.
# Script is inspired by 2 separate authors work.
# Austins Nerdy Things: https://austinsnerdythings.com/2021/08/30/how-to-create-a-proxmox-ubuntu-cloud-init-image/
# What the Server: https://whattheserver.com/proxmox-cloud-init-os-template-creation/
# requires libguestfs-tools to be installed.
# This script is designed to be run inside the ProxMox VE host environment.
# Modify the install_dir variable to reflect where you have placed the script and associated files.

set -euo pipefail

# default: Debian
VARS_FILE="./build-vars"

usage() {
  echo "Použití: $(basename "$0") [-u] [-h]"
  echo "  (bez parametrů)  Debian (./build-vars)"
  echo "  -u               Ubuntu (./build-vars_ub)"
  echo "  -h               Nápověda"
}

# parametry
while getopts ":uh" opt; do
  case "$opt" in
    u) VARS_FILE="./build-vars_ub" ;;
    h) usage; exit 0 ;;
    \?) echo "Neznámý přepínač: -$OPTARG" >&2; usage; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

# načtení proměnných
if [[ ! -f "$VARS_FILE" ]]; then
  echo "Soubor s proměnnými '$VARS_FILE' nebyl nalezen." >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$VARS_FILE"

# Clean up any previous build
rm ${install_dir}${image_name}
rm ${install_dir}build-info

# Grab latest cloud-init image for your selected image
wget ${cloud_img_url}

# insert commands to populate the currently empty build-info file
touch ${install_dir}build-info
echo "Base Image: "${image_name} > ${install_dir}build-info
echo "Packages added at build time: "${package_list} >> ${install_dir}build-info
echo "Build date: "$(date) >> ${install_dir}build-info
echo "Build creator: "${creator} >> ${install_dir}build-info

virt-customize --update -a ${image_name}
virt-customize --install ${package_list} -a ${image_name}
virt-customize --mkdir ${build_info_file_location} --copy-in ${install_dir}build-info:${build_info_file_location} -a ${image_name}
qm destroy ${build_vm_id}
qm create ${build_vm_id} --memory ${vm_mem} --cores ${vm_cores} --net0 virtio,bridge=vmbr0 --ipconfig0 ip=dhcp,ip6=auto --name ${template_name}
qm importdisk ${build_vm_id} ${image_name} ${storage_location}
qm set ${build_vm_id} --scsihw ${scsihw} --virtio0 ${storage_location}:vm-${build_vm_id}-disk-0
qm set ${build_vm_id} --ide0 ${storage_location}:cloudinit
qm set ${build_vm_id} --nameserver ${nameserver} --ostype l26 --searchdomain ${searchdomain} --sshkeys ${keyfile} --ciuser ${cloud_init_user}
qm set ${build_vm_id} --boot c --bootdisk virtio0
#qm set ${build_vm_id} --serial0 socket --vga serial0
qm set ${build_vm_id} --agent enabled=1
qm template ${build_vm_id}