Multi-instance Uninstaller....
#!/bin/bash
# Purpose: Remove multiple JIM instances supporting different domains

# User Settings:
# Enter a list of JIM instance names/numbers. There will be one instance of JIM per domain.
declare -a domain_a=('_mba' '_mbp');

rm -rf /var/log/jamf-im*.log
rm -rf ./jim
rm -rf /usr/share/jamf-im/

# ######################################################################## 
# If you are experimenting and need to undo this script...
# [!] snapshot before using rm -rF
# First, do a stop on each installed jim instance. E.g. "jamf-im_1 stop", etc.
for domain in domain_a; do
 # remove the service startup
 chkconfig --del "jamf-im${domain}"
 # remove autocomplete util
 rm -f "/etc/bash_completion.d/jamf-im"
 # remove init.d
 rm -f "/etc/init.d/jamf-im${domain}"
 # remove the symlink to the main script
 rm -f "/bin/jamf-im${domain}"
 # remove the jsam files
 rm -fR "/etc/jamf-im${domain}"
 # remove the jim java programs
 rm -fR "/usr/share/jamf-im${domain}"
 # remove the felix-cache
 rm -fR "/var/lib/jamf-im${domain}"
 # remove the log files
 rm -fR "/var/log/jamf-im${domain}"
 /usr/sbin/userdel "jamfservice${domain}"
 
 systemctl daemon-reload
done
/usr/sbin/groupdel "jamfservice"

## In the jss database (after making a backup)
## Clear out the JIMs
# TRUNCATE TABLE jsams; TRUNCATE TABLE jsam_invitations;
# --No longer needed -- you can delete from the GUI as of 9.98.
# ########################################################################
