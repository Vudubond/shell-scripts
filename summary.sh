#							   +----+----+----+----+
# 							   |    |    |    |    |
# Author: Mark David Scott Cunningham			   | M  | D  | S  | C  |
# 							   +----+----+----+----+
# Created: 2014-08-24
# Updated: 2014-08-27
#
# Based on work by Ted Wells
#
#!/bin/bash

serverName(){
  if [[ -n $(dig +time=1 +tries=1 +short $(hostname)) ]]; then hostname;
  else ip addr show | awk '/inet / {print $2}' | cut -d/ -f1 | grep -Ev '^127\.' | head -1; fi
  }

echo
FMT='%-14s: %s\n'

# CentOS and Kernel Versions
printf "$FMT" "OS (Kernel)" "$(cat /etc/redhat-release | awk '{print $1,$3}') ($(uname -r))"

# Web Server
ssl="$(openssl version | awk '{print $2}')"
web="$(curl -s -I $(serverName) | awk '/Server:/ {print $2}')";
if [[ $web =~ Apache ]]; then webver=$(httpd -v | head -1 | awk '{print $3}' | sed 's:/: :');
elif [[ $web =~ LiteSpeed ]]; then webver=$(/usr/local/lsws/bin/lshttpd -v | sed 's:/: :'); fi;
printf "$FMT" "Web Server" "$webver; OpenSSL ($ssl)"

# PHP Version/Type
phpv=$(php -v | awk '/^PHP/ {print $2}')
ionc=$(php -v | awk '/ionCube/ {print "; "$3" ("$6")"}' | sed 's/v//;s/,//')
eacc=$(php -v | awk '/eAcc/ {print "; "$2" ("$3")"}' | sed 's/v//;s/,//')
zend=$(php -v | awk '/Engine/ {print "; "$1,$2" ("$3")"}' | sed 's/v//;s/,//')
guard=$(php -v | awk '/Guard/ {print "; "$2,$3" ("$5")"}' | sed 's/v//;s/,//')
suhos=$(php -v | awk '/Suhosin/ {print "; "$2" ("$3")"}' | sed 's/v//;s/,//')
if [[ -d /etc/php-fpm.d/ ]]; then phpt='php-fpm'; else
phpt=$(awk '/^LoadModule/ {print $2}' /etc/httpd/conf.d/php.conf /etc/httpd/conf.d/suphp.conf | sed 's/php[0-9]_module/mod_php/;s/_module//'); fi
printf "$FMT" "PHP Version" "${phpt} (${phpv})${zend}${ionc}${guard}${eacc}${suhos}"

# Modsec Version and Ruleset
modsecv=$(rpm -qi mod_security | awk '/Version/ {print $3}' 2> /dev/null)
modsecr=$(awk -F\" '/SecComp.*\"$/ {print "("$2")"}' /etc/httpd/modsecurity.d/*_crs_10_*.conf 2> /dev/null)
printf "$FMT" "ModSecurity" "${modsecv:-No ModSecurity} ${modsecr}"

# MySQL Version/Type
printf "$FMT" "MySQL Version" "$(mysql --version | awk '{print $5}' | tr -d ,) $(mysqld --version 2> /dev/null | grep -io 'percona' 2> /dev/null)"

# Interworx Version
printf "$FMT" "Interworx" "$(grep -A1 'user="iworx"' /home/interworx/iworx.ini | tail -1 | cut -d\" -f2)"

if [[ $1 =~ -v ]]; then
# Version Control
printf "$FMT" "Rev. Control" "Git ($(git --version | awk '{print $3}')); SVN ($(svn --version | awk 'NR<2 {print $3}')); $(hg --version | awk 'NR<2 {print $1" ("$NF}')"

# Scripting Languages
printf "$FMT" "Script Langs" "$(perl -v | awk '/v[0-9]/ {print "Perl ("$4")"}' | sed 's/v//'); $(python -V 2>&1 | awk '{print $1" ("$2")"}'); $(ruby -v | awk '{print "Ruby ("$2")"}')"

# FTP/SFTP/SSH
printf "$FMT" "FTP/sFTP/SSH" "ProFTPD ($(proftpd --version | awk '{print $3}')); OpenSSH ($(ssh -V 2>&1 | cut -d, -f1 | awk -F_ '{print $2}'))"
fi

# Installed Memory
printf "$FMT" "Memory (RAM)" "$(free -m | awk '/Mem/ {print ($2/1000)"G / "($4/1000)"G ("($4/$2*100)"% Free)"}')"

# Swap Space
printf "$FMT" "Memory (Swap)" "$(if [[ $(free -m | awk '/Swap/ {print $2}') != 0 ]]; then free -m | awk '/Swap/ {print ($2/1000)"G / "($4/1000)"G ("($4/$2*100)"% Free)"}'; else echo 'No Swap'; fi)"

# Free and total disk space
printf "$FMT" "HDD (/home)" "$(df -h /home | tail -1 | awk '{print $2" / "$4" ("($4/$2*100)"% Free)"}')"
echo
