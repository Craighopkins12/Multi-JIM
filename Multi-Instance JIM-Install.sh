#!/bin/bash
# Purpose: Create multiple JIM instances to support different domains on a single JIM host.

### See end of script for license/copy-write/liability.

# How does it work?
#  
# JIM is just a java app. You can run more than one copy, each with its own configuration.
#  
# But… each one needs its own:
#  
# * Copy of the software
# * Port to listen on.
# * Init.d to start up
# * Log folder
# * Config file


# ######################################################################## 
# Test setup has 2 LDAP domains so we will setup 2 JIM instances
# ######################################################################## 
# JIM_Directory Domain Inbound_Port Assigned JIM external hostname
# ========================================================================
# jamf-im_dc1 dc1 1024 jim1.local
# jamf-im_dc2 dc2 1025 jim2.local


# ######################################################################## 
# User Settings:
# Enter a list of JIM instance names/numbers. 
# There will be one instance of JIM per domain...
declare -a domain_a=('_dc1' '_dc2');

# ########################################################################
# Before running this procedure...
# Ensure that the OS firewall will allow traffic inbound from the JSS to JIM. 
# * There will need to be one port per instance. These should be >= 1024
# Ensure that the internet proxy will allow traffic from JSS to JIM on these ports
# Ensure that the internet proxy will allow traffic from JIM to JSS HTTPS URL
# Ensure that external DNS or hosts file used by the JSS can resolve the 
# hostname alias for each JIM instance to the external IP address of the JIM host
# Ensure that internal DNS or hosts file used by the JIM can resolve the 
# hostname alias for each JIM instance to the internal IP address of the JIM host
# On the JIM host...
# yum install -y java-1.8.0-openjdk, or install the equivalent Oracle distribution
# On your Mac...
# Download jamf-im-1.1.0-1.noarch.rpm onto your Mac (the RHEL RPM is the 
# Jamf Nation>Assets>JIM>Alternative Downloads>Linux option)
# scp the rpm to your user folder on the JIM host. E.g.:
# scp "/Users/admin/Downloads/jamf-im-1.1.0-1.noarch.rpm" "root@10.0.1.9:/root"
# Back on the JIM host...
# Normally we would install with "sudo rpm -i ./jamf-im-1.1.0-1.noarch.rpm" but we will be using this script instead
# cd /root
# To find out what the JIM installer does, we can extract the rpm scripts with "rpm -qp --scripts ./jamf-im-1.1.0-1.noarch.rpm"
# Extract the rpm cpio archive files...

# ########################################################################

sourceDir="$HOME/jim"
mkdir "${sourceDir}"
(cd "${sourceDir}" && rpm2cpio /root/jamf-im-1.3.1-1.noarch.rpm | cpio -idmv)

# You now have this folder structure in your user folder.
# /$HOME/jim/
# |-etc
# |---bash_completion.d
# |---init.d
# |---jamf-im
# |-----jsam
# |-------logging
# |-usr
# |---bin
# |---share
# |-----jamf-im
# |-------bundles
# |-------lib
# ...and we're ready to begin.
# The JIM is just a java app that listens for LDAP traffic on an externally-facing 
# port then forwards it on passively to an LDAP server.
# The native installer puts files in the same paths as above relative to "/" 
# but there is no reason the file have to be in that location. So we can 
# make a few copies of the JIM files and adjust a few things so each instance 
# knows where it's files are. So below you will see a loop that copies the 
# unpacked files but into directories that include the domain instance name. 
# Then there are some sed find and replace commands to fix up the paths where
# the files call each other so they'll know where to find the different components. 
# Also, we will create a separate service account user. Probably not needed but
# it might help keep them away from each other so there's no possibility of 
# bleedover.


# ######################################################################## 
# If you are experimenting and need to undo this script...
# [!] snapshot before using rm -rF
# First, do a stop on each installed jim instance. E.g. "jamf-im_1 stop", etc.
# declare -a domain_a=('_mbp' '_mba');
# for domain in domain_a; do
# # remove the service startup
# chkconfig --del "jamf-im${domain}"
# # remove autocomplete util
# rm -f "/etc/bash_completion.d/jamf-im"
# # remove init.d
# rm -f "/etc/init.d/jamf-im${domain}"
# # remove the symlink to the main script
# rm -f "/bin/jamf-im${domain}"
# # remove the jsam files
# rm -fR "/etc/jamf-im${domain}"
# # remove the jim java programs
# rm -fR "/usr/share/jamf-im${domain}"
# # remove the felix-cache
# rm -fR "/var/lib/jamf-im${domain}"
# # remove the log files
# rm -fR "/var/log/jamf-im${domain}"
# /usr/sbin/userdel "jamfservice${domain}"
# /usr/sbin/groupdel "jamfservice${domain}"
# systemctl daemon-reload
# done
## In the jss database (after making a backup)
## Clear out the JIMs -- this is in the GUI now, so you can do it on cloud jsss
# TRUNCATE TABLE jsams;
# TRUNCATE TABLE jsam_invitations;
# ########################################################################

if [ $(id -u) -ne 0 ]; then
 echo "This script must be run with sudo." 1>&2
 exit 1
fi

#### Install the bash autocomplete for jim. Probably not worth the trouble to create 
# multiple copies for each domain so we won't...
if [[ ! -f "/etc/bash_completion.d/jamf-im" ]]; then
 completionfile="/etc/bash_completion.d/jamf-im"
 cp -R "${sourceDir}/etc/bash_completion.d/jamf-im" "${completionfile}"
 chmod 644 "${completionfile}"
 chown root:root "${completionfile}"
fi

for domain in "${domain_a[@]}"
do
# Vars...
 JSAM_USER="jamfservice${domain}"
 JSAM_USER_GROUP="jamfservice"
 JSAM_USER_COLON_GROUP="$JSAM_USER":"$JSAM_USER_GROUP"
logdir="/var/log"

#### STEP 1:
 #### Create init.d directive (tells OS how to start/stop/etc. the JIM service)...
 cp "${sourceDir}/etc/init.d/jamf-im" "/etc/init.d/jamf-im${domain}"
 chmod 755 "/etc/init.d/jamf-im${domain}"
 chown root:root "/etc/init.d/jamf-im${domain}"
 sed -i'' "s|jamf-im|jamf-im${domain}|g" "/etc/init.d/jamf-im${domain}"
 # Deamon script name should be put back the way it was...
 sed -i'' "s|jamf-im${domain}d.sh|jamf-imd.sh|g" "/etc/init.d/jamf-im${domain}"
 sed -i'' "s|--user \"jamfservice\"|--user ${JSAM_USER}|g" "/etc/init.d/jamf-im${domain}"
 # VERIFY: nano "/etc/init.d/jamf-im${domain}"


 #### STEP 2:
 #### Copy JSAM (JAMF Service Application Manager) files
 mkdir -p "/etc/jamf-im${domain}"
 cp -R "${sourceDir}/etc/jamf-im/jsam" "/etc/jamf-im${domain}/jsam"
# Modify path pointer in Felix Config properties
 sed -i'' "s|jamf-im|jamf-im${domain}|g" "/etc/jamf-im${domain}/jsam/felix.config.properties"
# Modify path pointer in System properties
 #sed -i'' "s|jsamLogPath|jsamLogPath${domain}|g" "/etc/jamf-im${domain}/jsam/felix.system.properties"
 sed -i'' "s|jamf-im|jamf-im${domain}|g" "/etc/jamf-im${domain}/jsam/felix.system.properties"
 # sed -i'' "s|\/var\/log|${logdir}|g" "/etc/jamf-im${domain}/jsam/felix.system.properties"
# LOG4 J
 # Need to update patterns
# Launcher
 #sed -i'' "s|jsamLogPath|jsamLogPath${domain}|g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im-launcher.xml"
# log4j2-jamf-im-pre-enroll-stderr.xml needs no changes
# Modify path pointer in pre-enroll
 #sed -i'' "s|jsamLogPath|jsamLogPath${domain}|g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im-pre-enroll.xml"
# Modify path pointer in base
 #sed -i'' "s|jsamLogPath|jsamLogPath${domain}|g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im.xml"
# Modify path pointer in pax logging cfg
 sed -i'' "s|\/etc\/jamf-im|\/etc\/jamf-im${domain}|g" "/etc/jamf-im${domain}/jsam/org.ops4j.pax.logging.cfg"
#### That takes care of the JSAM files. 

#### STEP 3:
 #### Change the logging output patterns so we can tell which instance logged which message...
# sed -i'' "s|%d |%d [${domain}] |g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im-launcher.xml"
 sed -i'' "s|.SSS} |.SSS} [${domain}] |g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im-pre-enroll-stderr.xml"
# sed -i'' "s|%d |%d [${domain}] |g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im-pre-enroll.xml"
# sed -i'' "s|%d |%d [${domain}] |g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im.xml"
# This is the wrong approach. ^^^ would be easier to just give each instance it's own logs folder. 
# See here: 
# Should do it like this...
# https://derflounder.wordpress.com/2017/11/04/implementing-log-rotation-for-the-jamf-infrastructure-manager-logs-on-red-hat-enterprise-linux/
### Give New Domain its own log location
 sed -i'' "s|jamf-im.log|jamf-im${domain}.log|g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im.xml"
 sed -i'' "s|jamf-im-launcher.log|jamf-im-launcher${domain}.log|g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im-launcher.xml"
 sed -i'' "s|jamf-im-pre-enroll.log|jamf-im-pre-enroll${domain}.log|g" "/etc/jamf-im${domain}/jsam/logging/log4j2-jamf-im-pre-enroll.xml"
 
### Create New Log files and set permissions
 touch /var/log/jamf-im${domain}.log
 touch /var/log/jamf-im-launcher${domain}.log
 touch /var/log/jamf-im-pre-enroll${domain}.log
 chgrp jamfservice /var/log/jamf-im*
 chmod 664 /var/log/jamf-im*
 
 
 
### Configure Log Rotation
 
 if [[ -f /etc/logrotate.conf ]]; then

# Back up existing /etc/logrotate.conf

cp /etc/logrotate.conf /etc/logrotate_conf_$(date +"%Y%m%d%H%M%S").bak

cat > /etc/logrotate.d/jamf-im${domain} <<JIMLogRotation
/var/log/jamf-im-launcher${domain}.log {
        missingok
        daily
        copytruncate
        create 700 jamfservice jamfservice
        dateext
        rotate 4
        compress
}
/var/log/jamf-im${domain}.log {
        missingok
        daily
        copytruncate
        create 700 jamfservice jamfservice
        dateext
        rotate 4
        compress
}
/var/log/jamf-im-pre-enroll${domain}.log {
        missingok
        daily
        copytruncate
        create 700 jamfservice jamfservice
        dateext
        rotate 4
        compress
}
JIMLogRotation

fi


#### STEP 4:
 #### Copy /usr/share files (this is the actual JIM program)
 ## Probably could have one shared copy of the .jar bundles and library but 
 # they're tiny, so we'll just keep it simple... 
 cp -R "${sourceDir}/usr/share/jamf-im" "/usr/share/jamf-im${domain}"
 # put a link to the main .sh script into bin for convenience. 
 ln -s "/usr/share/jamf-im${domain}/jamf-im.sh" "/bin/jamf-im${domain}"
# jamf-im.sh
 sed -i'' "s|jamf-im|jamf-im${domain}|g" "/usr/share/jamf-im${domain}/jamf-im.sh"
 sed -i'' "s|jamfservice\":|${JSAM_USER}\":|g" "/usr/share/jamf-im${domain}/jamf-im.sh"
# jamf-imd.sh
 sed -i'' "s|jamf-im|jamf-im${domain}|g" "/usr/share/jamf-im${domain}/jamf-imd.sh"
 # Put luncher log.xml back the way it was
 sed -i'' "s|log4j2-jamf-im${domain}-launcher|log4j2-jamf-im-launcher|" "/usr/share/jamf-im${domain}/jamf-imd.sh"
# jsam-enroll.sh
 sed -i'' "s|\/etc\/jamf-im|\/etc\/jamf-im${domain}|g" "/usr/share/jamf-im${domain}/jsam-enroll.sh"
 sed -i'' "s|\/share\/jamf-im|\/share\/jamf-im${domain}|g" "/usr/share/jamf-im${domain}/jsam-enroll.sh"
# jsam.sh
 sed -i'' "s|\/jamf-im|\/jamf-im${domain}|g" "/usr/share/jamf-im${domain}/jsam.sh"
 # That's the end of /usr/share.

#### STEP LAST:
 #### Replaces some functions of the installer RPM scripts ...
#### preinstall scriptlet
 getent group "${JSAM_USER_GROUP}" >/dev/null 2>&1 || groupadd --system "${JSAM_USER_GROUP}"
 id -u "${JSAM_USER}" >/dev/null 2>&1 || useradd -g "${JSAM_USER_GROUP}" --system --shell /sbin/nologin "${JSAM_USER}"
#### postinstall scriptlet
 # Make a dir for Felix Cache 
 mkdir -p "/var/lib/jamf-im${domain}/felix-cache" 2> /dev/null || true
 chown -R "$JSAM_USER_COLON_GROUP" "/var/lib/jamf-im${domain}/felix-cache" || exit $?
# Create a file for the Process log
 logfile="${logdir}/jamf-im.log"
 touch "${logfile}" || { echo "[err] Could not create process log file."; exit 1; }
 chown -R "root:${JSAM_USER_GROUP}" "${logfile}" || exit $?
 chmod 664 "${logfile}"
# Create a file for the Launch Log
 launchlogfile="${logdir}/jamf-im-launcher.log"
 touch "${launchlogfile}" || { echo "[err] Could not create launch log file."; exit 1; }
 chown -R "root:${JSAM_USER_GROUP}" "${launchlogfile}" || exit $?
 chmod 664 "${launchlogfile}"
# Set the permissions on the new jamf-im instance in /usr and /etc
 chown -R "$JSAM_USER_COLON_GROUP" "/usr/share/jamf-im${domain}/bundles" || exit $?
 chown -R "$JSAM_USER_COLON_GROUP" "/etc/jamf-im${domain}" || exit $?
done


# Copyright/Jamf
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons
# to whom the Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or
# substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
# PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
# FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.



