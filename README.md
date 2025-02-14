# dataplane-node-exporter-test



## Introduction

Functional testcases for [dataplane-node-exporter](https://github.com/openstack-k8s-operators/dataplane-node-exporter.git)

It will create a vm with ovs-dpdk bridges together to dataplane-node-exporter. Traffic will be injected and statistics generated
by dataplane-node-exporter will be checked 

## How to use it

It can run in any linux machine. 

Steps:
1. Configure the environment. Run the script [config_test_environment.sh](https://gitlab.cee.redhat.com/mnietoji/dataplane-node-exporter-test/-/blob/main/config_test_environment.sh?ref_type=heads)

   ```
   ./config_test_environment.sh install
   ```

   It will configure:
   - vm with ovs and dataplane-node-exporter
   - 2 namespaces in the host connected to the vm used to inject some traffic in order to update statistics values
   - A file with ip addresses of vm and namespaces: 
     ```
     cat test_env 
     ns_0_ip: 10.10.10.10   # ip address of namespace 0
     ns_1_ip: 10.10.10.11   # ip address of namespace 1
     vm_ip: 192.168.122.174 # ip address of vm
     ```

2. Run testcases. Run the script [run_tests.sh](https://gitlab.cee.redhat.com/mnietoji/dataplane-node-exporter-test/-/blob/main/run_tests.sh?ref_type=heads)


   ```
   ./run_tests.sh
   ```

