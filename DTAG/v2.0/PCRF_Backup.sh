#!/bin/ksh

# Policy Controller Backup Script
# v2.0 ssciriha Apr 17th 2012
# This new version supersedes all the previous v1.x scripts 

. /etc/BWS/BPC/config.sh
# . $BPC_HOME/util/environment.sh

INSTANCE_HOME="$BPC_HOME/is"

#set backup directory
BACKUP_DIR="/doxstore2/backup"

#set temp directory under /backup
TEMP_DIR="$BACKUP_DIR/temp"

#set default file list location 
# it is hidden to ensure no changes are made to it
DEFAULT_FILE_LIST="/opt/Amdocs/backup_scripts/system_backup_filelist.conf"

#this is the text file the tar command will run on
FILE_LIST="/var/tmp/filelist.txt"

#set user-configurable file list location
USER_FILE_LIST="/opt/Amdocs/backup_scripts/user_backup_filelist.conf"

#set location for backup log
LOG=$BACKUP_DIR/backup.log

#RMA rules engine root credentials
XPC_USERNAME="root"
XPC_PASSWORD="root"

# The age variable represent the retention period
age="1"

#########################
# create_backup_file
#########################

create_backup_file(){

# make sure directory exists
  if [ ! -d $BACKUP_DIR ]
  then
    mkdir -p $BACKUP_DIR
    if [ $? != 0 ]
    then
    	echo "Could not create backup directory. Exiting..." >> $LOG
    fi   
    chmod 755 $BACKUP_DIR
  fi

 # generate backup file name
  BACKUP_FILE="$BACKUP_DIR/BACKUP_`hostname`_`date '+PCRF.%d.%m.%y'`.tar"

# Check if temp directory has been created if yes delete it and recreate it, if not create it
if [ -d $TEMP_DIR ]
  then
    echo "Temp directory already exists!! Recreating..." >> $LOG
    rm -rf $TEMP_DIR
    mkdir $TEMP_DIR
    chmod 777 $TEMP_DIR
    if [ $? != 0 ]
       then
          return 4
    fi
 else
    mkdir $TEMP_DIR
    chmod 777 $TEMP_DIR
    if [ $? != 0 ]
       then
          return 4
    fi
fi

# Copy contents of default system filelist.txt file to working file
if [ -f $DEFAULT_FILE_LIST ] 
   then
     if [ -f $FILE_LIST ]
     	then
             rm $FILE_LIST
     fi
     cp -p $DEFAULT_FILE_LIST $FILE_LIST
     if [  $? != 0 ]
       then
          return 4
     fi
   else
    echo "$DEFAULT_FILE_LIST does not exist or has been deleted, please create and restart. Exiting..." >> $LOG
    exit  
fi     

}


#########################
# add_to_tar
# $1 file to add
#########################
add_to_tar(){
  if [ "x$1" != "x" ]
  then
    if [[ -f $1 ]]
    then
      if [ -f $FILE_LIST ]
      then
        echo $1 >> $FILE_LIST
        return $?
      else
        echo "$FILE_LIST does not exist! Exiting..." >> $LOG
        exit
      fi
    else
        echo "Warning: $1 does not exist or has been corrupted..."
    fi
  fi
}

#########################
# get_parmdbs
#########################

get_parmdbs(){
  echo "Exporting instance configurations..." >> $LOG
  for arg in $(ls $INSTANCE_HOME)
  do
    if [ -d $INSTANCE_HOME/$arg ]
    then
      INSTANCE_CURRENT=${INSTANCE_HOME}/$arg
      # we only want actual instance directories
      if [ -f ${INSTANCE_CURRENT}/parmdb -a -f ${INSTANCE_CURRENT}/version ]
      then
        # we want to ignore the special *_dfn instances
        if [[ ${arg##${arg%%_dfn}} = "_dfn" ]]
        then
          continue
        fi

        echo "Exporting instance ${arg}..." >> $LOG
        # create a temp copy of the parmdb with a traceable name
        PARMDB_NAME=${TEMP_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.parmdb
        cp -f ${INSTANCE_CURRENT}/parmdb $PARMDB_NAME
        if [ -f $PARMDB_NAME ]
        then
          add_to_tar $PARMDB_NAME
          if [ $? != 0 ]
          then
            return 3
          fi
        fi
      fi
    fi
  done
}



#########################
# perform_rules_export
#########################
perform_rules_export(){
  echo "Exporting RMA Rules for instance..." >> $LOG
  # look for the Timesten instance
  if [ -d $INSTANCE_HOME/TimesTen ]
  then
    # we currently only support one TimesTen instance, and hence there is only one rules set
    # to export; however, we do not know what instance it is from. But it really
    # doesn't matter other than the fact that the policyExport script still
    # requires a valid instance name (although it's not really used anymore).
    # for each instance (besides TimesTen and *_dfn) export the rules from TT
    for arg in $(ls $INSTANCE_HOME)
    do
      # find the active instance directory and use it as the policyExport.sh parameter.
      # echo "DEBUG:Processing $INSTANCE_HOME/$arg" >> $LOG
      if [ -d $INSTANCE_HOME/$arg ]
      then
        INSTANCE_CURRENT=$INSTANCE_HOME/$arg
        # we only want actual instance directories
        if [ -f ${INSTANCE_CURRENT}/parmdb -a -f ${INSTANCE_CURRENT}/version ]
        then
          # we want to ignore the special *_dfn, TimesTen, and SNMP instances

          if [[ ${arg##${arg%%_dfn}} = "_dfn" ]]
          then
            #echo "DEBUG:Ignoring $arg instance export" >> $LOG
            continue
          fi
          if [[ "$arg" = "TimesTen" ]]
          then
            #echo "DEBUG: Ignoring special $arg instance export" >> $LOG
            continue
          fi
          if [[ "$arg" = "SNMP" ]]
          then
            #echo "DEBUG: Ignoring special $arg instance export" >> $LOG
            continue
          fi

          # check if instance is active
          STATE=`$BPC_HOME/bin/$arg state 2>&1`
          PCRF_instance=$arg
          echo $STATE | grep "running" > /dev/null
          if [ $? -eq 0 ]
          then
            # we found the online instance - use this insstance name to export policy
            echo "Using online instance '$arg' to export rule set" >> $LOG
            # Export the RMA credentials to allow them to be accessed by the policyExport.sh script
            export XPC_USERNAME
            export XPC_PASSWORD

            # NetworkPolicy
            RE_EXPORT_NAME=${TEMP_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.RE.NetworkPolicy.zip
            echo "Exporting NetworkPolicy rules..." >> $LOG
            #echo "DEBUG:Exporting $RE_EXPORT_NAME" >> $LOG
            su - bpc --session-command "export XPC_USERNAME=$XPC_USERNAME;export XPC_PASSWORD=$XPC_PASSWORD;$BPC_HOME/bin/policyExport.sh $arg "NetworkPolicy" $RE_EXPORT_NAME > /dev/null"
            if [[ -f $RE_EXPORT_NAME ]]
            then
              add_to_tar $RE_EXPORT_NAME
              if [ $? != 0 ]
              then
             #   rm $RE_EXPORT_NAME
                return 4
              fi
            #  rm $RE_EXPORT_NAME
            else
              echo "Failed to export NetworkPolicy Project or Project does not exist..." >> $LOG
             # return 2
            fi

            # SessionRights
            RE_EXPORT_NAME=${TEMP_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.RE.SessionRights.zip
            echo "Exporting SessionRights rules..." >> $LOG
            #echo "DEBUG:Exporting $RE_EXPORT_NAME" >> $LOG
            su - bpc --session-command "export XPC_USERNAME=$XPC_USERNAME;export XPC_PASSWORD=$XPC_PASSWORD;$BPC_HOME/bin/policyExport.sh $arg "SessionRights" $RE_EXPORT_NAME > /dev/null"
            if [[ -f $RE_EXPORT_NAME ]]
            then
              add_to_tar $RE_EXPORT_NAME
              if [ $? != 0 ]
              then
              #  rm $RE_EXPORT_NAME
                return 4
              fi
             # rm $RE_EXPORT_NAME
            else
              echo "Failed to export SessionRights Project or Project does not exist..." >> $LOG
            #  return 2
            fi

            # TieredServices
            RE_EXPORT_NAME=${TEMP_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.RE.TieredServices.zip
            echo "Exporting TieredServices rules..." >> $LOG
            #echo "DEBUG:Exporting $RE_EXPORT_NAME" >> $LOG
            su - bpc --session-command "export XPC_USERNAME=$XPC_USERNAME;export XPC_PASSWORD=$XPC_PASSWORD;$BPC_HOME/bin/policyExport.sh $arg "TieredServices" $RE_EXPORT_NAME > /dev/null"
            if [[ -f $RE_EXPORT_NAME ]]
            then
              add_to_tar $RE_EXPORT_NAME
              if [ $? != 0 ]
              then
           #     rm $RE_EXPORT_NAME
                return 4
              fi
           #   rm $RE_EXPORT_NAME
            else
              echo "Failed to export TieredServices Project or Project does not exist..." >> $LOG
            #  return 2
            fi

            # we have successfully exported the rule set, so return
            return
            else
            # this instance is not online, use the next one
            echo "Instance $arg not online" >> $LOG
          fi
        fi
      fi
    done
    # if we get here, it is because we could not find an online instance to export rule for.
    echo "WARNING: There are no online instances found. No RMA rules will be exported." >> $LOG
  else
    echo "There is no TimesTen instance to export rule from". >> $LOG
    return
  fi
}


#########################
# perform_config_export
#########################
perform_config_export() {
  echo "Exporting BPC configuration directory $BPC_HOME/is/$PCRF_instance/provserver/config..." >> $LOG
  if [ -d $BPC_HOME/is/$PCRF_instance ]
  then
    CONFIG_EXPORT_NAME=${TEMP_DIR}/BPC.config.tar
    tar -chf $CONFIG_EXPORT_NAME $BPC_HOME/is/$PCRF_instance/provserver/config --exclude \*.jar --exclude \*.exe --exclude \*.jsp >>/dev/null
    add_to_tar $CONFIG_EXPORT_NAME
    if [ $? != 0 ]
    then
      return 4
    fi
  else
    echo "There is no Prov config directory to export." >> $LOG
    return 4
  fi
}

#
# Perform cleanup of all backup tarfiles older then $age
#
backup_cleanup() {

 #look for all files with an modified time greater then $age
 if [ -d $BACKUP_DIR ]
 then
 echo "performing backup file cleanup, deleting files older then $age days..." >> $LOG
 find $BACKUP_DIR -name "*BACKUP*" -mtime +$age -exec rm {} \; >> /dev/null
 else
         echo "Backup Directory $BACKUP_DIR does not exist" >> $LOG
 fi

}

get_package_versions() {


echo "Exporting system and application package versions..." >> $LOG
PackageVersions="$TEMP_DIR/PackageVersions.`date '+%d%m%y'`.txt"
rpm -qa > $PackageVersions
add_to_tar $PackageVersions
if [ $? != 0 ]
          then
          #  rm $PackageVersions
            return 3
          fi
        #  rm $PackageVersions

}


compress_tarfile() {

if [ ! -f $BACKUP_FILE.gz ]
then
gzip $BACKUP_FILE >> /dev/null
if (($? != 0))
then
  echo "Failed to compress tarfile..." >> $LOG
fi
else
echo "ERROR: Could not compress...$BACKUP_FILE.gz already exists!" >> $LOG
return 4
fi
}

perform_tar_operation() {

# This tar command will read the list of files and directories of $FILE_LIST and archive, if they exist
echo "Performing tar archive operation..." >> $LOG
tar -chf $BACKUP_FILE --ignore-failed-read --files-from=$FILE_LIST --wildcards >> /dev/null
if (($? != 0))
then
    return 4
fi

# Delete temp directory
if [ -d $TEMP_DIR ]
	then
            rm -rf $TEMP_DIR
        else 
            echo "ERROR: Could not delete temporary directory..." >> $LOG
fi

# Delete temp filelist
if [ -f $FILE_LIST ]
        then
            rm -rf $FILE_LIST
        else
            echo "ERROR: Could not delete temporary file list..." >> $LOG
fi
}

restore_original_filelist() {
# restore original $FILE_LIST to undo changes made by script

if [ -f /var/tmp/.filelist.txt.bak ]
	then
		cp -p /var/tmp/.filelist.txt.bak $FILE_LIST
		if (($? != 0))
			then
    				return 5
		fi
fi

}

append_network_scripts() {

# This function is required to backup the network scripts because the tar command doesnt take wildcards when using a list of files
# Add the wildcard entries you want to have backed up to the following array

set -A Configs_List "*ifcfg*" "*route*"
   for config in ${Configs_List[*]}
        do
		find /etc/sysconfig/network-scripts -name $config >> $FILE_LIST
		if (($? != 0))
			then
   				echo "Could not find network scripts. Skipping..." 
		fi
        done 

}

export_CTA_parmdb() {

if [ -f /etc/BWC/config.sh ]
	then 
            . /etc/BWC/config.sh
            INSTANCE_HOME="$BWC_HOME/is" 
        else
            echo "WARNING: CTA agent not detected...Could not backup!" >> $LOG
            return 4
fi


 echo "Exporting instance configurations..." >> $LOG
  for arg in $(ls $INSTANCE_HOME)
  do
    if [ -d $INSTANCE_HOME/$arg ]
    then
      INSTANCE_CURRENT=${INSTANCE_HOME}/$arg
      # we only want actual instance directories
        echo "Exporting instance ${arg}..." >> $LOG
        # create a temp copy of the parmdb with a traceable name
       PARMDB_NAME=$TEMP_DIR/`cat ${INSTANCE_CURRENT}/version`.${arg}.parmdb

       cp -f ${INSTANCE_CURRENT}/parmdb $PARMDB_NAME

        if [ -f $PARMDB_NAME ]
        then
          add_to_tar $PARMDB_NAME
          if [ $? != 0 ]
          then
            return 3
          fi
        fi

    fi
   done

if [ -f /etc/BWS/BPC/config.sh ]
        then
        # Reset INSTANCE_HOME variable to BPC_HOME
        INSTANCE_HOME="$BPC_HOME/is"
fi
}

backup_user_configs() {

if [ -f $USER_FILE_LIST ]
	then
            echo "User-Configurable file list detected. Script will attempt to backup all specified files..." >> $LOG
            cat $USER_FILE_LIST >> $FILE_LIST
	else
            echo "No User-Configurable file list detected. Skipping..." >> $LOG
fi
}

perform_active_partition_export(){
echo "Exporting Active Subscriber Partition..." >> $LOG

if [ -f $BPC_HOME/bin/partmgr.sh ]
	then
	export XPC_USERNAME
	export XPC_PASSWORD
	ACTIVE_PARTITION_OUTPUT=$TEMP_DIR/Active_Partition_Config.txt
	Active_Partition=`su - bpc --session-command "export XPC_USERNAME=$XPC_USERNAME;export XPC_PASSWORD=$XPC_PASSWORD;$BPC_HOME/bin/partmgr.sh $PCRF_instance list" | grep "*" | grep -v "indicates active configuration" | awk '{print $1}' | cut -d'*' -f2`
	su - bpc --session-command  "export XPC_USERNAME=$XPC_USERNAME;export XPC_PASSWORD=$XPC_PASSWORD;$BPC_HOME/bin/partmgr.sh $PCRF_instance show $Active_Partition" > $ACTIVE_PARTITION_OUTPUT  

	add_to_tar $ACTIVE_PARTITION_OUTPUT
	if [ $? != 0 ]
    		then
      			return 4
	fi
    else
	echo "Subscriber partition not installed. Skipping..." >> $LOG
fi

}


backup_snmp_config() {
  #Backup snmp config directory
    if [ -d "/WideSpan/snmp/config" ]
  then
    echo "exporting snmp configuration directory /WideSpan/snmp/config..." >> $LOG
    SNMP_EXPORT_NAME="$TEMP_DIR/snmp.config.tar"
    tar -chf $SNMP_EXPORT_NAME /WideSpan/snmp/config --exclude \*.jar --exclude \*.exe --exclude \*.jsp >>/dev/null
    if [ $? != 0 ]
        then 
            return 4
    fi
    add_to_tar $SNMP_EXPORT_NAME
    if [ $? != 0 ]
    then
#      rm $SNMP_EXPORT_NAME
      return 4
    fi
#    rm $SNMP_EXPORT_NAME
  else
    echo "There is no snmp config directory to export." >> $LOG
  fi
}

#########################
#########################
# MAIN
#########################
#########################


create_backup_file
if (($? != 0))
then
  echo "Failed to create Backup Directory $BACKUP_DIR..." >> $LOG
  exit
fi

# clear log
echo "" > $LOG
echo "Export starting at `date`..." >> $LOG


backup_cleanup
if (($? != 0))
then
        echo "Failed to perform backup cleanup..." >> $LOG
fi

append_network_scripts
if (($? != 0))
then
  echo "Failed to export network scripts" >> $LOG
fi

backup_user_configs
if (($? != 0))
then
  echo "Failed to backup user-configurable configuration files" >> $LOG
fi


get_parmdbs
if (($? != 0))
then
  echo "Failed to export parmdb files" >> $LOG
fi

export_CTA_parmdb
if (($? != 0))
then
  echo "Failed to export CTA parmdb files" >> $LOG
fi


perform_rules_export
if (($? != 0))
then
  echo "Failed to export RMA rules" >> $LOG
fi

perform_config_export
if (($? != 0))
then
  echo "Failed to export BPC config" >> $LOG
fi

get_package_versions
if (($? != 0))
then
  echo "Failed to export package version" >> $LOG
fi

perform_active_partition_export
if (($? != 0))
then
  echo "Failed to export active partition" >> $LOG
fi

backup_snmp_config
if (($? != 0))
then
  echo "Failed to backup snmp configuration" >> $LOG
fi


perform_tar_operation
if (($? != 0))
then
       echo "Failed to create archive. Exiting..." >> $LOG
       exit
fi

compress_tarfile
if (($? != 0))
then
  echo "Failed to compress logfile" >> $LOG
  echo "Backup Complete...The archive can be found at ${BACKUP_FILE}" >> $LOG
  exit 
fi

echo "Complete. The archive can be found at ${BACKUP_FILE}.gz" >> $LOG

