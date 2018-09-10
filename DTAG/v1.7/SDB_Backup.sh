#!/bin/ksh

# v1.7 ssciriha Jan 17th 2012
# SDB Backup Script
# Performs the following backups:

. /u01/app/oracle/widespan/scripts/env_server.sh
LOG="/u01/app/oracle/widespan/backups/TARFILE/backup.log"
# The age variable represent the retention period
age="1"

###################################################################
#Create the backup directory the tarfile directory and the tarfile
###################################################################
create_backup_file(){
  # make sure directory exists
  TARFILE_DIR="/u01/app/oracle/widespan/backups/TARFILE"
 export TARFILE_DIR
 if [ ! -d $TARFILE_DIR ]
 then
	 mkdir $TARFILE_DIR
 fi 

 # generate backup file name
  BACKUP_FILE="$TARFILE_DIR/BACKUP_`hostname`_`date '+SDB.%d.%m.%y'`"
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
    then       if [ ! -f ${BACKUP_FILE}.tar ]
      then
        TAR_OPTIONS="-chf"
      else
        TAR_OPTIONS="-rhf"
      fi

tar $TAR_OPTIONS ${BACKUP_FILE}.tar $1 >> /dev/null
      return $?
    fi
  fi
}


perform_SDB_config_export() {
  echo "Exporting ORACLE configuration directory $ORACLE_HOME/network/admin..." >> $LOG
  if [ -d $ORACLE_HOME/network/admin ]
  then
    CONFIG_EXPORT_NAME="$TARFILE_DIR/SDB.config.zip"
#    echo "DEBUG:CONFIG_EXPORT_NAME:$CONFIG_EXPORT_NAME" >> $LOG
    zip -r $CONFIG_EXPORT_NAME $ORACLE_HOME/network/admin -x \*.jar \*.exe \*.jsp >> /dev/null
    add_to_tar $CONFIG_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $CONFIG_EXPORT_NAME
      return 4
    fi
    rm $CONFIG_EXPORT_NAME
  else
    echo "There is no SDB config directory to export." >> $LOG
  fi
}

get_db_backup() {

DB_BACKUP_DIR="/u01/app/oracle/widespan/backups/daily/"
for arg in $(ls $DB_BACKUP_DIR)
do
echo "Adding database backup files to tarfile..." >> $LOG
if [ -f $DB_BACKUP_DIR$arg ]
then
add_to_tar $DB_BACKUP_DIR$arg
else
echo "ERROR: $DB_BACKUP_DIR$arg does not exist" >> $LOG
fi
done
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
    echo "There is no snmp config directory to export." >> $LOG
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

get_provs_config() {

        #Backup Provserver config directory
    if [ -d "/WideSpan/config/provserver" ]
  then
    echo "exporting Provserver configuration directory /WideSpan/config/provserver..." >> $LOG
    PROV_EXPORT_NAME="$TARFILE_DIR/provserver.config.zip"
    zip -r $PROV_EXPORT_NAME /WideSpan/config/provserver -x \*.jar \*.exe \*.jsp >> /dev/null
    add_to_tar $PROV_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $PROV_EXPORT_NAME
      return 4
    fi
    rm $PROV_EXPORT_NAME
  else
    echo "There is no provserver config directory to export." >> $LOG
  fi
}

get_params_config() {

        #Backup params directory
    if [ -d "/WideSpan/stage/params" ]
  then
    echo "exporting params directory /WideSpan/stage/params..." >> $LOG
    PARAMS_EXPORT_NAME="$TARFILE_DIR/params.config.zip"
    zip -r $PARAMS_EXPORT_NAME /WideSpan/stage/params -x \*.jar \*.exe \*.jsp >> /dev/null
    add_to_tar $PARAMS_EXPORT_NAME
    if [ $? != 0 ]
    then
      rm $PARAMS_EXPORT_NAME
      return 4
    fi
    rm $PARAMS_EXPORT_NAME
  else
    echo "There is no params directory to export." >> $LOG
  fi
}


################
#MAIN
################

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

perform_SDB_config_export
if (($? != 0))
then
  echo "Failed to export SDC config" >> $LOG
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

get_provs_config
if (($? != 0))
then
  echo "Failed to export provserver configs" >> $LOG
fi

get_params_config
if (($? != 0))
then
  echo "Failed to export params configs" >> $LOG
fi

get_db_backup
if (($? != 0))
then
  echo "Failed to backup Oracle Database..." >> $LOG
fi


compress_tarfile
if (($? != 0))
then
  echo "Failed to compress logfile" >> $LOG
fi
echo "Complete. The archive can be found at ${BACKUP_FILE}.tar.gz" >> $LOG

