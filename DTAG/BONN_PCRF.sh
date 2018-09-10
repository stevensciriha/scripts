#!/bin/ksh
# v1.3 ssciriha Jan 17th 2012
#Policy Controller Backup Script
#Performs the following:
#

. /etc/BWS/BPC/config.sh
. $BPC_HOME/util/environment.sh

#set location for backup log
LOG=$BPC_HOME/backup/backup.log

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
  BACKUP_DIR=${BPC_HOME}/backup

  export BACKUP_DIR
  if [ ! -d $BACKUP_DIR ]
  then
    mkdir $BACKUP_DIR
  fi

#make tar file directory
  TARFILE_DIR=$BACKUP_DIR/TARFILE
  export TARFILE_DIR
 if [ ! -d $TARFILE_DIR ]
  then
    mkdir $TARFILE_DIR
    chmod 777 $TARFILE_DIR
  fi
 # generate backup file name
  BACKUP_FILE="$TARFILE_DIR/BACKUP_`hostname`_`date '+PCRF.%d.%m.%y'`"
  export BACKUP_FILE

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
      if [ ! -f ${BACKUP_FILE}.tar ]
      then
        TAR_OPTIONS="-chf"
      else
        TAR_OPTIONS="-rhf"
      fi

#      echo "DEBUG:Adding $1 to ${BACKUP_FILE}.tar" >> $LOG
      tar $TAR_OPTIONS ${BACKUP_FILE}.tar $1 >> /dev/null
      return $?
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
#          echo "DEBUG:Ignoring $arg instance parmdb" >> $LOG
          continue
        fi

        echo "Exporting instance ${arg}..." >> $LOG
        # create a temp copy of the parmdb with a traceable name
        PARMDB_NAME=${TARFILE_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.parmdb
#        echo "DEBUG:PARMDB_NAME:$PARMDB_NAME" >> $LOG
        cp -f ${INSTANCE_CURRENT}/parmdb $PARMDB_NAME
        if [ -f $PARMDB_NAME ]
        then
          add_to_tar $PARMDB_NAME
          if [ $? != 0 ]
          then
            rm $PARMDB_NAME
            return 3
          fi
          rm $PARMDB_NAME
        fi
#      else
#        echo "DEBUG: Ignoring $arg: not an instance directory" >> $LOG
      fi
#    else
#      echo "DEBUG: Ignoring $arg: not a directory" >> $LOG
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
          #echo "DEBUG:STATE:$STATE" >> $LOG
          echo $STATE | grep "running" > /dev/null
          if [ $? -eq 0 ]
          then
            # we found the online instance - use this insstance name to export policy
            echo "Using online instance '$arg' to export rule set" >> $LOG
            # Export the RMA credentials to allow them to be accessed by the policyExport.sh script
            export XPC_USERNAME
            export XPC_PASSWORD

            # NetworkPolicy
            RE_EXPORT_NAME=${TARFILE_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.RE.NetworkPolicy.zip
            echo "Exporting NetworkPolicy rules..." >> $LOG
            #echo "DEBUG:Exporting $RE_EXPORT_NAME" >> $LOG
            $BPC_HOME/bin/policyExport.sh $arg "NetworkPolicy" $RE_EXPORT_NAME > /dev/null
            if [[ -f $RE_EXPORT_NAME ]]
            then
              add_to_tar $RE_EXPORT_NAME
              if [ $? != 0 ]
              then
                rm $RE_EXPORT_NAME
                return 4
              fi
              rm $RE_EXPORT_NAME
            else
              echo "Failed to export NetworkPolicy Project" >> $LOG
              return 2
            fi

            # SessionRights
            RE_EXPORT_NAME=${TARFILE_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.RE.SessionRights.zip
            echo "Exporting SessionRights rules..." >> $LOG
            #echo "DEBUG:Exporting $RE_EXPORT_NAME" >> $LOG
            $BPC_HOME/bin/policyExport.sh $arg "SessionRights" $RE_EXPORT_NAME > /dev/null
            if [[ -f $RE_EXPORT_NAME ]]
            then
              add_to_tar $RE_EXPORT_NAME
              if [ $? != 0 ]
              then
                rm $RE_EXPORT_NAME
                return 4
              fi
              rm $RE_EXPORT_NAME
            else
              echo "Failed to export SessionRights Project" >> $LOG
              return 2
            fi

            # TieredServices
            RE_EXPORT_NAME=${TARFILE_DIR}/`cat ${INSTANCE_CURRENT}/version`.${arg}.RE.TieredServices.zip
            echo "Exporting TieredServices rules..." >> $LOG
            #echo "DEBUG:Exporting $RE_EXPORT_NAME" >> $LOG
            $BPC_HOME/bin/policyExport.sh $arg "TieredServices" $RE_EXPORT_NAME > /dev/null
            if [[ -f $RE_EXPORT_NAME ]]
            then
              add_to_tar $RE_EXPORT_NAME
              if [ $? != 0 ]
              then
                rm $RE_EXPORT_NAME
                return 4
              fi
              rm $RE_EXPORT_NAME
            else
              echo "Failed to export TieredServices Project" >> $LOG
              return 2
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
  if [ -d $BPC_HOME/is/ ]
  then
    CONFIG_EXPORT_NAME=${TARFILE_DIR}/BPC.config.zip
    #echo "DEBUG:CONFIG_EXPORT_NAME:$CONFIG_EXPORT_NAME" >> $LOG
    zip -r $CONFIG_EXPORT_NAME $BPC_HOME/is/$PCRF_instance/provserver/config -x \*.jar \*.exe \*.jsp >>/dev/null
    add_to_tar $CONFIG_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $CONFIG_EXPORT_NAME
      return 4
    fi
    rm $CONFIG_EXPORT_NAME
  else
    echo "There is no Prov config directory to export." >> $LOG
  fi
}

#
# Perform cleanup of all backup tarfiles older then $age
#
backup_cleanup() {

 #look for all files with an modified time greater then $age
 if [ -d $TARFILE_DIR ]
 then
 echo "performing backup file cleanup, deleting files older then $age days..." >> $LOG
 find $TARFILE_DIR -name "*BACKUP*" -mtime +$age -exec rm {} \; >> /dev/null
 else
         echo "Backup Directory $TARFILE_DIR does not exist" >> $LOG
 fi

}

get_package_versions() {


echo "Exporting system and application package versions..." >> $LOG
PackageVersions="$TARFILE_DIR/PackageVersions.`date '+%d%m%y'`.txt"
rpm -qa > $PackageVersions
add_to_tar $PackageVersions
if [ $? != 0 ]
          then
            rm $PackageVersions
            return 3
          fi
          rm $PackageVersions

}


get_system_configs() {

echo "Exporting system configuration files..." >> $LOG
 # Create an array with all the configs that require backing up
set -A Configs_List "/etc/sysconfig/network-scripts/*if*" "/etc/sysconfig/network" "/etc/modprobe.conf" "/etc/hosts" "/etc/syslog.conf" "/etc/passwd" "/etc/group" "/etc/shadow" "/etc/sysconfig/network-scripts/route-*" "/etc/sysctl.conf" "/etc/sysconfig/syslog" "/etc/ntp.conf" "/etc/sysconfig/selinux" "/etc/yum.repos.d/*"

   #check if each config exists and if it doesn't skip to the next config
   for config in ${Configs_List[*]}
        do
            if [ -r $config ];then
            echo "Exporting $config" >> $LOG

            add_to_tar $config
                if [ $? != 0 ]
                     then
                     echo "$config could not be added to backup file" >> $LOG
                     return 3
                fi

            else

            echo "$config does not exist or is not accessible" >> $LOG
            fi
        done

   #Backup snmp config directory
    if [ -d "/WideSpan/snmp/config" ]
  then
    echo "exporting snmp configuration directory /WideSpan/snmp/config..." >> $LOG
    SNMP_EXPORT_NAME="$TARFILE_DIR/snmp.config.zip"
    zip -r $SNMP_EXPORT_NAME /WideSpan/snmp/config -x \*.jar \*.exe \*.jsp >> /dev/null
    add_to_tar $SNMP_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $SNMP_EXPORT_NAME
      return 4
    fi
    rm $SNMP_EXPORT_NAME
  else
    echo "There is no SNMP config directory to export." >> $LOG
  fi

}

compress_tarfile() {

if [ ! -f $BACKUP_FILE.tar.gz ]
then
gzip $BACKUP_FILE.tar >> /dev/null
if (($? != 0))
then
  echo "Failed to compress tarfile..." >> $LOG
fi
else
echo "ERROR: Could not compress...$BACKUP_FILE.tar.gz already exists!" >> $LOG
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
  echo "Failed to create Backup Directory $TARFILE_DIR..." >> $LOG
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

INSTANCE_HOME="$BPC_HOME/is"
export INSTANCE_HOME

get_parmdbs
if (($? != 0))
then
  echo "Failed to export parmdb files" >> $LOG
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

get_system_configs
if (($? != 0))
then
  echo "Failed to export system configs" >> $LOG
fi

compress_tarfile
if (($? != 0))
then
  echo "Failed to compress logfile" >> $LOG
fi

echo "Complete. The archive can be found at ${BACKUP_FILE}.tar.gz" >> $LOG

