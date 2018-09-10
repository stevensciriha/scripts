#!/usr/local/bin/perl
# v1.0 ssciriha Feb 28 2012

# Read in the 2 command line arguments provided with the script
$inputFilename = shift(@ARGV);
$configFilename = shift(@ARGV);

# Set the logging directory
$logfile_dir = "/var/log/";
$script_logfile = "LogSplitter.log";
$path_script_logfile = "$logfile_dir$script_logfile";

# Create the log file handle that logs all the script actions
open (LOG,">$path_script_logfile") or die "cannot open script log $!";
 select((select($LOG), $|=1)[0]);

$date = `date`;
print LOG "Starting up logsplitting script $date...\n\n";

# Validate command line arguments
if ((!$configFilename) || (!$inputFilename)) {
   print LOG "\nUsage: LogSplitter.sh <path to logfile> <path to config-file>\n\n";
   exit 1;
}

# Print out the PID for the script process to allow logrotate to HUP the script
open (PIDFILE,">/tmp/LogSplitter.pid") or die print LOG "cannot open pid file $!";
print PIDFILE "$$";
close(PIDFILE);


$nPatterns = 0;            # The number of patterns (messages) to look for

# Fixed set of logs configured in this Hash
%interfaceloglist = ( 'GXlog', '1', 'SDBPROVlog', '1', 'JMSlog', '1', 'PCPROVlog', '1', 'SOAPlog', '1' );

# Create string of the hash above to allow for simple printing
$interfaceloglist_string = join(' ',keys %interfaceloglist);


# The following block of code will open the LogSplitter configuration file passed in the arguments and do the following:
# 1. Check that the configuration file is properly formatted in the following manner /<regex string>/<interface log>/
# 2. If properly formatted it will check that the interface log specified is one of the 5 allowed interfaces
print LOG "Loading configuration file $configFilename...\n\n";
open FP, $configFilename or die print LOG "can't open config file $configFilename";
while (<FP>) {
  next if /^\s*?$|^#|^\s*?#/;

  if (/^\/(.*)\/([A-Za-z]+)\/$/)
    {
      $pattern[$nPatterns] = $1;
      $interfacelogfile[$nPatterns] = $2;
      if (!exists ($interfaceloglist{$interfacelogfile[$nPatterns]}))
             {
             print LOG "\n$interfacelogfile[$nPatterns] is NOT a valid interface log...the interface log configured must match one of the following strings: ".$interfaceloglist_string. "\n\n";
             }
    }
  else
    {
    die print LOG "invalid log monitor entry: $_";
    }

  $nPatterns++;
}
close FP;


# This foreach loop checks to see if an interface logfile exists and is writable if not it will create it
foreach (@interfacelogfile)
 {
 $absolute_logfile = "$logfile_dir$_";
    if (-e $absolute_logfile)
       {
        if (! -w $absolute_logfile)
             {
              print LOG "logfile $absolute_logfile exists but is corrupted/not writeable. Exiting...\n";
              exit 2;
             }
        else
             {
              $interfacelog_FH = $_;
              open ($interfacelog_FH, ">>$absolute_logfile") or die "Cannot open $absolute_logfile\n";
              select((select($interfacelog_FH), $|=1)[0]);
             }
       }
     else
       {
       print LOG "\n$logfile_dir$_ does not exist. Creating...\n";
       `touch "$logfile_dir$_";chmod 777 "$logfile_dir$_"`;
       $interfacelog_FH = $_;
       open ($interfacelog_FH, ">>$absolute_logfile") or die print LOG "Cannot open $absolute_logfile\n";
       select((select($interfacelog_FH), $|=1)[0]);
}

 }


# this subroutine will trap the HUP signal from the logrotation which indicates that the interface logs are getting rotated
# so the filehandles need to be closed and opened for them to point to the new logfile
$SIG{HUP} = sub
     {
        foreach (@interfacelogfile)
         {
         $absolute_logfile = "$logfile_dir$_";
         close($_);
         open($_,">>$absolute_logfile") or die print LOG "cannot open logfile $absolute_logfile\n";
         select((select($_), $|=1)[0]);
         }
     };

# Here we are taking a STAT snapshot of the input logfile that we are reading from
# this will allow us to check if the log has been rotated or not by comparing file sizes

($dev, $ini, $mode, $nlink, $uid, $gid, $rdev, $curSize, $atime, $mtime, $ctime, $blksize, $blocks) = stat $inputFilename;


open (FP2, $inputFilename) or die print LOG "Cannot open $inputFilename\n";

# Always start at the end of the file
seek (FP2, 0, 2);

# If we get here it means that script has been started up successfully
print LOG "The logsplitter process has started up successfully and is now running...";
close(LOG);
open(LOG, ">>$path_script_logfile");

# This infinite loop is where we are constantly reading from the input logfile and writing out to the seperate interface logs
# In the loop we are comparing all the configured patterns to the current line we are reading and if it matches we print it
# out to appropriate interface log configured for that pattern
while (1)
   {
    while ($line = <FP2>)
        {
        for ($i = 0; $i < $nPatterns; $i++)
                {
                if ($line =~ /$pattern[$i]/)
                        {
                        $interfacelog_FH = $interfacelogfile[$i];
                        print $interfacelog_FH $line;
                        #`echo "$line" >> /var/log/$interfacelog_FH`;
                        }

                }
        }

  # No more logs to read (maybe none are being generated)
  # Remove the EOF flag to read new incoming logs
  seek (FP2, 0, 1);


# take another snapshot of the input logfile and comapre the current filesize to the original filesize...
# if its less then the log has been rotated so close and open the log filehandle
  ($dev, $ini, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = stat $inputFilename;
  if ($size < $curSize) {           # Log file has rolled over
    close (FP2);
    open (FP2, $inputFilename) or die print LOG "Cannot open $inputFilename\n";
  }

  $curSize = $size;

  # Sleep for X seconds before checking for new logs
  sleep (1);
}
