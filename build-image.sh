#!/bin/sh

# Requires: libguestfs-tools, wget, qemu-utils, Proxmox VE environment

. ./build-vars

# Clean up any previous build
rm -f ${install_dir}${image_name}
rm -f ${install_dir}build-info

# Download latest Debian cloud image
wget -O ${install_dir}${image_name} ${cloud_img_url}

# Create build-info file
touch ${install_dir}build-info
echo "Base Image: ${image_name}" > ${install_dir}build-info
echo "Packages added at build time: ${package_list}" >> ${install_dir}build-info
echo "Build date: $(date)" >> ${install_dir}build-info
echo "Build creator: ${creator}" >> ${install_dir}build-info

# Customize image - add packages needed for autogrow
virt-customize \
  -a ${install_dir}${image_name} \
  --update \
  --install "${package_list} cloud-guest-utils" \
  --mkdir ${build_info_file_location} \
  --copy-in ${install_dir}build-info:${build_info_file_location}

# Resize the raw disk image (filesystem will expand during boot)
qemu-img resize ${install_dir}${image_name} +6G

# Remove any existing VM with same ID
qm destroy ${build_vm_id} 2>/dev/null

# Create the VM template
qm create ${build_vm_id} \
  --memory ${vm_mem} \
  --cores ${vm_cores} \
  --net0 virtio,bridge=vmbr0 \
  --ipconfig0 ip=dhcp,ip6=auto \
  --name ${template_name} \
  --ostype l26 \
  --boot c \
  --bootdisk virtio0 \
  --agent enabled=1

# Import the customized disk
qm importdisk ${build_vm_id} ${install_dir}${image_name} ${storage_location}
qm set ${build_vm_id} --virtio0 ${storage_location}:vm-${build_vm_id}-disk-0

# Attach cloud-init and metadata
qm set ${build_vm_id} \
  --ide0 ${storage_location}:cloudinit \
  --nameserver ${nameserver} \
  --searchdomain ${searchdomain} \
  --sshkeys ${keyfile} \
  --ciuser ${cloud_init_user}

# Convert to template
qm template ${build_vm_id}
