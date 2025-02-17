# dataplane-node-exporter-test



## Introduction

Functional testcases for [dataplane-node-exporter](https://github.com/openstack-k8s-operators/dataplane-node-exporter.git)

It will create a ovs-dpdk bridge together to dataplane-node-exporter. Traffic will be injected and statistics generated
by dataplane-node-exporter will be checked 

## How to use it

Steps:
1. Configure the environment. Run the script [config_test_environment.sh](https://github.com/mnietoji/dataplane-node-exporter-test/blob/main/config_test_environment.sh)

   ```
   ./config_test_environment.sh 
   ```

   It will configure a ovs bridge and 2 namespaces connected to the ovs bridge

2. Run testcases. Run the script [run_tests.sh](https://github.com/mnietoji/dataplane-node-exporter-test/blob/main/run_tests.sh)

   ```
   ./run_tests.sh
   ```

