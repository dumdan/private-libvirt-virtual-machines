#!/bin/bash
#
#   DD
#
ansible-playbook playbooks/provision.yml
(( $? == 0 )) || { echo -e "*** Provision FAILED *** Exitting \x21 ***\n" ; exit 255 ;}
echo "Provision done"
sleep 20
while true; do
    vm_stopped="$(ssh -qn oryxdd.ddse.ca "virsh --connect=qemu:///system list --inactive --name| egrep gcpsdk")"
    if [[ -n ${vm_stopped} ]] ; then
        echo "*** The VM was stopped  - starting it"
        ssh -qn oryxdd.ddse.ca "virsh --connect=qemu:///system start gcpsdk"
        break
    else
    #   echo "------- The VM was   *** N O T    STOPPED ***"
        echo "------- The VM was NOT STOPPED - waiting"
    fi
    sleep 5
done;
ansible-playbook playbooks/wait-reboot.yml
ansible-playbook playbooks/docker.yml
(( $? == 0 )) || { echo -e "*** Docker install FAILED *** Exitting \x21 ***\n" ; exit 251 ;}

ansible-playbook playbooks/users.yml
(( $? == 0 )) || { echo -e "*** User config FAILED *** Exitting \x21 ***\n" ; exit 252 ;}

ansible-playbook playbooks/gcpsdk.yml
(( $? == 0 )) || { echo -e "*** Google Cloud SDK FAILED *** Exitting \x21 ***\n" ; exit 253 ;}

