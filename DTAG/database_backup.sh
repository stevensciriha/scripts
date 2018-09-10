#!/bin/sh
# Shell script for performing Database backups
# Version Information: $Id: database_backup.sh,v 1.9.8.1 2011/05/09 17:47:07 mmayer Exp $
###############################################################################
setup_env ()
{

ORACLE_BASE=/u01/app/oracle
WSP_INSTANCE=`egrep "^wsp" /var/opt/oracle/oratab`

BWS_OS=`uname -s`

if [ $BWS_OS = "Linux" ]
then
    ECHO='printf %b\n'
else
    ECHO='echo'
fi

CURR_HOME=`$ECHO $WSP_INSTANCE | awk -F: '{print $2}' -`
ORACLE_HOME=$CURR_HOME
ORACLE_SID=wsp
PATH=$ORACLE_HOME/bin:$PATH
LD_LIBRARY_PATH=$ORACLE_HOME/lib:usr/ucblib:/usr/openwin/lib:usr/dt/lib

export ORACLE_BASE ORACLE_HOME ORACLE_SID LD_LIBRARY_PATH PATH

LOGFILE=/database/widespan/backups/database_backup.log

WSPTEMP=/database/widespan/backups/wsptemp.tmp

$ECHO "Database Backup for `uname -n` on `date`" > $LOGFILE

# check Oracle Editon: Enterprise or Standard
$ECHO "\nChecking Oracle Edition Installed ..." | tee -a $LOGFILE

sqlplus /nolog <<! > $WSPTEMP
connect / as sysdba
set head off
select 'EDITION='||decode(instr(banner, 'Enterprise'), 0, 'Standard', 'Enterprise')
  from v\$version
 where banner like '%Oracle%';
!

EDITION=`egrep 'EDITION' $WSPTEMP | cut -d '=' -f 2`

$ECHO "$EDITION" >> $LOGFILE

if [ "$EDITION" = "Enterprise" ] ; then
   $ECHO "Using Oracle Enterprise Edition ..." | tee -a $LOGFILE
   OE_VERSION="true"
   PARALLEL=" parallelism 2"
else
   $ECHO "Using Oracle Standard Edition ..." | tee -a $LOGFILE
   OE_VERSION="false"
   PARALLEL=" parallelism 1"
fi

}

###############################################################################
get_server_type ()
{
sqlplus /nolog<<! > $WSPTEMP
connect / as sysdba
set serveroutput on
declare
   ct    number := 0;
begin
   select count(*) into ct from dba_users where username='STRMADMIN';
   if ct != 0 then
      dbms_output.put_line('SERVERTYPE=STREAMS');
   else
      dbms_output.put_line('SERVERTYPE=NOSTREAMS');
   end if;
end;
/

!

SERVERTYPE=`egrep 'SERVERTYPE' $WSPTEMP | cut -d '=' -f 2`

$ECHO "$SERVERTYPE" >> $LOGFILE

}
###############################################################################
check_config ()
{

# Check that the config file exists
if [ ! -f $CONFIG_FILE ] ; then
   log_message "Configuration file $CONFIG_FILE does not exist. Aborting."
   exit
fi

# Check operation type
case $CHECKONLY in
     y) $ECHO "Checking specified operation type... \c" ;;
esac
case $OPERATION in
     full|FULL|cold|COLD|level0|LEVEL0|level1i|LEVEL1I|level1c|LEVEL1C|level2i|LEVEL2I|level2c|LEVEL2C|arch|ARCH) ;;
     *) log_message "Invalid operation specified."
        log_message "Use ${0} -h for list of operation types. Exiting."
        exit ;;
esac
case $CHECKONLY in
     y) $ECHO "ok." ;;
esac

# read parameters from config file
TARGET_USER=`egrep -i '^targetuser' $CONFIG_FILE | cut -d '=' -f 2`
TARGET_PASS=`egrep -i '^targetpass' $CONFIG_FILE | cut -d '=' -f 2`
DESTINATION=`egrep -i '^destination' $CONFIG_FILE | cut -d '=' -f 2`
DIRECTORY=`egrep -i '^directory' $CONFIG_FILE | cut -d '=' -f 2`
MAILTO=`egrep -i '^mailto' $CONFIG_FILE | cut -d '=' -f 2`
RETENTION=`egrep -i '^retention' $CONFIG_FILE | cut -d '=' -f 2`

case $CHECKONLY in
     y) $ECHO "Checking for defined parameters..." ;;
esac

# check for undefined parameters
case $CHECKONLY in
     y) $ECHO "targetuser \c" ;;
esac
case $TARGET_USER in
     "") log_message "Target username not specified in configuration file. Exiting."
         exit ;;
esac

case $CHECKONLY in
     y) $ECHO "targetpass \c" ;;
esac
case $TARGET_PASS in
     "") log_message "Target password not specified in configuration file. Exiting."
         exit ;;
esac

case $CHECKONLY in
     y) $ECHO "retention \c" ;;
esac
case $RETENTION in
     "") log_message "Retention policy not specified in configuration file. Exiting."
         exit ;;
esac

case $CHECKONLY in
     y) $ECHO "destination \c" ;;
esac
case $DESTINATION in
     "") log_message "Destination not specified in configuration file. Exiting."
         exit ;;
esac

case $DESTINATION in
     disk|DISK) DESTINATION="disk"
        case $CHECKONLY in
             y) $ECHO "directory" ;;
        esac
        case "$DIRECTORY" in
             "") log_message "Directory for disk backup not specified in configuration file. Exiting."
                 exit ;;
             *) if [ ! -d "$DIRECTORY" ] ; then
                   log_message "Directory ($DIRECTORY) specified in configuration file does not exist. Exiting."
                   exit
                fi
                # Check to be able to create files in specified directory
                case $CHECKONLY in
                     y) $ECHO "Test writing to directory... \c" ;;
                esac
                testfile=$DIRECTORY/`date +'%y%m%d%H%M%S'`
                touch $testfile
                status=$?
                if [ $status -gt 0 ] ; then
                   log_message "Unable to write to directory: $DIRECTORY. Exiting."
                   exit;
                else
                   rm $testfile
                   case $CHECKONLY in
                        y) $ECHO "ok." ;;
                   esac
                fi ;;
        esac
        DESTINATION="disk" ;;
     tape|TAPE) DESTINATION="'sbt_tape'" ;;
     *) log_message "Invalid destination specified in configuration file."
        log_message "Destination must be one of 'tape' or 'disk'. Exiting."
         exit ;;
esac

case $CHECKONLY in
     y) $ECHO "Administrator (mailto)" ;;
esac
case $MAILTO in
     "") log_message "Administrator (MAILTO) not specified in configuration file. Exiting."
         exit ;;
esac

# Test connectivity

case $CHECKONLY in
     y) $ECHO "Testing Connectivity to Database... \c" ;;
esac

# Target Database Username/password connect test
connectfile=/tmp/connect.`date +'%y%m%d%H%M%S'`
sqlplus /nolog <<! > $connectfile
connect $TARGET_USER/$TARGET_PASS
!
stat=`grep ORA- $connectfile`
if [ ! -z "$stat" ] ; then
   log_message "Error encountered when connecting to target database."
   $ECHO "The following errors were encountered. Exiting.\n" | tee -a $LOGFILE
   cat $connectfile |grep ORA-| tee -a $LOGFILE
   rm $connectfile
   exit
fi
rm $connectfile
case $CHECKONLY in
     y) $ECHO "connect to Target DB ok.\n" ;;
esac

case $DIRECTORY in
     "") DIRECTORY="Not applicable" ;;
esac

cat <<!>>$LOGFILE
Target username:    $TARGET_USER
Target password:    $TARGET_PASS
Destination:        $DESTINATION
Directory (if app): $DIRECTORY
Retention (days):   $RETENTION
Mail to:            $MAILTO
!

case $CHECKONLY in
     y) $ECHO "Configuration check complete. All tests passed.\n" ;;
esac

}

###############################################################################
log_message ()
{
# Function used to log a message to syslog and to stdout

# First send to stdout
$ECHO "$1" | tee -a $LOGFILE

# Also log to syslog
logger -p user.err "ERROR: DATABASE BACKUP $1"

}

###############################################################################
run_spec_op ()
{
$ECHO "Ensuring recovery window retention period is set...">>$LOGFILE
rman<<!>>$LOGFILE
connect target $TARGET_USER/$TARGET_PASS
run {
configure retention policy to redundancy $RETENTION;
}
!

# First ensure that operation specified is valid

case $OPERATION in
     full|FULL)       backup_full ;;
     cold|COLD)       backup_cold ;;
     level0|LEVEL0)   backup_level_0 ;;
     level1i|LEVEL1I) backup_level_1i ;;
     level1c|LEVEL1C) backup_level_1c ;;
     level2i|LEVEL2I) backup_level_2i ;;
     level2c|LEVEL2C) backup_level_2c ;;
     arch|ARCH)       get_arch_log_backup ;;
esac

}

###############################################################################
backup_full ()
{

# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="fulldb_%U"
                 CTLFORMAT="fulldb_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/fulldb_%U"
                 CTLFORMAT="$DIRECTORY/fulldb_ctl_%F" ;;
esac

# Then perform the backup operation

$ECHO "\nPerforming Full Online Backup..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
full
tag backup_db_full
filesperset 50
format '$FORMAT'
check logical database;
}
!

# Check for errors
check_for_errors

if [ "$SERVERTYPE" = "STREAMS" ]; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
backup_cold ()
{

# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="colddb_%U"
                 CTLFORMAT="colddb_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/colddb_%U"
                 CTLFORMAT="$DIRECTORY/colddb_ctl_%F" ;;
esac

# Then perform the backup operation

$ECHO "\nPerforming Full Offline (cold) Backup..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

# Shutdown the database
shutdown immediate
# Bring the db back up momentarily
startup dba
# Bring it down again
shutdown immediate
# Start the instance and mount the db (do not open)
startup mount

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
full
tag backup_db_cold
filesperset 50
format '$FORMAT'
check logical database;
}

# Shut the db down again
shutdown immediate
# Bring it back up
startup

!

# Check for errors
check_for_errors

if [ "$SERVERTYPE" = "STREAMS" ]; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
backup_level_0 ()
{

# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="i0db_%U"
                 CTLFORMAT="i0db_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/i0db_%U"
                 CTLFORMAT="$DIRECTORY/i0db_ctl_%F" ;;
esac

# Then perform the backup operation

$ECHO "\nPerforming Backup Level 0..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
incremental level 0
tag backup_db_level_0
filesperset 50
Format '$FORMAT'
check logical database;
}
!

# Check for errors
check_for_errors

if [ "$SERVERTYPE" = "STREAMS" ] ; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
backup_level_1i ()
{

# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="i1db_%U"
                 CTLFORMAT="i1db_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/i1db_%U"
                 CTLFORMAT="$DIRECTORY/i1db_ctl_%F" ;;
esac

# Then perform the backup operation

$ECHO "Performing Incremental Backup Level 1..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
incremental level 1
tag backup_db_level_1
filesperset 50
format '$FORMAT'
check logical database;
}
!

# Check for errors
check_for_errors

if [ "$SERVERTYPE" = "STREAMS" ]; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
backup_level_1c ()
{

# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="ic1db_%U"
                 CTLFORMAT="ic1db_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/ic1db_%U"
                 CTLFORMAT="$DIRECTORY/ic1db_ctl_%F" ;;
esac

# Then perform the backup operation

$ECHO "Performing Cumulative Incremental Backup Level 1..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
incremental level 1 cumulative
tag backup_db_level_1c
filesperset 50
format '$FORMAT'
check logical database;
}
!

# Check for errors
check_for_errors

if [ "$SERVERTYPE" = "STREAMS" ]; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
backup_level_2i ()
{

# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="i2db_%U"
                 CTLFORMAT="i2db_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/i2db_%U"
                 CTLFORMAT="$DIRECTORY/i2db_ctl_%F" ;;
esac

# Then perform the backup operation

$ECHO "Performing Incremental Backup Level 2..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
incremental level 2
tag backup_db_level_2
filesperset 50
format '$FORMAT'
check logical database;
}
!

# Check for errors
check_for_errors

if [ "$SERVERTYPE" = "STREAMS" ]; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
backup_level_2c ()
{

# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="ic2db_%U"
                 CTLFORMAT="ic2db_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/ic2db_%U"
                 CTLFORMAT="$DIRECTORY/ic2db_ctl_%F" ;;
esac

# Then perform the backup operation

$ECHO "Performing Cumulative Incremental Backup Level 2..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
incremental level 2 cumulative
tag backup_db_level_2c
filesperset 50
format '$FORMAT'
check logical database;
}
!

# Check for errors
check_for_errors

if [ "$SERVERTYPE" = "STREAMS" ] ; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
get_arch_log_backup ()
{

if [ "$SERVERTYPE" = "STREAMS" ]; then
   backup_arch_log_streams
else
   backup_archive_log
fi

}

###############################################################################
backup_archive_log ()
{
# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="arch_%U"
                 CTLFORMAT="arch_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/arch_%U"
                 CTLFORMAT="$DIRECTORY/arch_ctl_%F" ;;
esac

$ECHO "\nPerforming Archive Log Backup..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure controlfile autobackup on;
configure controlfile autobackup format for device type $DESTINATION to '$CTLFORMAT';
configure device type $DESTINATION$PARALLEL;
backup
filesperset 50
format '$FORMAT'
archivelog all delete input;
}
!

# Check for errors
check_for_errors

}

###############################################################################
backup_arch_log_streams ()
{
# Set FORMAT
case $DESTINATION in
   "'sbt_tape'") FORMAT="arch_%U"
                 CTLFORMAT="arch_ctl_%F" ;;
   "disk")       FORMAT="$DIRECTORY/arch_%U"
                 CTLFORMAT="$DIRECTORY/arch_ctl_%F" ;;
esac

get_arch_log_seq

$ECHO "\nPerforming Archive Log Backup..."|tee -a $LOGFILE

$ECHO "Backing up currently archived log files until sequence number $LOGSEQ ..."|tee -a $LOGFILE

rman <<!>> $LOGFILE

connect target $TARGET_USER/$TARGET_PASS

run {
configure device type $DESTINATION$PARALLEL;
backup
filesperset 50
format '$FORMAT'
archivelog until logseq $LOGSEQ delete input;
}
!

# Check for errors
check_for_errors

}
###############################################################################
get_arch_log_seq ()
{

# Find the Minimum Necessary to Restart Capture

sqlplus /nolog <<! > $WSPTEMP
connect / as sysdba
set serveroutput on
DECLARE
 hScn number := 0;
 lScn number := 0;
 sScn number;
 ascn number;
 seqnum number;
 alog varchar2(1000);
begin
  select min(start_scn), min(applied_scn) into sScn, ascn
    from dba_capture;
  DBMS_OUTPUT.ENABLE(2000);
  for cr in (select distinct(a.ckpt_scn)
             from system.logmnr_restart_ckpt$ a
             where a.ckpt_scn <= ascn and a.valid = 1
             and exists (select * from system.logmnr_log$ l
               where a.ckpt_scn between l.first_change# and l.next_change#)
             order by a.ckpt_scn desc)
  loop
    if (hScn = 0) then
       hScn := cr.ckpt_scn;
    else
       lScn := cr.ckpt_scn;
       exit;
    end if;
  end loop;
  if lScn = 0 then
    lScn := sScn;
  end if;
  select min(sequence#) into seqnum
    from DBA_REGISTERED_ARCHIVED_LOG
   where lScn between first_scn and next_scn
   and purgeable='NO';
  dbms_output.put_line('MINARCHLOG='||to_char(seqnum));
  dbms_output.put_line('LOGSEQ='||to_char(seqnum-1));
end;
/

!

MINARCHLOG=`egrep 'MINARCHLOG' $WSPTEMP | cut -d '=' -f 2`
LOGSEQ=`egrep 'LOGSEQ' $WSPTEMP | cut -d '=' -f 2`

$ECHO "\n\nMinimum Archive Log Sequence to Start Capture: $MINARCHLOG" >> $LOGFILE

}
###############################################################################
check_for_errors ()
{
        egrep "ORA-|RMAN-|PLS-" $LOGFILE |grep -v ORA-02011|grep -v ORA-00955|grep -v ORA-01434 > /dev/null
        oerr_check=$?

        case $oerr_check in
                0) printf "\n\nErrors were encountered while performing operation!!!\n"
                printf "Check $LOGFILE file for details.\n"
                exit 1 ;;
                1) printf "No errors found.\n"
        esac

}

###############################################################################
mail_logfile ()
{
# Send logfile of operation to designated administrator (mailto)

$ECHO "Sending output of operation to administrator(s)\n"
mailx -s "$1:Database Backup Report for `uname -n`" $MAILTO < $LOGFILE

}

###############################################################################
finished_notification ()
{
rm -f $WSPTEMP
date >> $LOGFILE
$ECHO "\nSpecified Database Backup Operation Completed.\n"|tee -a $LOGFILE
}

###############################################################################
# Main


printf %b "\nDatabase Backup\n" |tee -a $LOGFILE
printf %b "===============\n" |tee -a $LOGFILE
printf %b "This script will perform a RMAN backup of the database\n" |tee -a $LOGFILE

setup_env

if [ $# -eq 1 ]
then
        case $1 in
        -[vV]*) exit ;;
        -[hH]*)
                $ECHO "\nUsage: ${0} {configfile} {operation} [-c]\n"
                $ECHO "where:"
                $ECHO "  configfile = Full path name for configuration settings"
                $ECHO "  operation  = Type of backup operation to perform\n"
                $ECHO "List of valid operations:"
                $ECHO "  full    = full online database backup"
                $ECHO "  cold    = full offline database backup"
                $ECHO "  level0  = incremental level 0 backup"
                $ECHO "  level1i = incremental level 1 backup"
                $ECHO "  level1c = cumulative level 1 backup"
                $ECHO "  level2i = incremental level 2 backup"
                $ECHO "  level2c = cumulative level 2 backup"
                $ECHO "  arch    = backup and remove all archived logfiles"
                exit ;;
        esac
fi

if [ $# -lt 2 ]
then
        $ECHO "\nUsage: ${0} {configfile} {operation} [-c]\n"
        $ECHO "where:"
        $ECHO "  configfile = File name for configuration settings"
        $ECHO "  operation  = Type of backup operation to perform"
        $ECHO "               (use ${0} -h for full list)"
        $ECHO "          -c = Perform check of configuration file only"
        exit
else
        CONFIG_FILE=$1
        OPERATION=$2
        case $3 in
           -[cC]*) $ECHO "Checking configuration file only...\n" | tee -a $LOGFILE
                   CHECKONLY=y
                   check_config
                   exit ;;
        esac
fi

check_config

get_server_type

run_spec_op

finished_notification

mail_logfile "INFO"

