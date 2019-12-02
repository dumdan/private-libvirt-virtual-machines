#!/bin/bash
#

# This is running on the "hypervisor".
# There are a lot of hard-coded parameters that need to be sorted-out
# The boot image(s), also, need to be brought there.

# None of these tasks/issues is hard - they just need to be taken care of, eventually.

vmName="gcpsdk"
domainName="oryx"
networkName="default"
ipAddress="192.168.122.41"
diskSize="20G"
memSize="8192"
vCPUs="4"
dckDiskSize="20G"

netIpAddress="192.168.122.0"
netPrefix="24"
netMask="$(ipcalc -m ${netIpAddress}/${netPrefix} | cut -f2 -d'=')"
netBcast="$(ipcalc -b ${netIpAddress}/${netPrefix} | cut -f2 -d'=')"
gatewayAddress="$(ipcalc --minaddr ${netIpAddress}/${netPrefix} | cut -f2 -d'=')"
dnsSrv="${gatewayAddress}"

hypervisor="qemu:///system"
poolName="default"
poolType="dir"
dirPoolPath="/var/lib/libvirt/images"
diskFormat="qcow2"
# configureSwap="False"

sourceImage="/home/daniel-work/dist/cos/CentOS-7-x86_64-GenericCloud-1907.qcow2c"

# sourceImage="/home/daniel-work/dist/f31/Fedora-Cloud-Base-31-1.9.x86_64.qcow2"
# sourceImage="/home/daniel-work/dist/f30/Fedora-Cloud-Base-30-1.2.x86_64.qcow2"
# sourceImage="/home/daniel-work/dist/cos/CentOS-7-x86_64-GenericCloud-1907.qcow2c"

vmdefined="$(virsh --connect=qemu:///system list --all | awk -v vm=${vmName} '$0 ~ vm {print $2}')"
[[ -n "${vmdefined}" ]] && {
    echo -e "Error: VM already defined\x21 You would need to delete it, first...";
    exit 255
}

if [[ -f ${vmName}.id ]]; then
    cloudInitId="$( printf "%02d" $(( $(cat ${vmName}.id) + 1 )) )"
else
    cloudInitId="01"
fi
echo "${cloudInitId}" > ${vmName}.id 

macaddress="$(printf "52:54:00";hexdump -n 3 -e '""3/1 ":%02x""\n"' /dev/urandom)"

diskName="${vmName}.${diskFormat}"
diskBoot="${dirPoolPath}/${diskName}"
dckDiskName="${vmName}_dck.${diskFormat}"
dckDisk="${dirPoolPath}/${dckDiskName}"

cwdir="$(dirname "$( python -c "import os;print( os.path.realpath('$0') )" )")"
cdrom="${vmName}.iso"
isoDir="${vmName}-iso-root"

[[ -d ${isoDir} ]] || mkdir ${isoDir}

cp iso-root-fixed-ip-template/user-data ${isoDir}/
sed -e "\
	s/INSTANCE/${vmName}-${cloudInitId}/; \
	s/HOSTNAME/${vmName}.${domainName}/; \
	s/ETHNAME/eth0/g; \
	s/IPADDR/${ipAddress}/; \
	s/NETWORK/${netIpAddress}/; \
	s/BROADCAST/${netIpAddress}.255/; \
	s/NETMASK/255.255.255.0/; \
	s/GATEWAY/${gatewayAddress}/; \
	s/DNSSRV/${dnsSrv}/; \
	s/DOMAIN/${domainName}/; \
    s/NOZEROCONF/true/
" iso-root-fixed-ip-template/meta-data > ${isoDir}/meta-data

sudo rm -rf ${cdrom}

echo "Making config drive..."
genisoimage -output ${cdrom} -volid cidata -joliet -rock ${isoDir}

volExists="$(virsh --connect=${hypervisor} vol-info --pool "${poolName}" "${diskName}" 2>&1 | egrep -iv "^error")"

if  [[ -n ${volExists} ]] ; then
    virsh --connect=${hypervisor} vol-delete --pool "${poolName}" "${diskName}"
fi
virsh --connect=${hypervisor} vol-create-as "${poolName}" "${diskName}" "${diskSize}" --format ${diskFormat}
virsh --connect=${hypervisor} vol-create-as "${poolName}" "${dckDiskName}" "${dckDiskSize}" --format ${diskFormat}

sudo chown qemu:qemu ${diskBoot} ${dckDisk}

sudo qemu-img convert -p -n -O ${diskFormat} "${sourceImage}" ${diskBoot}

qipaddr="$(printf "\x27%s\x27" ${ipAddress})"
qlong_host="$(printf "\x27%s.%s\x27" ${vmName} ${domainName})"
qhost="$(printf "\x27%s\x27" ${vmName})"
qmac="$(printf "\x27%s\x27" ${macaddress})"

if host ${qlong_host} ${dnsSrv} >/dev/null 2>&1 ; then
    havedns="true"
else
    havedns=""
fi
# remove any associated DNS A record
[[ ${havedns} ]] && virsh --connect=${hypervisor} net-update ${networkName} \
            delete dns-host "<host ip=${qipaddr}> <hostname>${vmName}.${domainName}</hostname> <hostname>${vmName}</hostname> </host>" --live --config
# Create DNS A record (equivalent in libvirt network descriptor)
virsh --connect=${hypervisor} net-update ${networkName} \
            add dns-host "<host ip=${qipaddr}> <hostname>${vmName}.${domainName}</hostname> <hostname>${vmName}</hostname> </host>" --live --config

# Remove any old leases for this name or ip address
virsh --connect=qemu:///system net-update default delete ip-dhcp-host "<host name=${qlong_host} ip=${qipaddr}/>" --live
virsh --connect=qemu:///system net-update default delete ip-dhcp-host "<host name=${qlong_host} ip=${qipaddr}/>" --config
# And, create the new leases for this name or ip address
virsh --connect=qemu:///system net-update default add ip-dhcp-host "<host mac=${qmac} name=${qlong_host} ip=${qipaddr}/>" --live --config

CMD="--connect=${hypervisor} --noautoconsole --name ${vmName} --virt-type kvm --vcpus ${vCPUs} --memory ${memSize} --cdrom ${cdrom} --boot hd --network network=${networkName},model=virtio,mac=${macaddress}"
CMD="${CMD} --disk ${diskBoot},bus=virtio,format=${diskFormat}"
CMD="${CMD} --disk ${dckDisk},bus=virtio,format=${diskFormat}"

virt-install ${CMD}

sleep 15

cdromdrive="$(virsh --connect=${hypervisor} domblklist ${vmName} --details | awk ' $2 ~ "cdrom" {print $3}')"
[[ -n "${cdromdrive}" ]] && virsh --connect=${hypervisor} change-media ${vmName} ${cdromdrive} --eject --live --force


