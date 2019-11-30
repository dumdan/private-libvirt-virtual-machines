#!/bin/bash
#
#   DD
#
ansible-playbook playbooks/provision.yml
echo "Provision done"
sleep 30
while true; do
    vm_stopped="$(ssh -qn oryxdd.ddse.ca "virsh --connect=qemu:///system list --inactive --name| egrep minikube")"
    if [[ -n ${vm_stopped} ]] ; then
        echo "*** The VM was stopped  - starting it"
        ssh -qn oryxdd.ddse.ca "virsh --connect=qemu:///system start minikube"
        break
    else
    #   echo "------- The VM was   *** N O T    STOPPED ***"
        echo "------- The VM was NOT STOPPED - waiting"
    fi
    sleep 5
done;
ansible-playbook playbooks/wait-reboot.yml
ansible-playbook playbooks/config-os.yml
# ansible-playbook playbooks/docker.yml

ansible-playbook playbooks/minikube.yml

