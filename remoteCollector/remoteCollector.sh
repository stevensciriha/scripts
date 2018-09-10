#!/bin/bash

source ~/stackrc
export run_command="$1"
declare -a serverList=(`openstack server list | grep overcloud | awk -F '|' {'print $5'} | awk -F '=' {'print $2'} `)

for i in "${serverList[@]}";
do
        echo -e "\nrunning \"$run_command\" on $i..."
	./remoteCollector.exp $i  
done


