#! /bin/sh

# Requires: libguestfs-tools, wget, qemu-utils, Proxmox VE environment

. ./build-vars

# Clean up any previous build
rm -f ${install_dir}${image_name}
rm -f ${install_dir}build-info
rm -f ${install_dir}${image_name}_resized.qcow2

# Download latest cloud-init image
wget -O ${install_dir}${image_name} ${cloud_img_url}

# Create build info
touch ${install_dir}build-info
echo "Base Image: ${image_name}" > ${install_dir}build-info
echo "Packages added at build time: ${package_list}" >> ${install_dir}build-info
echo "Build date: $(date)" >> ${install_dir}build-info
echo "Build creator: ${creator}" >> ${install_dir}build-info

# Customize image
virt-customize --update -a ${install_dir}${image_name}
virt-customize --install ${package_list} -a ${install_dir}${image_name}
virt-customize --mkdir ${build_info_file_location} --copy-in ${install_dir}build-info:${build_info_file_location} -a ${install_dir}${image_name}

# Identify correct root partition
ROOT_PART=$(virt-filesystems -a ${install_dir}${image_name} --partition --all | grep '/dev/' | grep -vE 'boot|efi' | head -n1)

# Resize disk image safely
qemu-img create -f qcow2 ${install_dir}${image_name}_resized.qcow2 8G
virt-resize --expand ${ROOT_PART} -a ${install_dir}${image_name} -o ${install_dir}${image_name}_resized.qcow2

# Build Proxmox VM Template with VirtIO
qm destroy ${build_vm_id} 2>/dev/null
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

# Import disk and attach as virtio
qm importdisk ${build_vm_id} ${install_dir}${image_name}_resized.qcow2 ${storage_location}
qm set ${build_vm_id} --virtio0 ${storage_location}:vm-${build_vm_id}-disk-0

# Cloud-init and other metadata
qm set ${build_vm_id} \
  --ide0 ${storage_location}:cloudinit \
  --nameserver ${nameserver} \
  --searchdomain ${searchdomain} \
  --sshkeys ${keyfile} \
  --ciuser ${cloud_init_user}

# Finalize template
qm template ${build_vm_id}

