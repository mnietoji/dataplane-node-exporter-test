#!/bin/bash

c() {
   echo "+vm $*"
   "$@"
}
c sudo apt-get install openvswitch-switch-dpdk iperf3 -y
c sudo /etc/init.d/openvswitch-switch start

c sudo modprobe vfio
c sudo modprobe vfio-pci
c sudo ovs-vsctl set o . other_config:pmd-cpu-mask=0x06
c sudo ovs-vsctl set o . other_config:dpdk-extra="-n 4 -a 0000:00:00.0"
c sudo ovs-vsctl set o . other_config:dpdk-init=true
c sudo /etc/init.d/openvswitch-switch restart

c sudo ip link add veth0_0 type veth peer name veth0_1
c sudo ip link add veth1_0 type veth peer name veth1_1
c sudo ip link add veth2_0 type veth peer name veth2_1

c sudo ovs-vsctl add-br br-phy-0 -- set bridge br-phy-0 datapath_type=netdev
c sudo ip link set br-phy-0 up
c sudo ovs-vsctl add-port br-phy-0 veth0_0
c sudo ip link set veth0_0 up
c sudo ovs-vsctl add-port br-phy-0 veth2_0
c sudo ip link set veth2_0 up
c sudo ovs-vsctl add-br br-phy-1 -- set bridge br-phy-1 datapath_type=netdev
c sudo ip link set br-phy-1 up
c sudo ovs-vsctl add-port br-phy-1 veth1_0
c sudo ip link set veth1_0 up
c sudo ovs-vsctl add-port br-phy-1 veth2_1
c sudo ip link set veth2_1 up

c sudo ip netns add ns_0
c sudo ip link set veth0_1 netns ns_0
c sudo ip netns exec ns_0 ip addr add 10.10.10.10/24 dev veth0_1
c sudo ip netns exec ns_0 ip link set veth0_1 up

c sudo ip netns add ns_1
c sudo ip link set veth1_1 netns ns_1
c sudo ip netns exec ns_1 ip addr add 10.10.10.11/24 dev veth1_1
c sudo ip netns exec ns_1 ip link set veth1_1 up

c cat /proc/cpuinfo
c sudo ip netns ls
namespaces=$(sudo ip netns ls | awk '{print $1}')
for namespace in ${namespaces};do
   c sudo ip netns exec ${namespace} ip a | awk -v n=${namespace} '{print n," ",$0}'
done
c sudo ip a
c sudo ovs-vsctl show
c sudo ovs-appctl dpif-netdev/pmd-rxq-show
c sudo ip netns exec ns_1 ping -c 3 10.10.10.10

