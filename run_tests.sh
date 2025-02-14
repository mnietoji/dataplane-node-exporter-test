#!/bin/bash

inject_traffic()
{
   echo "Injecting Traffic"
   ip="${1}"
   sudo ip netns exec ns_0 timeout 25 iperf3 -s 1>&2 &
   sleep 1
   sudo ip netns exec ns_1 iperf3 -c "${ip}" -t 20 1>&2 
   sleep 2
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

test1()
{
  echo "Test1: Get statistics with default configuration"
  ssh cloud-user@"${vm_ip}"  <<EOF
  sudo rm /etc/dataplane-node-exporter.yaml 2>/dev/null
  sudo systemctl restart dataplane-node-exporter
EOF
  sleep 1
  file="test1"
  inject_traffic "${ns_0_ip}"
  get_stats "${file}_1" "${file}_2"
  compare "${file}_1" "${file}_2"
  return $?
}

test2()
{
  echo "Test2: Get statistics with only with some collectors"
  ssh cloud-user@"${vm_ip}"  <<EOF
  echo "collectors: [interface, memory]" | sudo tee /etc/dataplane-node-exporter.yaml
  sudo systemctl restart dataplane-node-exporter
EOF
  sleep 1
  file="test2"
  inject_traffic "${ns_0_ip}"
  get_stats "${file}_1" "${file}_2" "-c interface:memory"
  compare "${file}_1" "${file}_2"
  return $?
}

test3()
{
  echo "Test3: Get statistics with only with some collectors and metricsets"
  ssh cloud-user@"${vm_ip}"  <<EOF
  echo "collectors: [interface, memory]" | sudo tee /etc/dataplane-node-exporter.yaml
  echo "metric-sets: [errors, counters]" | sudo tee -a /etc/dataplane-node-exporter.yaml
  sudo systemctl restart dataplane-node-exporter
EOF
  sleep 1
  file="test3"
  inject_traffic "${ns_0_ip}"
  get_stats "${file}_1" "${file}_2" "-c interface:memory -m errors:counters"
  compare "${file}_1" "${file}_2"
  return $?
}

run_tests()
{
   ret=0
   testcases=$(echo "${1}" | tr ':' ' ')
   for test in ${testcases};do
      $test | awk -v t="${test}" '{print t": "$0}'
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

vm_ip=$(grep vm_ip test_env | awk -F ':' '{print $2}' | sed 's/ //g')
ns_0_ip=$(grep ns_0_ip test_env | awk -F ':' '{print $2}' | sed 's/ //g')
if [[ "${verbose}" == "true" ]];then
   run_tests "${testcases}"
else
   run_tests "${testcases}" 2>/dev/null
fi
