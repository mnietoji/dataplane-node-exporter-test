#!/bin/bash
set -x

start_iperf_server()
{
   ns="${1}"
   ip="${2}"
   sudo ip netns exec "${ns}" iperf3 -s -B "${ip}" -p 7575 -D --logfile /tmp/iperf3.txt --forceflush
   while ! grep listening /tmp/iperf3.txt >/dev/null;do
      sleep 1
   done
   echo "iperf server is running"
}

start_iperf_client()
{
   ns="${1}"
   ip="${2}"
   sudo ip netns exec "${ns}" iperf3 -c "${ip}" -t 20 -p 7575 1>&2 
   sleep 3
}

filter_file()
{
   file="${1}"
   out="${2}"
   skipfiles="${3}"

   cmd="cat ${file}"
   for skip in ${skipfiles};do
      cmd="${cmd} | grep -v ${skip}"
   done
   echo "${cmd}" | bash > "${out}"
}

compare()
{
   echo "Checking that dataplane-node-exporter statistics are ok"
   file1=$1
   file2=$2
   threshold=2

   skipfile1="ovs_interface_tx_retries ovs_interface_rx_dropped"
   skipfile2="ovs_interface_rx_dropped"

   filter_file "${file1}" "${file1}".tmp1 "${skipfile1}"
   filter_file "${file2}" "${file2}".tmp1 "${skipfile2}"

   len1=$(wc -l "${file1}".tmp1 | awk '{print $1}')
   len2=$(wc -l "${file2}".tmp1 | awk '{print $1}')

   if [[ "${len1}" != "${len2}" ]];then
      echo "ERROR: Wrong number of statistics, files have different length ${len1} ${len2}"
      return 1
   fi

   awk '{print $1}' "${file1}".tmp1 > "${file1}".tmp2
   awk '{print $1}' "${file2}".tmp1 > "${file2}".tmp2

   if ! diff "${file1}".tmp2 "${file2}".tmp2;then
     echo "ERROR: Statistics set is not completed, Files have different fields"
     return 1
   fi

   retvalue=0
   while IFS= read -r -u 4 line1 && IFS= read -r -u 5 line2; do
      if [[ "${line1}" != "${line2}" ]];then
	 field1=$(echo "${line1}" | awk '{print $1}' | sed 's/ //g')
	 field2=$(echo "${line2}" | awk '{print $1}' | sed 's/ //g')
	 value1=$(echo "${line1}" | awk '{print $2}' | sed 's/ //g')
	 value2=$(echo "${line2}" | awk '{print $2}' | sed 's/ //g')
	 if [[ "${field1}" != "${field2}" ]];then
	    echo "ERROR: Unextected error, fields should coincide ${field1} ${field2}"
	    retvalue=1
	    break
	 fi 
	 if [[ "${value1}" != "0" && "${value2}" != "0" ]];then
	    diff=$(awk -v value1="${value1}" -v value2="${value2}" 'BEGIN{d=(100*(value2-value1)/value1);if (d<0) d=d*(-1);printf("%2.2f\n", d)}')
	    if awk "BEGIN {exit !($diff >= $threshold)}"; then
	       if [[ ${retvalue} == 0 ]];then
		  echo "ERROR: Obtaing wrong values for some statistics"
		  retvalue=1
	       fi
	       echo "${field1} ${value1} ${value2} ${diff}"
	    fi
	 else
	   if [[ ${retvalue} == 0 ]];then
	      echo "ERROR: Obtaing wrong values for some statistics"
	      retvalue=1
	   fi
	   echo "${field1} ${value1} ${value2}"
	 fi
      fi
   done 4<"${file1}".tmp1 5<"${file2}".tmp1
   rm "${file1}" "${file2}" "${file1}".tmp1 "${file1}".tmp2 "${file2}".tmp1 "${file2}".tmp2
   return "${retvalue}"
}

get_stats()
{
  file1="${1}"
  file2="${2}"
  options="${3}"
  echo "Getting stats"
  rm "${file1}" "${file2}" 2>/dev/null
  curl -o "${file1}" "${vm_ip}":1981/metrics 
  ssh cloud-user@"${vm_ip}" /home/cloud-user/test_vm/get_ovs_stats.sh "${options}" >"${file2}"
  if [[ ! -f "$file1" || ! -f "$file2" ]];then
     echo "Failed to get statistics"
     ls -ls "$file1" "$file2"
     return 1
  fi
  return 0
}

check_sudo()
{
   if sudo -n true 2>/dev/null; then
     return 0
   fi
   echo "sudo needed to run this script"
   return 1
}

restart_dataplane_node_exporter()
{
  sudo killall -9 dataplane-node-exporter
  sudo sudo ./dataplane-node-exporter &
  sleep 5
}

test1()
{
  ns="${1}"
  ip="${2}"
  echo "Test1: Get statistics with default configuration"
  sudo rm /etc/dataplane-node-exporter.yaml 2>/dev/null
  restart_dataplane_node_exporter
  file="test1"
  start_iperf_client "${ns}" "${ip}"
  get_stats "${file}_1" "${file}_2"
  compare "${file}_1" "${file}_2"
  return $?
}

test2()
{
  ns="${1}"
  ip="${2}"
  echo "Test2: Get statistics with only with some collectors"
  echo "collectors: [interface, memory]" | sudo tee /etc/dataplane-node-exporter.yaml
  restart_dataplane_node_exporter
  file="test2"
  start_iperf_client "${ns}" "${ip}"
  get_stats "${file}_1" "${file}_2" "-c interface:memory"
  compare "${file}_1" "${file}_2"
  return $?
}

test3()
{
  ns="${1}"
  ip="${2}"
  echo "Test3: Get statistics with only with some collectors and metricsets"
  echo "collectors: [interface, memory]" | sudo tee /etc/dataplane-node-exporter.yaml
  echo "metric-sets: [errors, counters]" | sudo tee -a /etc/dataplane-node-exporter.yaml
  restart_dataplane_node_exporter
  file="test3"
  start_iperf_client "${ns}" "${ip}"
  get_stats "${file}_1" "${file}_2" "-c interface:memory -m errors:counters"
  compare "${file}_1" "${file}_2"
  return $?
}

run_tests()
{
   ret=0
   testcases=$(echo "${1}" | tr ':' ' ')
   ns="${2}"
   ip="${3}"
   for test in ${testcases};do
      $test "${ns}" "${ip}" | awk -v t="${test}" '{print t": "$0}'
      ret_test=${PIPESTATUS[0]}
      if [[ "${ret_test}" != 0 ]];then
         echo "${test}: Testcase failed"
	 ret="${ret_test}"
      else
         echo "${test}: Testcase passed"
      fi
   done
   return "${ret}"
}

help()
{
   echo "Run testcases"
   echo "run_tests.sh [-h | -t testcases -v ]"
   echo "   -h for this help"
   echo "   -t for testcases list separated by :"
   echo "   -v verbose"
   echo "Sudo needed"
}

verbose='false'
while getopts h?t:v flag
do
    case "${flag}" in
        t) testcases=${OPTARG};;
        v) verbose='true';;
        h|\?) help; exit 0;;
        *) help; exit 0;;
    esac
done
testcases=${testcases:-test1:test2:test3}

if ! check_sudo;then
   exit 1
fi

ips=$(for ns in $(sudo ip netns ls | awk '{print $1}');do echo ${ns}:$(sudo ip netns exec ${ns} ip a | grep "inet " | awk '{print $2}' | awk -F '/' '{print $1}');done | tr '\n' ' ')
echo "testcases: ${testcases}"
echo "ips      : ${ips}"
ns0=$(echo ${ips} | awk '{print $1}' | awk -F ':' '{print $1}')
ip0=$(echo ${ips} | awk '{print $1}' | awk -F ':' '{print $2}')
ns1=$(echo ${ips} | awk '{print $2}' | awk -F ':' '{print $1}')
ip1=$(echo ${ips} | awk '{print $2}' | awk -F ':' '{print $2}')
start_iperf_server "${ns0}" "${ip0}"

if [[ "${verbose}" == "true" ]];then
   run_tests "${testcases}" "${ns1}" "${ip0}"
else
   run_tests "${testcases}" "${ns1}" "${ip0}" 2>/dev/null
fi
killall -9 iperf3 2>/dev/null
