#!/bin/bash
#
FIC_TEMP=/tmp/repmgr_result_$$.tmp
#
sudo -u postgres repmgr -f /etc/repmgr.conf cluster show 2>/dev/null |col -b|tee -a $FIC_TEMP
#
NODE_PR=$(awk '$5=="primary" && NF==21 {print $5$7$8}' $FIC_TEMP)
NODE_SB=$(awk '$5=="standby" {print $3$5$7}' $FIC_TEMP)
#
if [ "$(hostname)standbyrunning" = "$NODE_SB" -a  "$NODE_PR" != "primary*running" ] ; then
  su - postgres -c "/usr/lib/postgresql/15/bin/repmgr standby promote -f /etc/repmgr.conf --log-to-file"
  sudo -u postgres repmgr -f /etc/repmgr.conf cluster show 2>/dev/null |col -b > $FIC_TEMP
  NODE_PR=$(awk -v host=$(hostname) '$3==host && NF==21 {print $5$7$8}' $FIC_TEMP)
  if [ "$(hostname)primary*running" = "$NODE_PR" ] ; then
    rm -rf  $FIC_TEMP ; exit 0
  else
    rm -rf  $FIC_TEMP ; exit 2
  fi
fi
#
NODE_PR=$(awk -v host=$(hostname) '$3==host && $5=="primary" && NF==21 {print $5$7$8}' $FIC_TEMP)
#
standby_run_as_primary=$(awk '$5=="standby" && $8=="running" && NF=23' $FIC_TEMP | wc -l)
#
if [ "$NODE_PR" = "primary*running" -a "$standby_run_as_primary" = 0 ] ; then
  rm -rf  $FIC_TEMP ; exit 0
else
  rm -rf  $FIC_TEMP ; exit 2
fi
