REP_PG="$HOME/adm/dba"
# Sigle ou acronyme de l'instance (3 lettres).
PSIG=$1
#Repertoire des transaction logs ( wal)  de l'instance
#REP_WAL=/pgwal
#
FIC_LOG=$REP_PG/log/pg_backup_pgwal_${PSIG:-Marg}$(date +'_le%d%m%Y').log
# Fichier journal temporaire.
LOG_TMP=$(dirname $FIC_LOG)/pg_wal_${PSIG:-Marg}$$$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
#Fichier des parametres concernes par le script save_rman_dbpostgres_drp.sh de toutes les bases sujet de la sauvegarde.
FIC_PAR=${REP_PG}/par/pg_save_instance_prd.psb
#
>$FIC_LOG
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut de la sauvegarde du fs ${REP_WAL} $(date +'le %d/%m/%Y a %H:%M:%S').
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#

# Controle de l'argument.
if [ $# -ne 1 ]; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le script necessite un seul argument l'acronyme de l'instance par exemple : ASC !
EOF_CAT
  exit 1
elif [ ! -f $FIC_PAR ] ; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le fichier des parametres inexistant !
  $FIC_PAR
EOF_CAT
  exit 1
elif ! /bin/egrep $PSIG $FIC_PAR >/dev/null 2>&1 ; then cat<<EOF_CAT | tee -a $FIC_LOG

- $PSIG est introuvable dans $FIC_PAR !
EOF_CAT
  exit 1
else cat<<EOF_CAT >>$FIC_LOG

- La liste des parametres de l'acronyme $PSIG est :

$(sed -n "/$PSIG {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$PSIG {/d;/}/d;/^#/d;/PWD/s/[a-z]/\*/g")
EOF_CAT
fi
# Recuperation des parametres pour l'instance  en question.
for PARAMS  in $(sed -n "/$PSIG {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$PSIG {/d;/}/d;/^#/d"); do
  export $PARAMS
done
#si l'instance en HA faut recuperer le serveur Pirmaire pour executer la sauvegarde
if expr "$(eval echo $PG_HA)" : "[yY]" >/dev/null
then
 if ! ssh -q -o "BatchMode=yes" $MACH_DEST ". \$HOME/.bash_profile; \$PGHOME/bin/repmgr -f /etc/repmgr.conf cluster show 2>/dev/null | awk -F '|'  '\$3 ~ \"primary\" {print \$2}' | tr -d ' ' " >$LOG_TMP
  then cat <<EOF_CAT | tee -a $FIC_LOG

- Probleme de recuperation du serveur Primaire de l'instance HA $PSIG !
EOF_CAT
exit 1;
 else
 MACH_DEST="$(cat $LOG_TMP)"
 rm -rf $LOG_TMP;
 fi
fi

#Verifier existence du repertoire de backup et de le creer s'il nexiste pas
REP_BCKP=$REP_BCKP/$(date +'%d-%m-%Y')
if ! ssh -q -o "BatchMode=yes" $MACH_DEST "if ! mkdir -p $REP_BCKP;then exit 1; else exit 0;fi"
  then cat <<EOF_CAT | tee -a $FIC_LOG

 --> Probleme de creation du Repertoire $REP_BCKP sur $MACH_DEST !!
EOF_CAT
    exit 1
elif ! ssh -q -o "BatchMode=yes" $MACH_DEST "[ -d $REP_BCKP  ]"
 then cat<<EOF_CAT | tee -a $FIC_LOG

 --> Repertoire $REP_BCKP inexistant sur $MACH_DEST !!
EOF_CAT
   exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

 --> Repertoire $REP_BCKP existe bien.
EOF_CAT
   fi

#fichier tar de sauvegarde
FIC_TAR=$REP_BCKP/backup_pgwal.tar.gz
#lance backup
#gerer le cas ou un fichier a ete modifie pendant la sauvegarde, c'est un warning a ignore et pourquivre la sauvegarde
#ssh -q -o "BatchMode=yes" $MACH_DEST "tar -czvf $FIC_TAR ${REP_WAL} --exclude \"lost+found\" --absolute-names" >${LOG_TMP} 2>&1
ssh -q -o "BatchMode=yes" $MACH_DEST "tar -czvf $FIC_TAR --exclude \"lost+found\" --absolute-names ${REP_WAL}" >${LOG_TMP} 2>&1
code_ret=$?
nb_warn=$(cat ${LOG_TMP} | egrep "fichier modifié pendant sa lecture|file changed as we read it" | wc -l)

if [ $code_ret -eq 1 -a $nb_warn -gt 0 ];
then  cat<<EOF_CAT | tee -a $FIC_LOG

- Commande de backup <tar> est execute avec un warning : <fichier modifié pendant sa lecture>
 |
 \`--> warning a ignore
EOF_CAT
code_ret=0
fi

if [ $code_ret -ne 0 ];
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de sauvegarde du fs ${REP_WAL} sur $MACH_DEST!
$(cat ${LOG_TMP}|paste -d " " - - -)
EOF_CAT
 rm -f ${LOG_TMP} ; exit 1
 fi
#
if ! cat<<EOF_CAT | tee -a $FIC_LOG

- Fin de la sauvegarde du fs ${REP_WAL} $(date +'le %d/%m/%Y a %H:%M:%S').
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#
exit 0
#


