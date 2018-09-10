#!/bin/ksh

#ssciriha v2.1 Jun 16th 2012
#This script is designed to work with v2.x of the Fetch_Backup.exp script
host_file="/opt/Amdocs/backup_scripts/hosts_to_fetch.txt"
fetch_script="/opt/Amdocs/backup_scripts/fetch_backups.exp"
BMS_backup_dir="/doxstore2/backup_location/"

set -A Dir_List "BMS" "DRA" "SWITCH" "PCRF" "SDB"

   #check if each directory exists and if it doesn't create it
   for dir in ${Dir_List[*]}
        do
            if [ ! -d $BMS_backup_dir$dir ]
                then
                      mkdir -p $BMS_backup_dir$dir
	    fi
	done

if [ -f $host_file ]
	then
             while read config
		do
                  echo $config | egrep -q '^\s*?$|^#|^\s*?#' 
                  if [[ $? == 0 ]]
                     then
                        continue
                  fi
                  $fetch_script $config       
		done <"$host_file"
        else
              echo "fetch_hosts.txt file does not exist"
 fi          
