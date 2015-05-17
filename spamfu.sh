#							   +----+----+----+----+
# 							   |    |    |    |    |
# Author: Mark David Scott Cunningham			   | M  | D  | S  | C  |
# 							   +----+----+----+----+
# Created: 2015-04-23
# Updated: 2015-05-10
#
#
#!/bin/bash

# Inspiration from previous work by: mwineland
# With php_maillog functions assisted by: mcarmack

#-----------------------------------------------------------------------------#
## Because /moar/ regex is always better
shopt -s extglob

#-----------------------------------------------------------------------------#
## Utility functions, because prettier is better
dash(){ for ((i=1;i<=$1;i++)); do printf $2; done; }
section_header(){ echo -e "\n$1\n$(dash 40 -)"; }

#-----------------------------------------------------------------------------#
## Initializations
LOGFILE="/var/log/exim_mainlog"
QUEUEFILE="/tmp/exim_queue_$(date +%Y.%m.%d_%H).00"
PHPLOG="/var/log/php_maillog"
l=1; p=0; q=0; full_log=0;
LINECOUNT='1000000'
RESULTCOUNT='10'
PHPCONF=$(php -i | awk '/php.ini$/ {print $NF}');
PHPLOG=$(awk '/mail.log/ {print $NF}' $PHPCONF);

#-----------------------------------------------------------------------------#
# Menu scripting
#-----------------------------------------------------------------------------#
## Lines to read from the log file
line_count_menu(){
  PS3="Enter selection or linecount: "
  echo -e "\nHow many lines to analyze?\n$(dash 40 -)"
  select LINES in "Last 1,000,000 lines" "All of it" "Quit"; do
    case $LINES in
      "Quit") l=0; q=0; p=0; break ;;
      "All of it") full_log=1; break ;;
      "Last 1,000,000 lines") break ;;
      *) if [[ ${REPLY} =~ ([0-9]) ]]; then LINECOUNT=${REPLY}; break;
         else echo "Invalid input, using defaults."; break; fi ;;
    esac
  done
}

#-----------------------------------------------------------------------------#
## Select a log file from what's on the server
log_select_menu(){
  echo -e "\nWhich file?\n$(dash 40 -)\n$(du -sh $1)\n"
  select LOGS in $1 "Quit"; do
    case $LOGS in
      "Quit") l=0; q=0; p=0; break ;;
      *) if [[ -f $LOGS ]]; then LOGFILE=$LOGS; PHPLOG=$LOGS; break;
         elif [[ -f ${REPLY} ]]; then LOGFILE=${REPLY}; PHPLOG=${REPLY}; break;
         else echo -e "\nPlease enter a valid option.\n"; fi ;;
    esac
  done;
}

#-----------------------------------------------------------------------------#
# How many results to show
results_prompt(){
  if [[ $1 != '0' ]]; then
    echo; read -p "How many results do you want? [10]: " NEWCOUNT;
    if [[ -n $NEWCOUNT ]]; then RESULTCOUNT=$NEWCOUNT; fi;
  fi
}

#-----------------------------------------------------------------------------#
# Setup how much of the log file to read and how.
set_decomp(){
  # Compressed file -- decompress and read whole log
  if [[ $(file -b $1) =~ zip ]]; then
    DECOMP="zcat -f";
    du -sh $1 | awk '{print "Using Log File: "$2,"("$1")"}'
  # Read full log (uncompressed)
  elif [[ $full_log == 1 ]]; then
    DECOMP="cat";
    du -sh $1 | awk '{print "Using Log File: "$2,"("$1")"}'
    head -1 $1 | awk '{print "First date in log: "$1,$2}';
    tail -1 $1 | awk '{print "Last date in log: "$1,$2}'
  # Minimize impact on initial scan, using last 1,000,000 lines
  else
    DECOMP="tail -n $LINECOUNT";
    du -sh $1 | awk -v LINES="$LINECOUNT" '{print "Last",LINES,"lines of: "$2,"("$1")"}';
fi
}


if [[ -z $@ ]]; then

#-----------------------------------------------------------------------------#
# Menus for the un-initiated
#-----------------------------------------------------------------------------#
## MAIN MENU BEGIN
PS3="Enter selection: ";
clear
echo -e "$(dash 80 =)\nCurrent Queue: $(exim -bpc)\n$(dash 40 -)\n\nWhat would you like to do?\n$(dash 40 -)"
select OPTION in "Analyze Exim Logs" "Analyze PHP Logs" "Analyze Exim Queue" "Quit"; do
  case $OPTION in

    "Analyze Exim Logs")
      log_select_menu "/var/log/exim_mainlog*"
      if [[ $l != '0' && ! $(file -b $LOGFILE) =~ zip ]]; then line_count_menu; fi
      results_prompt $l; break ;;

    "Analyze PHP Logs")
      l=0; p=1; q=0; log_select_menu "${PHPLOG}*";
      if [[ $p != '0' && ! $(file -b $PHPLOG) =~ zip ]]; then line_count_menu; fi
      results_prompt $p;
      break;;

    "Analyze Exim Queue")
      l=0; q=1; p=0; line_count_menu; results_prompt $q; break ;;

    "Quit") l=0; q=0; p=0; break ;;

    *) echo -e "\nPlease enter a valid option.\n" ;;

  esac;
done;
clear
## MAIN MENU END

else
#-----------------------------------------------------------------------------#
# Process commandline flags
while getopts fhl:n:pqc: OPTIONS; do
  case "${OPTIONS}" in
    c) LINECOUNT=${OPTARG} ;;
    f) full_log=1 ;;
    l) LOGFILE=${OPTARG}; QUEUEFILE=${OPTARG}; PHPLOG=${OPTARG} ;; # Specify a log/queue file
    n) RESULTCOUNT=${OPTARG} ;;
    p) l=0; p=1; q=0 ;; # PHP log
    q) l=0; q=1; p=0 ;; # Analyze queue instead of log
    ## t) t=${OPTARG};; # Set a timeframe [log/queue] to analyze
    h) echo -e "\nUsage: $0 [OPTIONS]\n
    -c ... <#lines> to read from the end of the log
    -f ... Read full log (instead of last 1M lines)
    -l ... <logfile> to use instead of default
    -n ... <#results> to show from analysis
    -p ... Look for 'X-PHP-Script' in the php mail log
    -q ... Create a queue logfile and analyze the queue\n
    -h ... Print this help and quit\n"; exit ;; # Print help and quit
  esac
done
fi

#-----------------------------------------------------------------------------#
## Setup the log file analysis methods
mail_logs(){
# This will run a basic analysis of the exim_mainlog

echo; set_decomp $LOGFILE;

## Count of messages sent by scripts
section_header "Directories"
$DECOMP $LOGFILE | grep 'cwd=' | perl -pe 's/.*cwd=(\/.*?)\ .*/\1/g'\
 | awk '!/spool|error/ {freq[$0]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | head -n $RESULTCOUNT

# Count of Messages per account
# section_header "Accounts"
# $DECOMP $LOGFILE | grep -o '<=\ [^<>].*U=.*\ ' | perl -pe 's/.*U=(.*?)\ .*/\1/g' | awk '{freq[$1]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}' | sort -rn | head -n $RESULTCOUNT

# Count of messages per "Account/Domains"
section_header "Accounts/Domains"
$DECOMP $LOGFILE | grep -o '<=\ [^<>].*\ U=.*\ P=' | perl -pe 's/.*@(.*?)\ U=(.*?)\ P=/\2 \1/g'\
 | awk '{freq[$0]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | head -n $RESULTCOUNT | awk '{printf "%8s %-10s %s\n",$1,$2,$3}'

# Count of messages per Auth-Users
section_header "Auth-Users"
$DECOMP $LOGFILE | grep -Eo 'A=.*in:.*\ S=' | perl -pe 's/.*:(.*?)\ S=/\1/g' | awk '{freq[$0]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}' | sort -rn | head -n $RESULTCOUNT

# Count of IPs per Auth-Users
section_header "IP-Addresses/Auth-Users"
$DECOMP $LOGFILE | grep 'A=.*in:' | perl -pe 's/.*[^I=]\[(.*?)\].*A=.*in:(.*?)\ S=.*$/\1 \2/g'\
 | awk '{freq[$0]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | head -n $RESULTCOUNT | awk '{printf "%8s %-15s %s\n",$1,$2,$3}'

# Spoofed Sender Addresses
section_header "Spoofed Senders"
FMT="%8s %-35s %s\n"
printf "$FMT" "Count " " Auth-User" " Spoofed-User"
printf "$FMT" "--------" "$(dash 35 -)" "$(dash 35 -)"
$DECOMP $LOGFILE | grep '<=.*in:' | perl -pe 's/.*<=\ (.*?)\ .*A=.*in:(.*?)\ .*/\2 \1/g'\
 | awk '{ if ($1 != $2) freq[$0]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | head -n $RESULTCOUNT | awk -v FMT="$FMT" '{printf FMT,$1" ",$2,$3}'
printf "$FMT" "--------" "$(dash 35 -)" "$(dash 35 -)"

# Show sent messages with the most recipients
section_header "Bulk Senders"
FMT="%8s %-16s %s\n"
printf "$FMT" "RCPTs " " MessageID" " Auth-User"
printf "$FMT" "--------" "$(dash 16 -)" "$(dash 40 -)"
$DECOMP $LOGFILE | grep "<=.*A=.*in:.*\ for\ "\
 | perl -pe 's/.*\ (.*?)\ <=\ .*A=.*in:(.*)\ S=.*\ for\ (.*)//g; print $count = scalar(split(" ",$3))," ",$1," ",$2;'\
 | sort -rn | head -n $RESULTCOUNT | awk -v FMT="$FMT" '{printf FMT,$1" ",$2,$3}'
printf "$FMT" "--------" "$(dash 16 -)" "$(dash 40 -)"

# Count of Messages by Subject
section_header "Subjects (Non-Bounceback)"
$DECOMP $LOGFILE | grep '<=.*T=' | perl -pe 's/.*\"(.*?)\".*/\1/g'\
 | awk '!/failed: |deferred: / {freq[$0]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | head -n $RESULTCOUNT

# Count of From Addresses
#section_header "From Addresses"
#awk '/<=/ && !/U=mailnull/ {freq[$6]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}' $LOGFILE | sort -rn | head -n $RESULTCOUNT

# Count of To Addresses
#section_header "To Addresses"
# awk '/<=/ && !/U=mailnull/ {freq[$NF]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}' $LOGFILE | sort -rn | head -n $RESULTCOUNT

# Count of Bouncebacks by address
section_header "Bouncebacks (address)"
$DECOMP $LOGFILE | grep 'U=mailnull' | perl -pe 's/.*\".*for\ (.*$)/\1/g'\
 | awk '{freq[$0]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | head -n $RESULTCOUNT

# Count of Bouncebacks by domain
# section_header "Bouncebacks (domain)"
# awk -F@ '/U=mailnull/ {freq[$NF]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}' $LOGFILE | sort -rn | head -n $RESULTCOUNT

# Count of IPs sending mail
# echo -e "\nIP-Addresses"
# awk '/<=/ && ($7 ~ /H=/) && ($8 ~ /\[.*\]/) {print $8}' $LOGFILE | cut -d\] -f1 | sort | uniq -c | sort -rn | tr -d \[ | head -n $RESULTCOUNT

# Find Subjects for an auth user
# echo -e "\nSubjects for Auth $EMAILADDR"
# awk -F\" "/<= $EMAILADDR/"'{print $2}' $LOGFILE | sort | uniq -c | sort -rn | head -n $RESULTCOUNT

# Find IPs for an auth user
# echo -e "\nIPs for Auth $EMAILADDR"
# awk "/<= $EMAILADDR/"'{print $8}' $LOGFILE | cut -d: -f1 | sort | uniq -c | sort -rn | head -n $RESULTCOUNT | tr -d '[]'

echo
}

#-----------------------------------------------------------------------------#
## Setup the queue/file analysis methods
mail_queue(){
# This will run a basic summary of the mail queue, using both exim -bp and /var/spool/exim/input/*

## Current Queue Dump
if [[ -f $QUEUEFILE ]]; then
  echo -e "\nFound existing queue dump from this hour ( $(date +%Y.%m.%d_%H).00 ).\n"
else
  echo -e "\nCreating Queue Dump to speed up analysis ... Thank you for your patience"
  exim -bp > $QUEUEFILE
fi

# Read full log (uncompressed)
if [[ $full_log == 1 ]]; then
  DECOMP="cat";
  du -sh $QUEUEFILE | awk '{print "Using Queue Dump: "$2,"("$1")"}'
# Minimize impact on initial scan, using last 1,000,000 lines
else
  DECOMP="tail -$LINECOUNT";
  du -sh $QUEUEFILE | awk -v LINES="$LINECOUNT" '{print "Last",LINES,"lines of: "$2,"("$1")"}';
fi

## Queue Summary
section_header "Queue: Summary"
if [[ -n $(head $QUEUEFILE) ]]; then
$DECOMP $QUEUEFILE | exiqsumm | head -3 | tail -2;
cat $QUEUEFILE | exiqsumm | sort -rnk1 | grep -v "TOTAL$" | head -n $RESULTCOUNT
fi
#exim -bp | exiqsumm

## Queue Senders
section_header "Queue: Auth Users"
find /var/spool/exim/input/ -type f -name "*-H" -print | xargs grep --no-filename 'auth_id'\
 | sed 's/-auth_id //g' | sort | uniq -c | sort -rn | head -n $RESULTCOUNT

## Queue Subjects
# http://www.commandlinefu.com/commands/view/9758/sort-and-count-subjects-of-emails-stuck-in-exim-queue
section_header "Queue: Subjects"
find /var/spool/exim/input/ -type f -print | xargs grep --no-filename "Subject: "\
 | sed 's/.*Subject: //g' | sort | uniq -c | sort -rn | head -n $RESULTCOUNT

## Queue Scripts
section_header "Queue: X-PHP-Scripts"
find /var/spool/exim/input/ -type f -print | xargs grep --no-filename "X-PHP.*-Script:"\
 | sed 's/^.*X-PHP.*-Script: //g;s/\ for\ .*$//g' | sort | uniq -c | sort -rn | head -n $RESULTCOUNT

## Count of (non-bounceback) Sending Addresses in queue
section_header "Queue: Senders"
$DECOMP $QUEUEFILE | awk '($4 ~ /<[^>]/) {freq[$4]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | tr -d '<>' | head -n $RESULTCOUNT

## Count of Bouncebacks in the queue
section_header "Queue: Bouncebacks (count)"
$DECOMP $QUEUEFILE | awk '($4 ~ /<>/) {freq[$4]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn | head -n $RESULTCOUNT

## Count of 'frozen' messages by user
section_header "Queue: Frozen (count)"
$DECOMP $QUEUEFILE | awk '/frozen/ {freq[$4]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}'\
 | sort -rn  | head -n $RESULTCOUNT | sed 's/<>/*** Bounceback ***/' | tr -d '<>'

# echo -e "\nRemove Frozen Bouncebacks:\nawk '/<>.*frozen/ {print \$3}' $QUEUEFILE | xargs exim -Mrm > /dev/null"
# echo -e "find /var/spool/exim/msglog/ | xargs egrep -l \"P=local\" | cut -b26- | xargs -P6 -n500 exim -Mrm > /dev/null"

## Bounceback IDs in the queue
# cat $QUEUEFILE | awk '($4 ~ /<>/) {print $3}'

## Frozen Message IDs
# awk '/frozen/ {print $3}' $QUEUEFILE

echo
}

mail_php(){
# This checks to see if the php_maillog has been enabled, and if so, then
# runs a simple analysis of the scripts sending mail from that log.

# Warning
echo -e "\n ... Work in progress\n\n$(php -v | head -1)\n"

# Check if add_x_header is on
if [[ -n $(grep '^mail.add_x_header.*On' $PHPCONF) ]]; then
  echo "php.ini : $PHPCONF"
  echo "mail.log: $PHPLOG ($(du -sh $PHPLOG | awk '{print $1}'))"
  echo -e "X_Header: Enabled\n"

  set_decomp $PHPLOG;

  # Look for mailer scripts in the php_maillog
  section_header "PHP Mailer Scripts"
  $DECOMP $PHPLOG | grep '/home' | perl -pe 's/.*\[(.*?)\]/\1/g'\
   | awk -F: '{freq[$1]++} END {for (x in freq) {printf "%8s %s\n",freq[x],x}}' | sort -rn | head -n $RESULTCOUNT

  echo
else
  echo "X_Header: Disabled"
fi

}

#-----------------------------------------------------------------------------#
## Run either logs() or queue() function
if [[ $l == 1 ]]; then mail_logs
elif [[ $q == 1 ]]; then mail_queue
elif [[ $p == 1 ]]; then mail_php; fi

#~Fin~
