#!/bin/bash

#image_url="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
#image_url="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
image_url="http://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64-disk-kvm.img"
#image_dl="/var/lib/libvirt/images/base/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
#image_dl="/var/lib/libvirt/images/base/jammy-server-cloudimg-amd64.img"
image_dl="/var/lib/libvirt/images/base/ubuntu-22.04-server-cloudimg-amd64-disk-kvm.img"
#image_vm="/var/lib/libvirt/images/centos-obs3.qcow2"
image_vm="/var/lib/libvirt/images/ubuntu-2204.img"
#vm_name="centos_obs3"
vm_name="ubuntu_2204"
ssh_wait=120

c() {
	echo "+ $*"
	"$@"
}

download_image()
{
  c sudo mkdir -p /var/lib/libvirt/images/base
  if [ ! -f $image_dl ];then
    c sudo curl "{$image_url}" -o "${image_dl}"
  fi
}

configure_vm_image()
{
  c sudo yum install virt-install virt-viewer guest-fish
  c sudo qemu-img create -f qcow2 -b "${image_dl}" -F qcow2 "${image_vm}" 15G
  c sudo virt-customize -a "${image_vm}" --root-password password:12345678
  c virt-customize -a "${image_vm}" --run-command 'sed -i s/^PasswordAuthentication.*/PasswordAuthentication\ yes/ /etc/ssh/sshd_config'
  c virt-customize -a "${image_vm}" --run-command 'sed -i s/^#PermitRootLogin.*/PermitRootLogin\ prohibit-password/ /etc/ssh/sshd_config'
}

spawn_vm()
{
  cat <<EOF >user-data
  #cloud-config
  users:
    - name: cloud-user
      passwd: 12345678
      ssh_authorized_keys:
        - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7GkEmmWufMEriDMIBc2fIIUON227m/qJ6gJN2gR+pT mnietoji@mnietoji-thinkpadp1gen3.rmtes.csb
    - name: root
      passwd: 12345678
EOF

  c sudo virt-install --name "${vm_name}" --os-variant ubuntu22.04 --vcpus 6 --memory 8192 \
     --graphics vnc --virt-type kvm --disk "${image_vm}" --import --network default \
     --qemu-commandline="-device intel-iommu,intremap=on" --qemu-commandline="-machine q35,kernel-irqchip=split" \
     --cloud-init user-data=user-data  --noautoconsole  --wait 2
}

conf_host_network()
{
#  c sudo nmcli connection add type bridge con-name bridge0 ifname br0
#  c sudo nmcli connection add type bridge con-name bridge1 ifname br1
  c sudo ip link add name br0 type bridge
  c sudo ip link add name br1 type bridge
  c sudo ip netns add ns_0
  c sudo ip netns add ns_1
  c sudo ip link add veth0_0 type veth peer name veth0_1
  c sudo ip link add veth1_0 type veth peer name veth1_1
  c sudo ip link set veth0_0 netns ns_0
  c sudo ip link set veth1_0 netns ns_1
  c sudo ip link set veth0_1 master br0
  c sudo ip link set veth1_1 master br1
  c sudo ip netns exec ns_0 ip addr add 10.10.10.10/24 dev veth0_0
  c sudo ip netns exec ns_1 ip addr add 10.10.10.11/24 dev veth1_0
  c sudo ip netns exec ns_0 ip link set veth0_0 up
  c sudo ip netns exec ns_1 ip link set veth1_0 up
  c sudo ip link set up veth0_1
  c sudo ip link set up veth1_1
  c sudo ip link set br0 up
  c sudo ip link set br1 up
  echo "ns_0_ip: 10.10.10.10" >> test_env
  echo "ns_1_ip: 10.10.10.11" >> test_env
}

conf_vm()
{
  mac=$(sudo virsh domiflist ${vm_name} | grep virtio | awk '{print $5}')
  ip=$(sudo virsh net-dhcp-leases default  | grep "${mac}" | awk '{print $5}' | awk -F '/' '{print $1}')
  echo "vm_ip: ${ip}" >> test_env

  counter=0
  while [ "${counter}" -lt "${ssh_wait}" ];do
    if ssh -o StrictHostKeyChecking=accept-new cloud-user@"${ip}" ls;then
      echo "VM $ip is up"
      break
    fi
    sleep 1
    echo "Waiting vm $ip to be up"
    ((counter+=1))
  done
  exit

  scp -rp test_vm cloud-user@"${ip}":/home/cloud-user
  ssh cloud-user@"${ip}"  <<EOFS
    c() {
        echo "+vm \$*"
        "\$@"
    }
    c sudo dnf install driverctl pciutils dpdk centos-release-nfv-openvswitch git go -y
    c sudo dnf install openvswitch3.3 -y
    c sudo systemctl enable openvswitch
    c sudo systemctl start openvswitch

    c sudo modprobe vfio
    c sudo modprobe vfio-pci
    pcis=(\$(lspci | grep Ethernet | grep -v Virtio | awk '{print \$1}'))
    for pci in \${pcis[@]};do
       c sudo driverctl set-override 0000:\${pci} vfio-pci
    done
    c sudo ovs-vsctl set o . other_config:pmd-cpu-mask=0x3e
    c sudo ovs-vsctl set o . other_config:dpdk-extra="-n 4 -a 0000:00:00.0"
    c sudo ovs-vsctl set o . other_config:dpdk-init=true
    c sudo systemctl restart openvswitch

    ids=("0" "1")
    for id in \${ids[@]};do
       c sudo ovs-vsctl add-br br-phy-\${id} -- set bridge br-phy-\${id} datapath_type=netdev
       c sudo ovs-vsctl add-port br-phy-\${id} dpdk-\${id} -- set interface dpdk-\${id} type=dpdk options:dpdk-devargs=0000:\${pcis[\${id}]}
       c sudo ip link set br-phy-\${id} up
    done
    c sudo ip link add veth0 type veth peer name veth1
    #c sudo nmcli connection add type veth con-name veth veth.peer veth0 ifname veth1
    c sudo ip link set veth1 up
    c sudo ip link set veth0 up
    c sudo ovs-vsctl add-port br-phy-0 veth0
    c sudo ovs-vsctl add-port br-phy-1 veth1

    c cd \$HOME
    c git clone https://github.com/openstack-k8s-operators/dataplane-node-exporter.git
    c cd dataplane-node-exporter
    c make
    c sudo cp dataplane-node-exporter /usr/local/bin/
    c cat << EOFV | sudo tee /etc/systemd/system/dataplane-node-exporter.service >/dev/null
    [Unit]
    Description=dataplane-node-exporter

    # You may want to start after your network is ready
    After=network-online.target

    [Service]
    ExecStart=/usr/local/bin/dataplane-node-exporter
    Restart=Always
    PIDFile=/tmp/dataplane_node_exporter_pid
EOFV
    c sudo systemctl daemon-reload
    c sudo systemctl start dataplane-node-exporter
EOFS
}

clean()
{
  c sudo virsh destroy "${vm_name}"
  c sudo virsh undefine "${vm_name}"
  c sudo rm "${image_vm}"
#  c sudo nmcli connection delete bridge0
#  c sudo nmcli connection delete bridge1
  c sudo ip link delete br0
  c sudo ip link delete br1
  c sudo ip netns delete ns_0
  c sudo ip netns delete ns_1
  rm test_env

}

install()
{
  clean
  download_image
  configure_vm_image
#  conf_host_network
  spawn_vm
  conf_vm
}

help()
{
   echo "Install/Uninstall dataplane-node-exporter test environment"
   echo "config_test_environment.sh [install|uninstall]"
   echo "options:"
   echo "install     Install test environment"
   echo "uninstall   Uninstall test environment"
}

check_sudo()
{
   if sudo -n true 2>/dev/null; then
     return 0
   fi
   echo "sudo needed to run this script"
   return 1
}

if ! check_sudo;then
   exit 1
fi

case $1 in
  install) # install test environment
     install
     exit;;
  uninstall) # clean environment
     clean
     exit;;
esac
help
