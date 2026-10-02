Verif log postgres
#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom : pg15_verif_pglog.ksh
# Objectif : Verifier la presence erreurs dans les fichiers journaux postgresql.
# Interface : Aucun argument
#----------------------------------------------------------------------------------
# Adresse pour le(s) DBA(s).
LS_ADRS="adressmail"
#LS_ADRS=""
# Sous repertoire des fichiers journaux.
REP_PG="/home/postgres/adm/dba"
# Fichier journal du script.
FIC_LOG=${REP_PG}/log/pg15_verif_pglog$(date +'_le%d%m%Y').log
# Fichier journal tempo.
FIC_TEMP=${REP_PG}/tmp/pg15_verif_pglog_temp$(date +'_le%d%m%Y').log
# Recuperation des erreurs apres cette date.
DATE_VER="$(date --date "20 minutes ago" "+%Y-%m-%d %H:%M:%S")"
# Les diff. sous repertoires des fichiers journaux postgresql.
REP_PGLOG="/pglog/*.log /pginstance/log/*.log /pginstance/pg_log/*.log"
# Port par defaut postgresql.
PORT_PG=5432
# Fichiers contenant la liste des serveurs PostgreSQL.
list_servers_prod=${REP_PG}/par/list_servers_postgresql_production.txt
list_servers_val=${REP_PG}/par/list_servers_postgresql_validation.txt

# La liste des serveurs en PROD.
LS_SR_PG_PRD=$(awk '!/read/ && $1!~/^--/ {print $1}' $list_servers_prod)
# La liste des serveurs en VAL.
LS_SR_PG_VAL=$(awk '!/read/ && $1!~/^--/ {print $1}' $list_servers_val)
# La liste des serveurs en Read Only.
LS_SR_PG_REO=$(awk '/read/ && $1!~/^--/ {print $1}' $list_servers_val $list_servers_prod)

# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
#
find $(dirname $FIC_TEMP) -name "$(echo $(basename $FIC_TEMP .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
#
rm -f $FIC_LOG $FIC_TEMP
#
if ! /bin/cat<<EOF_CAT|tee -a $FIC_LOG
1. Debut de verification des fichiers journaux des serveurs PostgreSQL en VAL "$(date +'le %d/%m/%Y a %H:%M:%S')".
- Fichier journal disponible sur la machine $(hostname -a)
  |
  \`--> $FIC_LOG
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1
fi
# Envoyer un e-mail.
function E_MAIL
{ AttachFile=$FIC_LOG
  if ! (cat<<EOF_CAT
From: postgres@$(hostname -a).boursorama.fr
To: $LS_ADRS
Subject: [PG15]-Presence des erreurs fichiers journaux des serveurs PostgreSQL en VAL et PROD
Mime-Version: 1.0
content-type: multipart/related; boundary=xChaineLimtex
content-type: multipart/related; boundary=xChaineLimtex
--xChaineLimtex
Content-Type: text/plain
Content-Disposition: inline

Bonjour,

Pour analyser les erreurs des fichiers journaux des serveurs VAL et PROD PostgreSql voir fichier ci-joint.

Cordialement
  Equipe DBA
--xChaineLimtex
Content-Type: text/plain; name=$(basename $FIC_LOG)
Content-Disposition: attachment; filename=$(basename $FIC_LOG)

$(cat $AttachFile)
EOF_CAT
)|/usr/sbin/sendmail -t
  then cat<<EOF_CAT|tee -a $FIC_LOG

- Probleme de derouter un e-mail au(x) "$LS_ADRS" !

EOF_CAT
  else cat<<EOF_CAT|tee -a $FIC_LOG

- E-mail est OK pour $LS_ADRS.
EOF_CAT
#
  fi
#
}
# Pour numeroter les environnements.
PAR_SR=1
# Pour la gestion des erreurs.
OK_KO="OK"
# Verification du fichier journal postgresql dans le cas de la presence des erreurs.
function VERIF_PGLOG
{
# Pour numeroter les serveurs.
  NUM_SR=0
  for NOM_SR in $* ; do
    NUM_SR=$(($NUM_SR + 1))
# Fichier journal postgresql.
    FIC_PGLOG="$(/usr/bin/ssh -q $NOM_SR "ls -1t $REP_PGLOG 2>/dev/null|head -1 2>/dev/null")"
#
    if [ -z $FIC_PGLOG ] ; then /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

             (\_/)
            (_'.'_)
            (")+(")
               |
${PAR_SR}.${NUM_SR} Probleme de localiser le fichier journal du postgresql existant sur $NOM_SR !
EOF_CAT
      continue
    fi
# Verifier la presence du fichier journal postgresql.
    if /usr/bin/ssh -q -o "BatchMode=yes" $NOM_SR "if [ -f $FIC_PGLOG ] ; then exit 0 ; else exit 1 ; fi"
    then /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

${PAR_SR}.${NUM_SR} Recherche des erreurs generees apres $DATE_VER du fichier ci-dessous existant sur $NOM_SR :
  $FIC_PGLOG
EOF_CAT

# Verification de la date de modification du fichier journal postgresql.
      if [ $(/usr/bin/ssh -q -o "BatchMode=yes" $NOM_SR "expr \$(date +%s) - \$(/usr/bin/stat --format '%Y' $FIC_PGLOG) 2>/dev/null") -lt 1200 ]
      then
# Recherche des erreurs du fichier journal postgresql.
        /usr/bin/ssh -q -o "BatchMode=yes" $NOM_SR "awk '/LOG:/ && NR>=1{print substr(\$0,1,index(\$0,\"LOG:\")+3);exit;}' $FIC_PGLOG 2>/dev/null|awk '{print NF}'">$FIC_TEMP 2>&1
        if [ $(/bin/cat $FIC_TEMP 2>/dev/null) -ne 4 ] ; then /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

             (\_/)
            (_'.'_)
            (")+(")
               |
- Le fichier $FIC_PGLOG ne respecte pas :
  log_line_prefix = '%t:%r:%u@%d:[%p]: '
EOF_CAT
          continue
        fi
#
/usr/bin/ssh -q -o "BatchMode=yes" $NOM_SR "awk -v d_ver=\"$DATE_VER\" '\$0>d_ver && (\$4==\"FATAL:\"||\$4==\"ERROR:\") && \$0 !~/requested starting point.*history\$/' $FIC_PGLOG" >$FIC_TEMP 2>&1
#
        if [ -z $(/bin/grep '[^[:space:]]' $FIC_TEMP 2>/dev/null) ] ; then /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

- Aucune erreur detectee apres la date ${DATE_VER}.
EOF_CAT
          continue
        elif /bin/grep "^ssh:" $FIC_TEMP >/dev/null 2>&1 ; then OK_KO="KO" ; /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

- Probleme de rejoindre $NOM_SR en ssh !
$(/bin/cat $FIC_TEMP)
EOF_CAT
          continue
        else OK_KO="KO" ; /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

- Des erreurs localisees apres la date ${DATE_VER}.
$(head -1 $FIC_TEMP)
             (\_/)
            (_'.'_)
            (")+(")
               |
---------- Differents types d'erreurs : ----------
$(awk '{$1=$2=$3="";print $0}' $FIC_TEMP|sort -u|awk '{print NR". "$0}')
--------------------------------------------------
$(tail -1 $FIC_TEMP)
EOF_CAT
        fi
      elif /usr/bin/ssh -q -o "BatchMode=yes" $NOM_SR "if pg_isready -p $PORT_PG ; then exit 0 ; else exit 1 ; fi" >$FIC_TEMP 2>&1
      then /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

- L'acces au $FIC_PGLOG n'est pas assez recent $(/usr/bin/ssh -q -o "BatchMode=yes" $NOM_SR "/usr/bin/stat -c %x $FIC_PGLOG" 2>/dev/null) !
- Par contre le serveur $NOM_SR accepte les connexions normalement.
$(/bin/cat $FIC_TEMP)
EOF_CAT
        continue
      else OK_KO="KO" ; /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

             (\_/)
            (_'.'_)
            (")+(")
               |
- L'acces au $FIC_PGLOG n'est pas assez recent $(/usr/bin/ssh -q -o "BatchMode=yes" $NOM_SR "/usr/bin/stat -c %x $FIC_PGLOG" 2>/dev/null) !
- Et le serveur $NOM_SR n'accepte pas les connexions normalement.
$(/bin/cat $FIC_TEMP)
EOF_CAT
      fi
#
    else OK_KO="KO" ; /bin/cat<<EOF_CAT|/usr/bin/tee -a $FIC_LOG

             (\_/)
            (_'.'_)
            (")+(")
               |
${PAR_SR}.${NUM_SR} Probleme de localiser le fichier journal du postgresql existant sur $NOM_SR !
EOF_CAT
#
    fi
  done
#
  PAR_SR=$(($PAR_SR + 1))
}
# Analyse des fichiers journaux des serveurs en VAL.
VERIF_PGLOG $LS_SR_PG_VAL
#
if ! /bin/cat<<EOF_CAT|tee -a $FIC_LOG

2. Debut de verification des fichiers journaux des serveurs PostgreSQL en PROD "$(date +'le %d/%m/%Y a %H:%M:%S')".
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1
else
  VERIF_PGLOG $LS_SR_PG_PRD
fi
#
if ! /bin/cat<<EOF_CAT|tee -a $FIC_LOG

3. Debut de verification des fichiers journaux des serveurs PostgreSQL en Read-Only "$(date +'le %d/%m/%Y a %H:%M:%S')".
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1
else
  VERIF_PGLOG $LS_SR_PG_REO
fi
#
if [ "$OK_KO" = "KO" ] ; then /bin/cat<<EOF_CAT|tee -a $FIC_LOG

- Des erreurs trouvees voir ci-dessus pour analyser !

- Fin de verification des fichiers journaux des serveurs "$(date +'le %d/%m/%Y a %H:%M:%S')".
EOF_CAT
  E_MAIL ; exit 1
else /bin/cat<<EOF_CAT|tee -a $FIC_LOG

- Aucune erreur trouvee des fichiers journaux postgresql ci-dessus des serveurs.

- Fin de verification des fichiers journaux des serveurs "$(date +'le %d/%m/%Y a %H:%M:%S')".
EOF_CAT
  exit 0
fi
#
                   

--------------------------------------------------------------------pg15_verif_repmgrd.sh---------------------------------------------------------------------------------------
pg15_verif_repmgrd.sh

#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom :  pg15_verif_repmgrd.sh
# Date de creation : 12/03/2024
# Objectif : Verification du status de repmgrd
# Interface : Pas d'arguments
# Modification :
#
#----------------------------------------------------------------------------------
# Repertoire racine des scripts dba.
REP_PG="$HOME/adm/dba"
# Adresse pour le(s) DBA(s).
LS_ADRS="adresse_mail"
#LS_ADRS="mohammed.dablij@boursorama.fr"
# fichier log de script
FIC_LOG=$REP_PG/log/pg15_verif_repmgrd$(date +'_le%d%m%Y').log
# Fichier journal temporaire.
LOG_TEMP=$(dirname $FIC_LOG)/pg15_verif_repmgrd$$$(date +'_le%d%m%Y').log
# Fichier resultat temporaire
FIC_RES=$(dirname $FIC_LOG)/pg15_res_repmgrd$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
# Fichiers contenant la liste des serveurs PostgreSQL VAL et PROD.
LS_SERVERS_VAL=${REP_PG}/par/list_servers_postgresql_validation.txt
LS_SERVERS_PROD=${REP_PG}/par/list_servers_postgresql_production.txt
#
rm -f $FIC_LOG
#
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut de la verification du status de repmgrd des instances PostgreSQL en VAL/PROD $(date +'le %d/%m/%Y a %H:%M:%S').
   |
    - Fichier journal disponible sur la machine $(hostname)
   |
   \`--> $FIC_LOG
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#
function E_MAIL
{ AttachFile=$FIC_LOG
  if ! (cat<<EOF_CAT
From: postgres@$(hostname -a).boursorama.fr
To: $LS_ADRS
Subject: [$1] [PG15] - Verification du status du service repmgrd en $2
Mime-Version: 1.0
content-type: multipart/related; boundary=xChaineLimtex
--xChaineLimtex
Content-Type: text/plain
Content-Disposition: inline

Bonjour,

Pour le(s) probleme(s) ci-dessous voir fichier ci-joint :

$(awk '(/\- Probleme sur / && /\!$/)' $FIC_LOG)

Cordialement
  Equipe DBA
--xChaineLimtex
Content-Type: text/plain; name=$(basename $FIC_LOG)
Content-Disposition: attachment; filename=$(basename $FIC_LOG)

$(cat $AttachFile)
EOF_CAT
)|/usr/sbin/sendmail -t
  then cat<<EOF_CAT >>$FIC_LOG

- Probleme pour derouter un e-mail au $LS_ADRS !
EOF_CAT
    exit 1; else cat<<EOF_CAT >>$FIC_LOG

- E-mail est OK pour $LS_ADRS.
EOF_CAT
  fi
}
# Verifier l'etat de repmgr.
function VER_ETAT
{
  OK_KO="OK"
  N_SEC=0
  for NOM_SERV in $(awk '!/--/ {print $1}' $1 2>/dev/null); do
    N_SEC=$(($N_SEC + 1))
    IS_PB="NON"
    IS_LG_OK="OUI"
    rm -f $LOG_TEMP
    cat<<EOF_CAT | tee -a $LOG_TEMP

${N_SEC}$N_SSEC Serveur $NOM_SERV
EOF_CAT
#
    ssh -q -o "BatchMode=yes" $NOM_SERV "repmgr daemon status|awk -F\"|\" '/^ [1-2]/ && /not running/' 2>/dev/null" >$FIC_RES
#
    if [ "$(awk -v var=$NOM_SERV '$3==var {print $3}' $FIC_RES 2>/dev/null)" = "$NOM_SERV" ] ; then cat<<EOF_CAT| tee -a $LOG_TEMP

- Etat du status de repmgrd avant :
$(cat $FIC_RES)
EOF_CAT
# Demarrage du daemon.
      ssh -q -o "BatchMode=yes" $NOM_SERV "repmgr daemon start >/dev/null 2>&1"
      sleep 2
# Verification du status apres demarrage.
      ssh -q -o "BatchMode=yes" $NOM_SERV "repmgr daemon status|awk -F\"|\" '/^ [1-2]/ && /not running/' 2>/dev/null" >$FIC_RES
#
      if [ "$(awk -v var=$NOM_SERV '$3==var {print $3}' $FIC_RES 2>/dev/null)" = "$NOM_SERV" ] ; then cat<<EOF_CAT| tee -a $LOG_TEMP

- Probleme de demarrer daemon repmgrd !
- Etat du status de repmgrd apres :
$(cat $FIC_RES)
EOF_CAT
        IS_PB="OUI"
      else cat<<EOF_CAT | tee -a $LOG_TEMP

- Demarrage du daemon repmgrd est OK.
EOF_CAT
      fi
    else cat<<EOF_CAT| tee -a $LOG_TEMP
 |
  \`--> Le service repmgrd est OK.
EOF_CAT
    fi
#
    if [ "$IS_PB" == "OUI" ]; then cat<<EOF_CAT | tee -a $LOG_TEMP

- Probleme sur le serveur $NOM_SERV : voir paragraphe (${N_SEC}$N_SSEC) !
EOF_CAT
      OK_KO="KO"
    fi
    cat $LOG_TEMP >> $FIC_LOG
  done
#
  rm -rf $LOG_TEMP $FIC_RES
  if [ "$OK_KO" = "KO" ] ; then E_MAIL $OK_KO $2 ; fi
}
#
N_SSEC=".1"
#
VER_ETAT $LS_SERVERS_VAL VAL
#
N_SSEC=".2"
#
VER_ETAT $LS_SERVERS_PROD PROD
#
cat<<EOF_CAT | tee -a $FIC_LOG

- Fin de la verification du status de repmgrd des instances PostgreSQL en VAL/PROD $(date +'le %d/%m/%Y a %H:%M:%S').
EOF_CAT
#

------------------------------------------------------------------------verif_fs_pg_readonly.ksh------------------------------------------------------------------------------------------
#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom : verif_fs_pg_readonly.ksh
# Date de creation : 
# Auteur : 
# Objectif : Verifier la presence ou non des fs applicatifs en readonly.
# Interface : Aucun argument
# Modifications : DD/MM/YYYY
#
#----------------------------------------------------------------------------------
# Adresse pour le(s) DBA(s).
LS_ADRS="dedsdjjbhb"
#LS_ADRS=""
#
REP_LOG="/home/postgres/adm/dba/log"
# Fichier journal.
FIC_LOG=${REP_LOG}/verif_fs_pg_readonly$(date +'_le%d%m%Y').log
# Fichier journal tempo.
FIC_TEMP=${REP_LOG}/verif_fs_temp$(date +'_le%d%m%Y').log
# La liste des serveurs en PROD.
LS_SR_PG_PRD="pupglxtr001 pupglxtr002"
# La liste des serveurs en VAL.
LS_SR_PG_VAL="vupglxtr001 vupglxtr002"
# La liste des serveurs en Read Only.
LS_SR_PG_REO=""
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
#
find $(dirname $FIC_TEMP) -name "$(echo $(basename $FIC_TEMP .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
#
rm -f $FIC_LOG
# Pour la gestion des erreurs.
OK_KO="OK"
#
if ! /bin/cat<<EOF_CAT|tee -a $FIC_LOG
1. Debut de verification des fs applicatifs en readonly montes sur les serveurs en VAL $(date +'le %d/%m/%Y a %H:%M:%S')
- Fichier journal disponible sur la machine $(hostname -a)
  |
  \`--> $FIC_LOG
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1
fi
# Envoyer un e-mail.
function E_MAIL
{ AttachFile=$FIC_LOG
  if ! (cat<<EOF_CAT
From: postgres@$(hostname -a).boursorama.fr
To: $LS_ADRS
Subject: Presence des fs applicatifs en readonly VAL et PROD
Mime-Version: 1.0
content-type: multipart/related; boundary=xChaineLimtex
--xChaineLimtex
Content-Type: text/plain
Content-Disposition: inline

Bonjour

Pour analyser les fs montes en readonly sur les serveurs en VAL et PROD voir fichier ci-joint.

Cordialement

  Equipe DBA.
--xChaineLimtex
Content-Type: text/plain; name=$(basename $FIC_LOG)
Content-Disposition: attachment; filename=$(basename $FIC_LOG)

$(cat $AttachFile)
EOF_CAT
)|/usr/sbin/sendmail -t
  then cat<<EOF_CAT|tee -a $FIC_LOG

- Probleme de derouter un e-mail au(x) "$LS_ADRS" !

EOF_CAT
  else cat<<EOF_CAT|tee -a $FIC_LOG

- E-mail est OK pour $LS_ADRS.
EOF_CAT
#
  fi
#
}
#
function VERIF_FS
{ for NOM_SR in $* ; do
    if ! ssh -q -o "BatchMode=yes" $NOM_SR "awk 'NF==6 && \$4!~/^rw/ && !/tmpfs/' /proc/mounts" >$FIC_TEMP 2>&1
    then :
    fi
#
    if [ -z $(grep '[^[:space:]]' $FIC_TEMP 2>/dev/null) ] ; then cat<<EOF_CAT|tee -a $FIC_LOG
- Aucun fs applicatif en readonly monte sur $NOM_SR
EOF_CAT
    elif egrep "^ssh:" $FIC_TEMP >/dev/null 2>&1
    then cat<<EOF_CAT|tee -a $FIC_LOG

              (\_/)
             (_'.'_)
             (")+(")
                |
- Probleme de rejoindre $NOM_SR !
$(cat $FIC_TEMP)
EOF_CAT
      OK_KO="KO"
    else cat<<EOF_CAT|tee -a $FIC_LOG
              (\_/)
             (_'.'_)
             (")+(")
                |
- Presence de(s) fs en readonly monte sur $NOM_SR !
$(cat $FIC_TEMP)
EOF_CAT
      OK_KO="KO"
    fi
#
  done
#
}
# La liste des serveurs en VAL.
VERIF_FS $LS_SR_PG_VAL
#
if ! /bin/cat<<EOF_CAT|tee -a $FIC_LOG

2. Debut de verification des fs applicatifs en readonly montes sur les serveurs en PROD $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1
fi
# La liste des serveurs en PROD.
VERIF_FS $LS_SR_PG_PRD
#
if ! /bin/cat<<EOF_CAT|tee -a $FIC_LOG

3. Debut de verification des fs applicatifs en readonly des serveurs en Read Only PROD et VAL $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1
fi
# La liste des serveurs en Read Only.
VERIF_FS $LS_SR_PG_REO
#
if [ "$OK_KO" = "KO" ] ; then /bin/cat<<EOF_CAT|tee -a $FIC_LOG

- Des fs applicatifs en readonly sur certains serveurs voir ci-dessus pour analyser !

- Fin   de verification des fs applicatifs en readonly montes sur les serveurs en VAL et PROD $(date +'le %d/%m/%Y a %H:%M:%S')

EOF_CAT
  E_MAIL ; exit 1
else /bin/cat<<EOF_CAT|tee -a $FIC_LOG

- Aucun fs applicatif en readonly monte sur les serveurs en VAL et PROD.

- Fin   de verification des fs applicatifs en readonly montes sur les serveurs en VAL et PROD $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
  exit 0
fi
#


------------------------------------------------------------------------------pg_backup_archives.sh-------------------------------------------------------------------------------------------
#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom : pg_backup_archives.sh
# Date de creation : 08/09/2020
# Objectif : Sauvegarde des archives  d'une instance postgresql
# Interface : Un argument l'acronyme de l'instance  (3 lettres par exemple ASC )
# Modification : 17/09/2020
#
#----------------------------------------------------------------------------------
# Sous repertoire racine des diff. fichiers.
REP_PG="$HOME/adm/dba"
# Sigle ou acronyme de l'instance (3 lettres).
PSIG=$1
# Fichier journal du script.
FIC_LOG=${REP_PG}/log/pg_backup_archives_${PSIG:-Marg}$(date +'_le%d%m%Y').log
#Repertoire des fichiers archives  de l'instance
#REP_ARC=/pgarchive
# Fichier journal temporaire.
LOG_TMP=$(dirname $FIC_LOG)/save_pg_${PSIG:-Marg}$$$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
# Fichier des parametres concernes par le script save_rman_dbpostgres_drp.sh de toutes les bases sujet de la sauvegarde.
FIC_PAR=${REP_PG}/par/pg_save_instance_prd.psb
#label de la sauevagrde
flag="backup"$(date +'_%d%m%Y')

>$FIC_LOG
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut de la sauvegarde des archives existants sur le fs ci-dessous $(date +'le %d/%m/%Y a %H:%M:%S') :
  $REP_ARC
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

- La liste des parametres de l'acronyme $PSIG de la base est :

$(sed -n "/$PSIG {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$PSIG {/d;/}/d;/^#/d;/PWD/s/[a-z]/\*/g")
EOF_CAT
fi
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

#Verifier l'etat de l'instance a suavegardé
#POSTGRES_IS_RUNNING=$(export PGPASSWORD=${PG_PWD}; psql --host=${MACH_DEST} --port=${PORT} --user=${PG_USER} --dbname=postgres --quiet --tuples-only --no-psqlrc --command "SELECT 1;" 2>/dev/null)
POSTGRES_IS_RUNNING=$(sudo docker exec -i -e PGPASSWORD=$PG_PWD pgl bash -c "psql -h $MACH_DEST -p $PORT -U $PG_USER -d postgres -q -t -X -c \"SELECT 1;\" 2>/dev/null")
#
if [[ ${POSTGRES_IS_RUNNING} -ne 1 ]];
 then cat<<EOF_CAT | tee -a $FIC_LOG

 - L'instance n'est pas démarrer sur la machne ${MACH_DEST} ...
EOF_CAT
    exit 1
fi
#si l'instance est en mode recovery on fait pas de sauevagarde.
#INSTANCE_STATUS=$(export PGPASSWORD=${PG_PWD}; psql --host=${MACH_DEST} --port=${PORT} --user=${PG_USER} --dbname=postgres --quiet --tuples-only --no-psqlrc --command="SELECT CASE pg_is_in_recovery() WHEN true THEN 'IN RECOVERY' ELSE 'OPEN' END;" 2>/dev/null)
INSTANCE_STATUS=$(sudo docker exec -i -e PGPASSWORD=$PG_PWD pgl bash -c "psql -h $MACH_DEST -p $PORT -U $PG_USER -d postgres -q -t -X -c \"SELECT CASE pg_is_in_recovery() WHEN true THEN 'IN RECOVERY' ELSE 'OPEN' END;\" 2>/dev/null")
#
if [ "${INSTANCE_STATUS}" != " OPEN" ];
then cat<<EOF_CAT | tee -a $FIC_LOG

  - L'instance est en Mode RECOVERY , pas de sauevagarde a effectuee!
EOF_CAT
    exit 1;
fi

#
if ! ssh -q -o "BatchMode=yes" $MACH_DEST ". \$HOME/.bash_profile; \$PGHOME/bin/psql<<EOF_PSQL
\set ON_ERROR_STOP ON
SELECT pg_switch_wal();
EOF_PSQL" >>$LOG_TMP 2>&1
   then cat<<EOF_CAT | tee -a $FIC_LOG

 - Probleme de basculer vers le prochain journal de transactions !
$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP ; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Archivage du journal courant est OK

$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP
fi
#


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
FIC_TAR=$REP_BCKP/backup_pgarchive.tar.gz

#recuprer le dernier archive
FIC_ARC="$(ssh -q -o "BatchMode=yes" $MACH_DEST "ps -fupostgres|awk '\$0 ~/postgres\: archiver/{print \$NF}' 2>/dev/null")"

#
if [ -z "$FIC_ARC" ] ; then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de localiser le dernier fichier archive (Absence du processus : postgres: archiver) !
----------------------------------- Liste actuelle des processus postgres ------------------------------

$(ssh -q -o "BatchMode=yes" $MACH_DEST  "ps -fupostgres|awk '\$9 ~/logger|checkpointer|background|stats|walwriter|autovacuum|archiver|logical/' 2>/dev/null")

--------------------------------------------------------------------------------------------------------
EOF_CAT
  exit 1
fi
#
#

#sauvegarde les archives
#if ! ssh -q -o "BatchMode=yes" $MACH_DEST "tar -czvf $FIC_TAR \$(/usr/bin/find ${REP_ARC} -type f ! -newer ${REP_ARC}/${FIC_ARC} ! -name "*.done") --exclude \"lost+found\" --absolute-names" >${LOG_TMP} 2>&1
#ssh -q -o "BatchMode=yes" $MACH_DEST "tar -czvf $FIC_TAR \$(/usr/bin/find ${REP_ARC} -type f ! -newer ${REP_ARC}/${FIC_ARC} ! -name "*.done") --exclude \"lost+found\" --absolute-names" >${LOG_TMP} 2>&1

ssh -q -o "BatchMode=yes" $MACH_DEST "tar -czvf $FIC_TAR --exclude \"lost+found\" --absolute-names \$(/usr/bin/find ${REP_ARC} -type f ! -newer ${REP_ARC}/${FIC_ARC} ! -name "*.done")" >${LOG_TMP} 2>&1
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

- Probleme de sauvegarde des archives
$(cat ${LOG_TMP}|paste -d " " - - -)
EOF_CAT
 rm -f ${LOG_TMP} ; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Sauvegarde du fs ${REP_ARC} est OK, et ci-dessous le contenu du $FIC_TAR :
--------------------------------------------------------------------------------------------------------
$(cat ${LOG_TMP}|paste -d " " - - -)
--------------------------------------------------------------------------------------------------------
EOF_CAT
 rm -f ${LOG_TMP}
fi

#lancer un cleanup des archives apres backup
ssh -q -o "BatchMode=yes" $MACH_DEST ". \$HOME/.bash_profile; \$PGHOME/bin/pg_archivecleanup -d $REP_ARC ${FIC_ARC}" | tee -a $FIC_LOG

if ! cat<<EOF_CAT | tee -a $FIC_LOG

- Fin   de la sauvegarde des archives existants sur le fs ci-dessous $(date +'le %d/%m/%Y a %H:%M:%S') :
  $REP_ARC
EOF_CAT
then echo "- Probleme au niveau d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi
#





----------------------------------------------------------------------------pg_clone_instance_val.sh----------------------------------------------------------------------------------------------------------------------------

#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom : pg_clone_instance_val.sh
# Date de creation : 
# Auteurs :
# Objectif : Clonage d'une instance postgresql via l'emplacement de sauvegarde
# Interface : Un argument :
#               - L'alias de la base PostgreSQL clone en question
#                  l'alias fait reference a la base PostgreSQL dans fichier de parametre : pg_param_clone_instance_val.psb
# Date de Modification : 04/02/2021
#
#----------------------------------------------------------------------------------
# Sous repertoire racine des diff. fichiers.
REP_PG="$HOME/adm/dba"
# L'alias de la base PostgreSQL clone en question
PG_ALIAS=$1
# Fichier journal du script.
FIC_LOG=${REP_PG}/log/pg_clone_instance_val_${PG_ALIAS:-Marg}$(date +'_le%d%m%Y').log
# Fichier journal temporaire.
LOG_TMP=$(dirname $FIC_LOG)/clone_pg_${PG_ALIAS:-Marg}$$$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
# Fichier des parametres concernes par le script save_rman_dbpostgres_drp.sh de toutes les bases sujet de la sauvegarde.
FIC_PAR=${REP_PG}/par/pg_param_clone_instance_val.psb
#
>$FIC_LOG
#
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut de clonage de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S').
  |
  \`--> L'argument l'alias de la base est :  ${PG_ALIAS:-Marg}
  - Fichier journal disponible sur la machine $(hostname)
  |
  \`--> $FIC_LOG
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#

# Controle de l'argument.
if [ $# -ne 1 ]; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le script necessite un seul argument : l'alias de la base PostgreSQL clone en question !
EOF_CAT
  exit 1
elif [ ! -f $FIC_PAR ] ; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le fichier des parametres inexistant !
  $FIC_PAR
EOF_CAT
  exit 1
elif ! /bin/egrep $PG_ALIAS $FIC_PAR >/dev/null 2>&1 ; then cat<<EOF_CAT | tee -a $FIC_LOG

- $PG_ALIAS est introuvable dans $FIC_PAR !
EOF_CAT
  exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Les parametres pour l'argument $PG_ALIAS sont  :

$(sed -n "/\<$PG_ALIAS\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$PG_ALIAS {/d;/}/d;/^#/d;/PWD/s/[a-z]/\*/g")
EOF_CAT
fi

# Recuperation des parametres pour l'instance  en question.
for PARAMS  in $(sed -n "/\<$PG_ALIAS\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$PG_ALIAS {/d;/}/d;/^#/d"); do
  export $PARAMS
done

# identification des nodes de cluster
MACH_DEST_PRIMARY=$MACH_DEST
MACH_DEST_SECONDARY=$(echo $MACH_DEST | sed 's/.$/2/')

#verfier l'existance de repertoire de backup
if !  ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "[ -d $REP_BACK ]"
then cat<<EOF_CAT | tee -a $FIC_LOG

- Repertoire d'hebergement des fichiers de la sauvegarde est inexistant !
  |
  \`--> $REP_BACK
EOF_CAT
  exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Repertoire d'hebergement des fichiers de la sauvegarde existe :
  |
  \`--> $REP_BACK
EOF_CAT
fi

#recuperation du dernier backup
if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "ls -td ${REP_BACK}/* | grep -v ARCHIVES | head -n 1"  >$LOG_TMP  2>&1
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de recuperation du dernier backup de l'instance $PSIG.
$(cat $LOG_TMP)
EOF_CAT
rm -f $LOG_TMP ; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Recuperation du dernier backup de l'instance $PSIG ok.
  |
  \`--> $(cat $LOG_TMP)
EOF_CAT
back=$(cat $LOG_TMP)
fi
#back=$(ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "ls -td ${REP_BACK}/* | head -n 1")
#echo "back="$back
#exit 0;

#S'assurer que l'instance primaire est bien arrete avant clonage
check_pg=$(ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "ps -fupostgres|awk '\$9 ~/logger|checkpointer|background|stats|walwriter|autovacuum|archiver|logical/' | wc -l" 2>/dev/null)

if [[ ${check_pg} -ge 4 ]];
  then
 if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY ". \$HOME/.bash_profile; /usr/bin/sudo systemctl stop postgres" >$LOG_TMP 2>&1
  then cat<<EOF_CAT | tee -a $FIC_LOG
- Probleme d'arret de l'instance sur la machine $MACH_DEST_PRIMARY.

$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP ; exit 1
 else cat<<EOF_CAT | tee -a $FIC_LOG

- Arret de l'instance sur $MACH_DEST_PRIMARY est OK.

$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP
 fi
else cat<<EOF_CAT | tee -a $FIC_LOG

- L'instance sur $MACH_DEST_PRIMARY est deja arrete.
EOF_CAT
fi

#Nettoyage des fichiers de l'instance avant clonage
if expr "$(eval echo $SUP_FSDB)" : "[yY]" >/dev/null
 then
# if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY  "for rep in \$(ls -d /pg*) ;do find \$rep -mindepth 1 -user postgres 2>/dev/null -delete; done"
 if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY  "find /pg* -maxdepth 1 -mindepth 1 -user postgres 2>/dev/null -exec rm -rf {} \;"
 then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de suppression des fichiers existants dans les repertoires /pg* de l'instance sur la machine $MACH_DEST_PRIMARY !
EOF_CAT
    exit 1
  else cat<<EOF_CAT | tee -a $FIC_LOG

- Suppression des fichiers existants dans les repertoires /pg* de l'instance sur la machine $MACH_DEST_PRIMARY est effectues.
EOF_CAT
  fi
else cat<<EOF_CAT | tee -a $FIC_LOG

- Le parametre de la suppression des fichiers de l'instance avant clonage est $SUP_FSDB.
EOF_CAT
fi
#exit 0

#clonage de l'instance
if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "for fl in \$(find $back -type f) ;do tar zxvf \$fl -C /; done;" >$LOG_TMP 2>&1
  then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de clonage de l'instance, plus de details ci-dessous :

$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP ; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Clonage de l'instance PostgreSQL sur la machine $MACH_DEST_PRIMARY est effectues :

$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP
fi
#Restauration des fichiers de config deja sauevagrder dans ${REP_EXP_CFG}
if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "cp -p ${REP_EXP_CFG}/pg_hba.conf_${MACH_DEST} $REP_INST/pg_hba.conf; cp -p ${REP_EXP_CFG}/postgresql.conf_${MACH_DEST} $REP_INST/postgresql.conf" >$LOG_TMP 2>&1
   then cat <<EOF_CAT | tee -a $FIC_LOG

- Probleme de restauration des fichiers : pg_hba.conf et postgresql.conf.

$(cat $LOG_TMP)
EOF_CAT
  rm -rf $LOG_TMP;  exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Restauration des fichiers : pg_hba.conf et postgresql.conf est OK.
EOF_CAT
fi

sleep 20
#Demarrage de l'instance
if ! ssh -q -o "BatchMode=yes" -t -t $MACH_DEST_PRIMARY ". \$HOME/.bash_profile; /usr/bin/sudo systemctl start postgres" >$LOG_TMP 2>/dev/null
  then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de demarrage de l'instance sur la machine $MACH_DEST_PRIMARY.
$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP ; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Demarrage de l'instance sur $MACH_DEST_PRIMARY est OK.

$(cat $LOG_TMP)
EOF_CAT
  rm -f $LOG_TMP
fi

if ! cat<<EOF_CAT | tee -a $FIC_LOG

- Fin du clonage de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi
#
                 











----------------------------------------------------------------------pg_import_config_val.sh-------------------------------------------------------------------------------------------------------











#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom : pg_import_config_val.sh
# Date de creation : 03/02/2021
# Auteurs : lahcen BOUDAOUDI
# Objectif :  Import  tables et fichiers de config d'une instance postgresql
# Interface : Un argument :
#               - L'alias de la base PostgreSQL clone en question
#                  l'alias fait reference a la base PostgreSQL dans fichier de parametre : pg_param_clone_instance_val.psb
# Date de Modification : 04/02/2021
#
#----------------------------------------------------------------------------------
# Sous repertoire racine des diff. fichiers.
REP_PG="$HOME/adm/dba"
# L'alias de la base PostgreSQL clone en question
PG_ALIAS=$1
# Fichier journal du script.
FIC_LOG=${REP_PG}/log/pg_import_config_val_${PG_ALIAS:-Marg}$(date +'_le%d%m%Y').log
# Fichier journal temporaire.
LOG_TMP=$(dirname $FIC_LOG)/import_pg_${PG_ALIAS:-Marg}$$$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
# Fichier des parametres concernes par le script save_rman_dbpostgres_drp.sh de toutes les bases sujet de la sauvegarde.
FIC_PAR=${REP_PG}/par/pg_param_clone_instance_val.psb

>$FIC_LOG
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut d'import de la configuration de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S').
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#

# Controle de l'argument.
if [ $# -ne 1 ]; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le script necessite un seul argument le nom de la base en question !
EOF_CAT
  exit 1
elif [ ! -f $FIC_PAR ] ; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le fichier des parametres inexistant !
  $FIC_PAR
EOF_CAT
  exit 1
elif ! /bin/egrep -w $PG_ALIAS $FIC_PAR >/dev/null 2>&1 ; then cat<<EOF_CAT | tee -a $FIC_LOG

- $PG_ALIAS est introuvable dans $FIC_PAR !
EOF_CAT
  exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- La liste des parametres de la base $PG_ALIAS est :

$(sed -n "/\<$PG_ALIAS\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$PG_ALIAS {/d;/}/d;/^#/d;/PWD/s/[a-z]/\*/g")
EOF_CAT
fi

# Recuperation des parametres pour l'instance  en question.
for PARAMS  in $(sed -n "/\<$PG_ALIAS\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$PG_ALIAS {/d;/}/d;/^#/d"); do
  export $PARAMS
done

# identification des nodes de cluster
MACH_DEST_PRIMARY=$MACH_DEST
MACH_DEST_SECONDARY=$(echo $MACH_DEST | sed 's/.$/2/')

# Import ou non des tables de config. avant le clonage.
if ! expr "$(eval echo $IMPORT_ON)" : "[yY]" >/dev/null
then cat<<EOF_CAT | tee -a $FIC_LOG

- L'import des fichiers et tables de config. avant clonage est ignore (IMPORT_ON=$IMPORT_ON).

- Fin d'import de la configuration de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
  exit 0
else cat<<EOF_CAT | tee -a $FIC_LOG

- L'import des fichiers et tables de config. avant clonage est demande (IMPORT_ON=$IMPORT_ON).
EOF_CAT
fi


#Lance import des tables de config
if [ -z "$LS_TAB" ];
  then cat <<EOF_CAT | tee -a $FIC_LOG

- Pas de tables de configuration applicatives a importees.
EOF_CAT
  else

    #Truncate tables de config avant import, bocle si on a plusieurs tables de config
    for table in $( echo $LS_TAB | sed -e "s/,/ /g")
     do
      if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY ". \$HOME/.bash_profile;psql --port=${PORT} --user=${PG_USER} --dbname=$DB_NAME -c 'truncate table $table;'">$LOG_TMP 2>&1
    then cat <<EOF_CAT | tee -a $FIC_LOG

 +> Probleme de truncate de la table : $table

$(cat $LOG_TMP)
EOF_CAT
        rm -rf $LOG_TMP; exit 1
      else cat<<EOF_CAT | tee -a $FIC_LOG

 +> Trucate de la table $table OK.

$(cat $LOG_TMP)
EOF_CAT
        rm -rf $LOG_TMP
      fi
    done

  #Lancer l'import des tables de config
  if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY ". \$HOME/.bash_profile;psql --port=${PORT} --user=${PG_USER} --dbname=$DB_NAME < ${REP_EXP_CFG}/dump_config_${DB_NAME}_${MACH_DEST}.sql">$LOG_TMP 2>&1
    then cat <<EOF_CAT | tee -a $FIC_LOG

- Probleme d'import des tables de configuration $LS_TAB.

$(cat $LOG_TMP)
EOF_CAT
     rm -rf $LOG_TMP; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Import des tables de configuration : $LS_TAB est OK.

$(cat $LOG_TMP)
EOF_CAT
   rm -rf $LOG_TMP
   fi

 fi

#Restauration des fichiers de config deja sauevagrder dans ${REP_EXP_CFG}
#if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "cp -p ${REP_EXP_CFG}/pg_hba.conf_${MACH_DEST_PRIMARY} $REP_INST/pg_hba.conf; cp -p ${REP_EXP_CFG}/postgresql.conf_${MACH_DEST_PRIMARY} $REP_INST/postgresql.conf" >$LOG_TMP 2>&1
#   then cat <<EOF_CAT | tee -a $FIC_LOG
#
#- Probleme de restauration des fichiers : pg_hba.conf et postgresql.conf.
#
#$(cat $LOG_TMP)
#EOF_CAT
#  rm -rf $LOG_TMP;  exit 1
#else cat<<EOF_CAT | tee -a $FIC_LOG
#
#- Restauration des fichiers : pg_hba.conf et postgresql.conf est OK.
#EOF_CAT
#   fi

#Restauration des roles + grant
#if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY ". \$HOME/.bash_profile;egrep -v "^CREATE" ${REP_EXP_CFG}/roles_${DB_NAME}_${MACH_DEST}.sql | psql --port=${PORT} --user=${PG_USER} --dbname=postgres -1" >$LOG_TMP 2>&1
if ! ssh -q -o "BatchMode=yes" $MACH_DEST ". \$HOME/.bash_profile; psql -v ON_ERROR_STOP=1 --port=${PORT} --user=${PG_USER} --dbname=postgres -f ${REP_EXP_CFG}/roles_${DB_NAME}_${MACH_DEST}.sql " >$LOG_TMP 2>&1
 then cat <<EOF_CAT | tee -a $FIC_LOG

- Probleme de restauration des roles et grant apres clonage !!
----------------------------
 $(cat $LOG_TMP)
----------------------------
EOF_CAT
   rm -rf $LOG_TMP; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Restauration des roles et grant apres clonage OK.
-------------------------------
$(cat $LOG_TMP)
-------------------------------
EOF_CAT
   rm -rf $LOG_TMP
fi

if ! cat<<EOF_CAT | tee -a $FIC_LOG

- Fin d'import de la configuration de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi












--------------------------------------------------------------------------pg_export_config_val.sh-----------------------------------------------------------------------------------------------------------














#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom : pg_export_config_val.sh
# Date de creation : 03/02/2021
# Objectif :  Export tables et fichier de config d'une instance postgresql
# Interface : Un argument :
#                - L'alias de la base PostgreSQL clone en question
#                  l'alias fait reference a la base PostgreSQL dans fichier de parametre : pg_param_clone_instance_val.psb
# Date de Modification : 04/02/2021
#
#----------------------------------------------------------------------------------
# Sous repertoire racine des diff. fichiers.
REP_PG="$HOME/adm/dba"
#PG_ALIAS=$(echo $1 | tr '[:upper:]' '[:lower:]')
# L'alias de la base PostgreSQL clone en question
PG_ALIAS=$1
# Fichier journal du script.
FIC_LOG=${REP_PG}/log/pg_export_config_val_${PG_ALIAS:-Marg}$(date +'_le%d%m%Y').log
# Fichier journal temporaire.
LOG_TMP=$(dirname $FIC_LOG)/export_pg_${PG_ALIAS:-Marg}$$$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
# Fichier des parametres concernes par le script save_rman_dbpostgres_drp.sh de toutes les bases sujet de la sauvegarde.
FIC_PAR=${REP_PG}/par/pg_param_clone_instance_val.psb

>$FIC_LOG
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut d'export de la config de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S').
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#

# Controle de l'argument.
if [ $# -ne 1 ]; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le script necessite un seul argument l'alias de la base PostgreSQL clone en question !
EOF_CAT
exit 1
fi

# Recuperation des parametres pour l'instance  en question.
if ! ${REP_PG}/sh/generate_params_clone_postgresql.sh $PG_ALIAS
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme lors de recuperation des parametres par le script shell generate_params_clone_postgresql.sh !!
EOF_CAT
  exit 1
else source ${REP_PG}/par/source_param_clone_postgresql_${PG_ALIAS}.sh
cat<<EOF_CAT | tee -a $FIC_LOG

- Les parametres pour l'alias $PG_ALIAS sont :
$(sed '/PG_PWD/s/[a-z]/\*/g' ${REP_PG}/par/source_param_clone_postgresql_${PG_ALIAS}.sh)
EOF_CAT
fi

# Export ou non des tables de config. avant le clonage.
if ! expr "$(eval echo $EXPORT_ON)" : "[yY]" >/dev/null
then cat<<EOF_CAT | tee -a $FIC_LOG

- L'export des fichiers et tables de config. avant clonage est ignore (EXPORT_ON=$EXPORT_ON).

- Fin d'export de la configuration de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
  exit 0
else cat<<EOF_CAT | tee -a $FIC_LOG

- L'export des fichiers et tables de config. avant clonage est demande (EXPORT_ON=$EXPORT_ON).
EOF_CAT
fi

#Creation de repertoire d'hebergement des fichiers de config + tables de config avant clonage, s'il n'existe pas
if !  ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "[ -d $REP_EXP_CFG ]"
then cat<<EOF_CAT | tee -a $FIC_LOG

- Repertoire ${REP_EXP_CFG} inaccessible sur ${MACH_DEST_PRIMARY} !
EOF_CAT
  exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Repertoire ${REP_EXP_CFG} est bien accessible sur $MACH_DEST_PRIMARY .
EOF_CAT
fi


# Sauvegarde de fichier de config avant clonage
if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY "cp $REP_INST/pg_hba.conf $REP_EXP_CFG/pg_hba.conf_${MACH_DEST};cp $REP_INST/postgresql.conf ${REP_EXP_CFG}/postgresql.conf_${MACH_DEST}" >$LOG_TMP 2>&1
   then cat <<EOF_CAT | tee -a $FIC_LOG

- Probleme de sauvegade des fichiers : pg_hba.conf et postgresql.conf !!

$(cat $LOG_TMP)
EOF_CAT
  rm -rf $LOG_TMP;  exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Sauvegarde des fichiers pg_hba.conf et postgresql.conf avant clonage est OK.
EOF_CAT
   fi


if [ -z "$LS_TAB" ];
 then cat <<EOF_CAT | tee -a $FIC_LOG

- Pas de tables de configuration applicatives a exportees.
EOF_CAT
else

   #Lance Export des tables de config, la bocle s'il y en plusieurs
   for i in $( echo $LS_TAB | sed -e "s/,/ /g")
    do
      TAB=$TAB" -t $i"
    done

   if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY ". \$HOME/.bash_profile;export PGPASSWORD=${PG_PWD};pg_dump --data-only --port=${PORT} --user=${PG_USER} --dbname=$DB_NAME $TAB -f ${REP_EXP_CFG}/dump_config_${DB_NAME}_${MACH_DEST}.sql">$LOG_TMP 2>&1

    then cat <<EOF_CAT | tee -a $FIC_LOG

- Probleme de sauvegarde des tables de configuration : $LS_TAB
 $(cat $LOG_TMP)
EOF_CAT
      rm -rf $LOG_TMP; exit 1
    else cat<<EOF_CAT | tee -a $FIC_LOG

- Sauvegarde des tables de configuration est OK.
  |
  \-> ${REP_EXP_CFG}/dump_config_${DB_NAME}_${MACH_DEST}.sql
EOF_CAT
      rm -rf $LOG_TMP
    fi

fi


#Sauvegarder les roles avant clonage pour les importer apres
#if ! ssh -q -o "BatchMode=yes" $MACH_DEST_PRIMARY ". \$HOME/.bash_profile;export PGPASSWORD=${PG_PWD};pg_dumpall --port=${PORT} --user=${PG_USER} --roles-only --file=${REP_EXP_CFG}/roles_${DB_NAME}_${MACH_DEST}.sql"  >$LOG_TMP 2>&1
if ! ssh -q -o "BatchMode=yes" $MACH_DEST ". \$HOME/.bash_profile; \$PGHOME/bin/psql -tA -v ON_ERROR_STOP=1 <<EOF_PSQL
\o ${REP_EXP_CFG}/roles_${DB_NAME}_${MACH_DEST}.sql
SELECT  '
DO
$(echo '$(echo ''\$do$'')')
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE  rolname = '''||rolname||''')
        THEN
      CREATE ROLE '||rolname||';
          ALTER ROLE '||rolname||' WITH '||(CASE WHEN rolsuper='t' THEN 'SUPERUSER' ELSE 'NOSUPERUSER' END) ||' '||(CASE WHEN rolinherit='t' THEN 'INHERIT' ELSE 'NOINHERIT' END) ||' '||(CASE WHEN rolcreaterole='t' THEN 'CREATEROLE' ELSE 'NOCREATEROLE' END) ||' '||(CASE WHEN rolcreatedb='t' THEN 'CREATEDB' ELSE 'NOCREATEDB' END) ||' '||(CASE WHEN rolcanlogin='t' THEN 'LOGIN' ELSE 'NOLOGIN' END) ||' '||(CASE WHEN rolreplication='t' THEN 'REPLICATION' ELSE 'NOREPLICATION' END) ||' '||(CASE WHEN rolbypassrls='t' THEN 'BYPASSRLS' ELSE 'NOBYPASSRLS' END) ||' '||(CASE WHEN rolpassword is not null THEN 'PASSWORD '''||rolpassword||'''' ELSE '' END) ||';
      RAISE INFO ''ROLE '||rolname||' CREATED AND ALTERED'';
        ELSE
          ALTER ROLE '||rolname||' WITH '||(CASE WHEN rolsuper='t' THEN 'SUPERUSER' ELSE 'NOSUPERUSER' END) ||' '||(CASE WHEN rolinherit='t' THEN 'INHERIT' ELSE 'NOINHERIT' END) ||' '||(CASE WHEN rolcreaterole='t' THEN 'CREATEROLE' ELSE 'NOCREATEROLE' END) ||' '||(CASE WHEN rolcreatedb='t' THEN 'CREATEDB' ELSE 'NOCREATEDB' END) ||' '||(CASE WHEN rolcanlogin='t' THEN 'LOGIN' ELSE 'NOLOGIN' END) ||' '||(CASE WHEN rolreplication='t' THEN 'REPLICATION' ELSE 'NOREPLICATION' END) ||' '||(CASE WHEN rolbypassrls='t' THEN 'BYPASSRLS' ELSE 'NOBYPASSRLS' END) ||' '||(CASE WHEN rolpassword is not null THEN 'PASSWORD '''||rolpassword||'''' ELSE '' END) ||';
      RAISE INFO ''ROLE '||rolname||' ALTERED'';
   END IF;
END
$(echo '$(echo ''\$do$'')');
' FROM pg_authid where rolname not like 'pg_%' and rolname not like '%%{%';
EOF_PSQL" >$LOG_TMP 2>&1
 then cat <<EOF_CAT | tee -a $FIC_LOG

- Probleme lors de sauvegarde des roles et grants avant clonage !!
---------------
 $(cat $LOG_TMP)
---------------
EOF_CAT
   rm -rf $LOG_TMP; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Sauvegarde des roles et grants avant clonage est OK.
  |
  \-> ${REP_EXP_CFG}/roles_${DB_NAME}_${MACH_DEST}.sql
EOF_CAT
   rm -rf $LOG_TMP
fi

if ! cat<<EOF_CAT | tee -a $FIC_LOG

- Fin d'export de la configuration de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi










-------------------------------------------------------------------------------------pg_build_standby_readonly_node.sh
#!/bin/bash
#----------------------------------------------------------------------------------
#
# Nom : pg_build_standby_readonly_node.sh
# Date de creation :
# Auteurs : 
# Objectif : Permet de construire le noeud standby (3eme noeud de architecture HA) (arret instance +sauvegarde config + clone from standby HA +restaure config + start standby + check )
# Interface : Un argument :
#               - L'alias de la base PostgreSQL clone en question
#                  l'alias fait reference a la base PostgreSQL dans fichier de parametre : pg_param_clone_instance_val.psb
# Date de Modification : 04/02/2021
#
#----------------------------------------------------------------------------------
# Sous repertoire racine des diff. fichiers.
REP_PG="$HOME/adm/dba"
# L'alias de la base PostgreSQL clone en question
PG_ALIAS=$1
# Fichier journal du script.
FIC_LOG=${REP_PG}/log/pg_build_standby_readonly_node_${PG_ALIAS:-Marg}$(date +'_le%d%m%Y').log
# Fichier journal temporaire.
LOG_TEMP=$(dirname $FIC_LOG)/pg_build_stby_${PG_ALIAS:-Marg}$$$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
# Fichier des parametres concernes par le script save_rman_dbpostgres_drp.sh de toutes les bases sujet de la sauvegarde.
FIC_PAR=${REP_PG}/par/pg_param_clone_instance_val.psb
# Emplacement ou stocker les fichiers de config de l'instance sur machine readonly
REP_CONFIG="/home/postgres/adm/pg_conf"
#

>$FIC_LOG
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut de Construction de 3eme noeud Standby (ReadOnly) de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S').
  |
  \`--> L'argument l'alias de la base est :  ${PG_ALIAS:-Marg}
  - Fichier journal disponible sur la machine $(hostname)
  |
  \`--> $FIC_LOG
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#

# Controle de l'argument.
if [ $# -ne 1 ]; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le script necessite un seul argument : l'alias de la base PostgreSQL clone en question !
EOF_CAT
  exit 1
fi
# Recuperation des parametres pour l'instance  en question.
if ! ${REP_PG}/sh/generate_params_clone_postgresql.sh $PG_ALIAS
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme lors de recuperation des parametres par le script shell generate_params_clone_postgresql.sh !!
EOF_CAT
  exit 1
else source ${REP_PG}/par/source_param_clone_postgresql_${PG_ALIAS}.sh
cat<<EOF_CAT | tee -a $FIC_LOG

- Les parametres pour l'alias $PG_ALIAS sont :
$(sed '/PG_PWD/s/[a-z]/\*/g' ${REP_PG}/par/source_param_clone_postgresql_${PG_ALIAS}.sh)
EOF_CAT
fi

# Emplacement de sauvegarde de conf pour 3eme node readonly est dans /home/postgres/adm/export_conf
#REP_EXP_CFG="/home/postgres/adm/export_conf"
#
##Creation de repertoire d'hebergement des fichiers de config + tables de config avant clonage, s'il n'existe pas
#if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ "if ! mkdir -p ${REP_EXP_CFG}; then exit 1; else exit 0;fi"
#then cat<<EOF_CAT | tee -a $FIC_LOG
#
#- Probleme de creation du ${REP_EXP_CFG} sur $MACH_STBY_READ !
#EOF_CAT
#  exit 1
#elif !  ssh -q -o "BatchMode=yes" $MACH_STBY_READ "[ -d ${REP_EXP_CFG} ]"
#then cat<<EOF_CAT | tee -a $FIC_LOG
#
#- Repertoire ${REP_EXP_CFG} inexistant sur ${MACH_STBY_READ} !
#EOF_CAT
#  exit 1
#else cat<<EOF_CAT | tee -a $FIC_LOG
#
#- Repertoire ${REP_EXP_CFG} existe bien sur $MACH_STBY_READ .
#EOF_CAT
#fi

# Sauvegarde de fichier de config avant construction
#if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ "cp $REP_INST/pg_hba.conf $REP_EXP_CFG/pg_hba.conf_${MACH_STBY_READ};cp $REP_INST/postgresql.conf ${REP_EXP_CFG}/postgresql.conf_${MACH_STBY_READ};cp $REP_INST/recovery.conf ${REP_EXP_CFG}/recovery.conf_${MACH_STBY_READ}; cp $REP_INST/postgresql.replication.conf $REP_EXP_CFG/postgresql.replication.conf_${MACH_STBY_READ}" >$LOG_TEMP 2>&1
#   then cat <<EOF_CAT | tee -a $FIC_LOG
#
#- Probleme de sauvegade des fichiers : pg_hba.conf et postgresql.conf de noeud readonly $MACH_STBY_READ !!
#
#$(cat $LOG_TEMP)
#EOF_CAT
#  rm -rf $LOG_TEMP;  exit 1
#else cat<<EOF_CAT | tee -a $FIC_LOG
#
#- Sauvegarde des fichiers pg_hba.conf et postgresql.conf avant build de noeud readonly $MACH_STBY_READ est OK.
#EOF_CAT
#   fi

# S'assurer que l'instance est bien arreter sur Node readonly  avant de proceder au actions
check_pg=$(ssh -q -o "BatchMode=yes" ${MACH_STBY_READ} "ps -fupostgres|awk '\$9 ~/logger|checkpointer|background|stats|walwriter|autovacuum|archiver|logical/' | wc -l" 2>/dev/null)

if [[ ${check_pg} -ge 4 ]];
  then
 if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ ". \$HOME/.bash_profile; /usr/bin/sudo systemctl stop postgres" >$LOG_TEMP 2>&1
  then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme d'arret de l'instance sur la machine $MACH_STBY_READ.
$(cat $LOG_TEMP)
EOF_CAT
  rm -f $LOG_TEMP ; exit 1
 else cat<<EOF_CAT | tee -a $FIC_LOG

- Arret de l'instance sur $MACH_STBY_READ est OK.

$(cat $LOG_TEMP)
EOF_CAT
  rm -f $LOG_TEMP
 fi
else cat<<EOF_CAT | tee -a $FIC_LOG

- L'instance sur $MACH_STBY_READ est deja arrete.
EOF_CAT
fi


#Nettoyage des fichiers de l'instance sur Node MACH_STBY_READ avant lancement de contruction
#if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ  "for rep in \$(ls -d /pg*) ;do find \$rep -mindepth 1 -user postgres 2>/dev/null -delete; done"
if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ  "find /pg* -maxdepth 1 -mindepth 1 -user postgres 2>/dev/null -exec rm -rf {} \;"
  then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de suppression des fichiers existants dans les repertoires /pg* de l'instance sur la machine $MACH_STBY_READ !
EOF_CAT
    exit 1
  else cat<<EOF_CAT | tee -a $FIC_LOG

- Suppression des fichiers existants dans les repertoires /pg* de l'instance sur la machine $MACH_STBY_READ est effectues.
EOF_CAT
  fi

# Lancer la constructionde standby par basebackup
if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ  ". \$HOME/.bash_profile; \$PGHOME/bin/pg_basebackup -D /pgcluster/data -h $MACH_DEST_SECONDARY -U repuser -X stream --waldir=/pgwal/pg_wal -v" >$LOG_TEMP 2>&1
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme Construction de l'instance sur noeud readonly $MACH_STBY_READ via basebackup

$(cat $LOG_TEMP)
EOF_CAT
    rm -rf $LOG_TEMP; exit 1
  else cat<<EOF_CAT | tee -a $FIC_LOG

- Construction de l'instance  sur noeud readonly $MACH_STBY_READ via basebackup est effectues avec succes.

$(cat $LOG_TEMP)
EOF_CAT
 rm -rf $LOG_TEMP
  fi

## Restauration des fichier de config avant demarrage de l'instance
#if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ "cp -p ${REP_EXP_CFG}/pg_hba.conf_${MACH_STBY_READ} $REP_INST/pg_hba.conf; cp -p ${REP_EXP_CFG}/postgresql.conf_${MACH_STBY_READ} $REP_INST/postgresql.conf;cp -p ${REP_EXP_CFG}/recovery.conf_${MACH_STBY_READ} $REP_INST/recovery.conf; cp -p ${REP_EXP_CFG}/postgresql.replication.conf_${MACH_STBY_READ} $REP_INST/postgresql.replication.conf " >$LOG_TEMP 2>&1
#   then cat <<EOF_CAT | tee -a $FIC_LOG
#
#- Probleme de restauration des fichiers : pg_hba.conf et postgresql.conf dans ${MACH_STBY_READ}:$REP_INST.
#
#$(cat $LOG_TEMP)
#EOF_CAT
#  rm -rf $LOG_TEMP;  exit 1

#else cat<<EOF_CAT | tee -a $FIC_LOG
#
#- Restauration des fichiers : pg_hba.conf et postgresql.conf dans ${MACH_STBY_READ}:$REP_INST est OK.
#EOF_CAT
#fi

# Creation des Liens Symbolic vers les fichiers de config qui sont dans $REP_CONFIG
if ! ssh -q -o "BatchMode=yes" $MACH_STBY_READ "for fil in \$(ls ${REP_CONFIG}/*) ;do ln -f -s \$fil /pgcluster/data/\$(basename \$fil); done "
  then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de creation des liens symbolic vers les fichiers de config existants dans ${REP_CONFIG} !
EOF_CAT
    exit 1
  else cat<<EOF_CAT | tee -a $FIC_LOG

- La creation des liens symbolic vers les fichiers de config existants dans ${REP_CONFIG} est effectues avec succes.
EOF_CAT
fi

sleep 20
#Demarrage de l'instance sur noeud read only
if ! ssh -q -o "BatchMode=yes" -t -t $MACH_STBY_READ ". \$HOME/.bash_profile; /usr/bin/sudo systemctl start postgres" >$LOG_TEMP 2>/dev/null
  then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de demarrage de l'instance sur la machine $MACH_STBY_READ.

$(cat $LOG_TEMP)
EOF_CAT
  rm -f $LOG_TEMP ; exit 1
else cat<<EOF_CAT | tee -a $FIC_LOG

- Demarrage de l'instance sur $MACH_STBY_READ est OK.

$(cat $LOG_TEMP)
EOF_CAT
  rm -f $LOG_TEMP
fi


# Verification de status de cluster HA apres construction de standby
cat <<EOF_CAT | tee -a $FIC_LOG

- Status de la Replication apres Construction de l'instance Standby ReadOnly sur 3eme neoud:

$(ssh -q -o "BatchMode=yes" $MACH_DEST_SECONDARY "psql -c 'SELECT txid_current_snapshot() txid_nodeSdby02;'; ssh $MACH_STBY_READ \"psql -c 'SELECT txid_current_snapshot() txid_nodeRead;'\"")
EOF_CAT
###
if ! cat<<EOF_CAT | tee -a $FIC_LOG

- Fin du Construction de 3eme noeud Standby (ReadOnly) de l'alias PostgreSQL $PG_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi
#

---------------------------------------------------------------------------lance_backup_bdd_mssql.sh----------------------------------------------------------------

#!/bin/bash
#-----------------------------------------------------------------------------------------------------
#
# Nom : lance_backup_bdd_mssql.sh
#
# Date de creation : 19/10/2020.
#
# Auteur : 
#
# Objectif : Permet de lancer la sauvegarde d'une base MSSQL sur la machine target
#            apres avoir monter la base et generer les scripts de backup correspondant
#
# Interface : Un seul argument :
#                 L'alias Mssql qui fait reference a la base dans fichier parametre :
#                 param_export_base_mssql.psb
#
# Date de Modification : .
#
#-----------------------------------------------------------------------------------------------------
# L'ialias Mssql reference dans le fichier de parametere
db_alias=$1
# Repertoire des scripts Shell
REP_EXP="/home/oracle/adm/dba"
# Fichier journal
FIC_LOG=${REP_EXP}/log/lance_backup_bdd_mssql_${db_alias:-Marg}$(date +'_le%d%m%Y').log
# Fichier temporaire de gestion des traces.
FIC_TEMP=${REP_EXP}/log/backup_mssql_fic_$$tmp$$.log
# Menage des fichiers journaux (7 jours).
find ${REP_EXP}/log/lance_backup_bdd_mssql_${db_alias:-Marg}_le[0-9]*.log -ctime +7 2>/dev/null -delete
#fichier des parametres concernes par les scripts d'export
FIC_PAR=${REP_EXP}/par/param_export_base_mssql.psb
# client MSQL
SQLCMD=/opt/mssql-tools18/bin/sqlcmd
# MSSQL Access Login
MSSQL_LOGIN=DBA_BACKUP
# Fichier password bases MSSQL
mssql_passfile="${REP_EXP}/par/.mssqlpassfile"

>$FIC_LOG

if ! cat<<EOF_CAT  | tee -a $FIC_LOG
- Debut d'execution de la sauvegarde MSSQL "$(date +'le %d%m%Y a %H:%M:%S')".
  Pour l'argument(s) $*
  Dans $FIC_PAR
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi

# Controle de l'argument.
if [ $# -ne 1 ]; then cat<<EOF_CAT   | tee -a $FIC_LOG

- Le script necessite un seul argument l'alias de la base mssql a sauvegarde !
EOF_CAT
  exit 1
elif [ ! -f $FIC_PAR ] ; then cat<<EOF_CAT  | tee -a $FIC_LOG

- Le fichier des parametres inexistant !
  $FIC_PAR
EOF_CAT
  exit 1
elif ! /bin/egrep $db_alias $FIC_PAR >/dev/null 2>&1 ; then cat<<EOF_CAT   | tee -a $FIC_LOG

- L'alias $db_alias Introuvable dans fichier de parametre :  $FIC_PAR !
EOF_CAT
  exit 1
else cat<<EOF_CAT   | tee -a $FIC_LOG

- La liste des parametres de l'alias $db_alias de la base est :

$(sed -n "/\<$db_alias\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$db_alias {/d;/}/d;/^#/d")
EOF_CAT
fi

for params in $(sed -n "/\<$db_alias\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$db_alias {/d;/}/d;/^#/d"); do
  export $params
done

# Verifier l'existence de fichier mot de passe
if [ ! -f ${mssql_passfile} ];
  then cat<<EOF_CAT | tee -a $FIC_LOG

- Le fichier des mots de passe MSSQL pour l'env de VAL/PROD est introuvable !
  |
  \`--> MSSQL PASSFILE : ${mssql_passfile}
EOF_CAT
  exit 1;
 else
  MSSQL_PWD=$(awk -F':' '/PROD/ && $2~/'$MSSQL_LOGIN'/ && NR>1 {print $3}' ${mssql_passfile})
   if [ -z $MSSQL_PWD ];
     then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme de recuperation de mot de passe de user "MSSQL_LOGIN:$MSSQL_LOGIN" !!
EOF_CAT
     exit 1
   else cat<<EOF_CAT | tee -a $FIC_LOG

- Recuperation de mot de passe de user "MSSQL_LOGIN:$MSSQL_LOGIN" est effectues avec succes.
EOF_CAT
   fi
fi

#Script SQL pour backuper la base MSSQL
SCR_BKP_SQL=${REP_EXP}/sql/BACKUP_MENSUEL_${TARGET_DB_NAME}.sql
#Script cmd pour controler la presence de repertoire de sauvegarde sur la machine CIBEL
SCR_CTL_CMD=${REP_EXP}/cmd/CONTROL_BACKUP_PATH_${TARGET_DB_NAME}.cmd


# Verifier l'existance de l'emplacment de la sauvegarde , et de le creer s'il n'existe pas
# le script de creation  doit s'executer avec compte de domain "boursorama\svc_pbrbksql" puisque PilotageDB n'a pas les droits sur le partage
if ! ssh "boursorama\svc_pbrbksql"@${TARGET_HOST} "C:\BACKUP_MENSUEL\scripts\cmd\\$(basename ${SCR_CTL_CMD})" >$FIC_TEMP  2>&1
then cat<<EOF_CAT  | tee -a $FIC_LOG

- Probleme de creation de repertoire d'hebergement des fichiers de backup : ${BACKUP_PATH}
$(cat $FIC_TEMP)
EOF_CAT
exit 1;
else cat<<EOF_CAT  | tee -a $FIC_LOG

- Creation de repertoire d'hebergement des fichiers de backup est effectue avec succes !
$(cat $FIC_TEMP)
EOF_CAT
fi

#
if ! sudo docker exec -i mssql bash "$SQLCMD -C -b -S $TARGET_HOST -U $MSSQL_LOGIN -P $MSSQL_PWD -i $SCR_BKP_SQL" >$FIC_TEMP
then cat<<EOF_CAT  | tee -a $FIC_LOG

- Porbleme lors d'execution de la sauvegarde de la base "${TARGET_DB_NAME}" sur la machine "${TARGET_HOST}" :
------------------------------------------------------------------------------------------
$(cat $FIC_TEMP)
------------------------------------------------------------------------------------------
EOF_CAT
  rm -rf ${FIC_TEMP}; exit 1;
else cat<<EOF_CAT  | tee -a $FIC_LOG

- Execution de la sauvegarde de la base "${TARGET_DB_NAME}" sur la machine "${TARGET_HOST}" est effectue avec succes:
------------------------------------------------------------------------------------------
$(cat $FIC_TEMP)
------------------------------------------------------------------------------------------
EOF_CAT
fi
#

if ! cat<<EOF_CAT   | tee -a $FIC_LOG

- Fin d'execution de la sauvegarde MSSQL de l'alias $db_alias "$(date +'le %d%m%Y a %H:%M:%S')".
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi
#
                      








---------------------------------------------------------------------------------------------------clone_rubrik_db_mssql.sh--------------------------------------------------------------------------------------------------







#!/bin/bash
#-----------------------------------------------------------------------------------------------------
#
# Nom : clone_rubrik_db_mssql.sh
#
# Date de creation : 19/11/2020.
#
# Auteur : Lahcen BOUDAOUDI
#
# Objectif : Cloner une base MSSQL VAL/REC par RUBRIK (option EXPORT, Fileonly=false).
#
# Interface : deux arguments :
#            OBLIGATOIRE : un alias MSSQL  qui fait reference a la base a clonee dans fichier parametre : param_clone_dbmssql_rubrik.psb
#            OPTIONNEL   : Date de clonage, s'elle n'est pas preciser le script prends le dernier snapshot valide de la base a clonee
#            faut respecter le format de date : MM/DD/YYYY
#
# Date de modification : 07/01/2020, par Lahcen BOUDAOUDI
#
#-----------------------------------------------------------------------------------------------------
# Argument : alias mssql qui fait reference a la base a clonee
DB_ALIAS=$1
# Repertoire racine des diff. fichiers
REP_EXP="/home/oracle/adm/dba"
# Fichier journal
FIC_LOG=${REP_EXP}/log/clone_rubrik_db_mssql_${DB_ALIAS:-Marg}$(date +'_le%d%m%Y').log
# Fichier temporaire de gestion des traces.
FIC_TEMP=${REP_EXP}/tmp/fic_$$tmp$$.log
# Menage des fichiers journaux (7 jours).
find ${REP_EXP}/log/clone_rubrik_db_mssql_${DB_ALIAS:-Marg}_le[0-9]*.log -ctime +7 2>/dev/null -delete
# fichier variables pour les scripts
FIC_SOURCE=${REP_EXP}/par/source_param_clone_dbmssql_${DB_ALIAS}.sh
# Fichier temp output de URL d'export
FILE_OUTPUT=${REP_EXP}/tmp/curl_body_clone_mssql_${DB_ALIAS}
# Fichier temp output de URL de suivi status de CLONAGE
FILE_OUTPUT_STATUS=${REP_EXP}/tmp/curl_body_clone_job_status_$$
# Cluser RUBRIK ou VIP
cluster_rubrik='purbkclu001'
# Date de clonage souhaite : faut respecter le format MM/DD/YYYY
DATE_CLONAGE="$2"
# Rubrik Token associe au compte de service RSC svc_pbrbkapi_dba_Rsc
TOKEN="$(grep RBK_TOKEN ${REP_EXP}/par/rubrik_token_file_Rsc.txt | cut -d'=' -f2)"
#

>$FIC_LOG
if ! cat<<EOF_CAT | tee -a $FIC_LOG
- Debut du clonage de l'alias MSSQL ${DB_ALIAS} $(date +'le %d%m%Y a %H:%M:%S')

- Fichier journal disponible sur la machine $(hostname)
  |
  \`--> $FIC_LOG
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi

#control d'arguement en entree
if [ $# -lt 1 ]; then cat<<EOF_CAT | tee -a $FIC_LOG

- Le script necessite 2 arguments :
    - OBLIGATOIRE : L'alias de la base MSSQL a clonee ,par exemple: ABEL_REC !
    - OPTIONNEL   : Date de clonage, s'elle n'est pas rensigner on va prendre la date de la derniere snapshot valide
                    faut respecter le format de date : MM/DD/YYYY
EOF_CAT

   exit 1
fi

# Recuperation des parametres.
if ! ${REP_EXP}/sh/generate_params_clone_db_mssql.sh $DB_ALIAS "$DATE_CLONAGE"
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme lors de recuperation des parametres par le script shell generate_params_clone_db_mssql.sh ?
EOF_CAT
  exit 1
else source ${REP_EXP}/par/source_param_clone_dbmssql_${DB_ALIAS}.sh
cat<<EOF_CAT | tee -a $FIC_LOG

- Les parametres pour l'alias $DB_ALIAS sont :

$(cat ${REP_EXP}/par/source_param_clone_dbmssql_${DB_ALIAS}.sh)

EOF_CAT
fi
#
#controler la date de clonage
if [ -z "$RB_SRC_DB_SNAP_DATE" ]
then cat<<EOF_CAT | tee -a $FIC_LOG

- Pas de snapshot disponible pour la base ${RB_SRC_DATABASE_NAME} pour la date choisi :  ${DATE_CLONAGE}
- Ci-dessous l'ensemble des snapshots disponible :
----------------------------
$($REP_EXP/sh/mssql_get_info_DateSnap_db.sh ${RB_SRC_DATABASE_ID} |sed -e 's/-/\//g')
----------------------------
EOF_CAT
exit 1;
else cat<<EOF_CAT | tee -a $FIC_LOG
- Recuperation de la date de clonage de la base ${RB_SRC_DATABASE_NAME} OK :
  |
  -> Date de snapshot : "$RB_SRC_DB_SNAP_DATE"

EOF_CAT
fi

############################
# Controler est ce que le mappage des fichiers de la base est necessaire ou non
# si oui recuperer le fichier de mapping
if expr "$(eval echo ${MAP_FILES})" : "[nN]"  >/dev/null
then cat<<EOF_CAT | tee -a $FIC_LOG

- Le mappage des fichiers '*.mdf,*.ndf et *.ldf' de la base n'est pas necessaire.

EOF_CAT
RB_targetFilePaths=''
else cat<<EOF_CAT | tee -a $FIC_LOG
- Le mappage des fichiers '*.mdf,*.ndf et *.ldf' de la base est necessaire.
EOF_CAT
 if [ ! -f "${REP_EXP}/json/${RB_FIC_MAPPING}" ]
 then cat<<EOF_CAT | tee -a $FIC_LOG
- Le fichier ${RB_FIC_MAPPING} de mappage des fichiers MSSQL de la base n'existe pas.

EOF_CAT
exit 1;
else cat<<EOF_CAT | tee -a $FIC_LOG
- Le fichier ${RB_FIC_MAPPING} de mappage des fichiers MSSQL de la base est bien present.

EOF_CAT
exit 1;
else cat<<EOF_CAT | tee -a $FIC_LOG
- Le fichier ${RB_FIC_MAPPING} de mappage des fichiers MSSQL de la base est bien present.

EOF_CAT
 fi
RB_targetFilePaths='"targetFilePaths":'$(cat ${REP_EXP}/json/${RB_FIC_MAPPING})','
fi

#exit 0;

#Convertion de la date de snapshot en millisecond et en second
# Date de snapshot recuprer depusi RUBRIK est en decalage de 1h
########################
IFS=
DATE_CLONE_s=$(date --date="${RB_SRC_DB_SNAP_DATE} +1 hour" +"%s")
DATE_CLONE_ms=$(date --date="${RB_SRC_DB_SNAP_DATE} +1 hour" +"%s000")
# Request  URL pour lancer le Clonage ( export RUBRIK )
URL_CLONE="https://${cluster_rubrik}/api/v1/mssql/db/${RB_SRC_DATABASE_ID}/export"
# Parametre de Clonage
PARAM_CLONE='{"recoveryPoint":{"timestampMs": '$DATE_CLONE_ms'},"targetInstanceId": "'${RB_TARGET_INSTANCE_ID}'","targetDatabaseName": "'${RB_TARGET_DATABASE_NAME}'",'${RB_targetFilePaths}'"finishRecovery": '${RB_FinishRecovery}',"maxDataStreams": '${RB_MaxDataStreams}',"allowOverwrite": '${RB_AllowOverwrite}'}'
#PARAM_CLONE='{"recoveryPoint":{"timestampMs": '$DATE_CLONE_ms'},"targetInstanceId": "'${RB_TARGET_INSTANCE_ID}'","targetDatabaseName": "'${RB_TARGET_DATABASE_NAME}'","finishRecovery": '${RB_FinishRecovery}',"maxDataStreams": '${RB_MaxDataStreams}',"allowOverwrite": '${RB_AllowOverwrite}'}'
########################
#echo "targetFilePaths=$(cat $FIC_MAPPING)"
#echo "PARAM_CLONE=="$PARAM_CLONE
#echo "URL_CLONE=="$URL_CLONE
#exit 0;

call_code=`curl --silent --insecure --header 'Content-Type: application/json' --header 'Authorization: Bearer '$TOKEN'' -w "%{http_code}" --request POST $URL_CLONE --data "${PARAM_CLONE}" -o $FILE_OUTPUT 2>/dev/null`

if [ $call_code -ne 200 ] && [ $call_code -ne 202 ]
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme lors de l'appel a Curl export Rubrik de la base
- code de retour de l'appel Curl : $call_code

EOF_CAT
exit 1;
fi
#
#Suivi l'etat d'avnacement de clonage
#recuperation de l'id de Job d'export
idJob=`cat $FILE_OUTPUT | jq .id | tr -d '"'`
# URL de verification de STATUS de JOB
URL_CHECK="https://${cluster_rubrik}/api/v1/mssql/request/$idJob"

# Faire une boucle pour recuperer et suivre le status de job
pr=1
progress_before=999
while [ "$pr" -ne 0 ]
do
TOKEN="$(grep RBK_TOKEN ${REP_EXP}/par/rubrik_token_file_Rsc.txt | cut -d'=' -f2)"
call_code=`/usr/bin/curl --silent --insecure --header 'Content-Type: application/json' --header 'Authorization: Bearer '$TOKEN'' -w "%{http_code}" --request GET $URL_CHECK -o $FILE_OUTPUT_STATUS 2>/dev/null`
#echo "call_code2="$call_code
if [ $call_code -ne 200 ] && [ $call_code -ne 202 ]
then cat<<EOF_CAT | tee -a $FIC_LOG

- Probleme lors de l'appel a Curl de verification de status de Job
- code de retour de l'appel Curl : $call_code

EOF_CAT
exit 1;
fi
job_status=`cat $FILE_OUTPUT_STATUS | jq .status | tr -d '"'`
job_progress=`cat $FILE_OUTPUT_STATUS | jq .progress | tr -d '"'`

progress_current=${job_progress}
if [ ! -z $job_progress ];
 then

#si status de job encours d'execution reboucle
 if [ "$job_status" == "RUNNING" ]
  then
  pr=1
 fi

#si status de job  succes sort de la boucle avec un message OK
 if [ "$job_status" == "SUCCEEDED" ]
  then cat<<EOF_CAT | tee -a $FIC_LOG

 - Clonage de la base ${RB_SRC_DATABASE_NAME} est effectues avec succes : status -> $job_status
EOF_CAT
   pr=0
  break;
 fi
#si status de job Failed or cancel sort de la boucle avec un message KO
 if [ "$job_status" == "FAILED" ] || [  "$job_status" == "CANCELED" ]
 then cat<<EOF_CAT | tee -a $FIC_LOG

 - Clonage de la base ${RB_SRC_DATABASE_NAME} est Echoue : status -> $job_status
EOF_CAT
  pr=0
  exit 1;
  fi
else
pr=0
fi
sleep 300

if [ "$job_status" != "SUCCEEDED" ]
 then
   if  [ "${progress_current}" != "${progress_before}" ]
    then cat<<EOF_CAT | tee -a $FIC_LOG
  Avancement de Clonage de la base ${RB_SRC_DATABASE_NAME} : $job_status ${job_progress}%
EOF_CAT
   progress_before=${progress_current}
   fi
else cat<<EOF_CAT | tee -a $FIC_LOG
  Avancement de Clonage de la base ${RB_SRC_DATABASE_NAME}: $job_status  OK.
EOF_CAT
fi

done

#
if ! cat<<EOF_CAT | tee -a $FIC_LOG

- Fin du clonage de l'alias MSSQL $DB_ALIAS $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi
#






-----------------------------------------------------------------------------------sur_mssql_log.ksh----------------------------------------------------------------------------------------


#!/bin/bash
#-----------------------------------------------------------------------------------------------------
#
# Nom : sur_mssql_log.ksh
#
# Date de creation : 03/07/2023.
#
# Auteur : Mohammed DABLIJ
#
# Objectif : Surveillance du fichier journal des bases mssql hebergees par un serveur.
#
# Interface : Aucun argument.
#
#-----------------------------------------------------------------------------------------------------
# Adresse pour le(s) DBA(s).
LS_ADRS="dba-fr@boursorama.fr"
#LS_ADRS="mohammed.dablij@boursorama.fr"
# client MSQL
SQLCMD=/opt/mssql-tools18/bin/sqlcmd
# Repertoire racine des scripts dba.
REP_SC="/home/oracle/adm/dba"
# Sous repertoire des fichiers journaux.
REP_LOG=${REP_SC}/log
# Fichiers contenant la liste des serveurs sqlserver.
list_servers_val=${REP_SC}/par/list_servers_sqlserver_validation.txt
list_servers_prod=${REP_SC}/par/list_servers_sqlserver_production.txt

# Liste des serveurs MSSQL
LS_SER_MSSQL=$(awk '/pwsql/ && $1!~/^--/ {print $1}' ${list_servers_prod})

# Date de debut d'horodatage du fichier journal de l'instance MSSQL.
DATE_VER="$(date --date="-45 minutes" +"%Y-%m-%d %H:%M:00")"
# Nombre des erreurs rencontrees.
NB_ERR=0
#
# Envoyer un e-mail.
function E_MAIL
{ AttachFile=$2
  if ! (cat<<EOF_CAT
From: oracle@$(hostname -a).boursorama.fr
To: $LS_ADRS
Subject: Presence des erreurs dans le journal MSSQL de $1
Mime-Version: 1.0
content-type: multipart/related; boundary=xChaineLimtex
--xChaineLimtex
Content-Type: text/plain
Content-Disposition: inline

Bonjour

Pour analyser les erreurs ci-dessous de l'instance MSSQL hebergee par $1 voir fichier ci-joint :
$(cat $3)

Cordialement
  Equipe DBA.
--xChaineLimtex
Content-Type: text/plain; name=$(basename $2)
Content-Disposition: attachment; filename=$(basename $2)

$(cat $AttachFile)
EOF_CAT
)|/usr/sbin/sendmail -t
 then cat<<EOF_CAT>>$FIC_LOG

- Probleme de derouter un e-mail au(x) "$LS_ADRS" !

EOF_CAT
  else cat<<EOF_CAT>>$FIC_LOG

- E-mail est OK pour $LS_ADRS.
EOF_CAT
#
  fi
#
}
#
for NOM_SER in $LS_SER_MSSQL ; do
# Fichier journal temp dedie au serveur en question.
  LOG_TEMP=$REP_LOG/sur_mssql_log_temp_${NOM_SER}.log
# Fichier journal dedie au serveur en question.
  FIC_LOG=$REP_LOG/sur_mssql_log_${NOM_SER}$(date +'_le%d%m%Y').log
# Menage des fichiers journaux (7 jours).
  find $(dirname $FIC_LOG) -name "$(echo $(basename $FIC_LOG .log)|sed 's/[0-9]*$//')*.log" -ctime +7 2>/dev/null -delete
#
  if ! /bin/cat<<EOF_CAT>$FIC_LOG
- Debut de surveillance du fichier journal de l'instance mssql hebergee par $NOM_SER $(date +'le %d/%m/%Y a %H:%M:%S')
- Fichier journal disponible sur la machine $(hostname -a)
  |
  \`--> $FIC_LOG
EOF_CAT
  then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
    NB_ERR=$(($NB_ERR + 1))
    continue
  fi
# Lecture du fichier journal de l'instance MSSQL.
  if ! sudo docker exec -i mssql bash -c "$SQLCMD -C -S$NOM_SER -UUserDBA -Pgt4id5 -h-1 -b<<EOF_SQL
SET NOCOUNT ON;
EXEC xp_readerrorlog 0, 1, NULL, NULL, N'$DATE_VER', NULL, N'desc'
GO
EOF_SQL" |col -b>$LOG_TEMP
  then cat<<EOF_CAT>>$FIC_LOG

- Probleme de recuperer le fichier journal de l'instance :
$(cat $LOG_TEMP)
EOF_CAT
    NB_ERR=$(($NB_ERR + 1))
# Remonte l'information aux DBAs.
    E_MAIL $NOM_SER $LOG_TEMP $FIC_LOG
    continue
  else cat<<EOF_CAT>>$FIC_LOG

- Recuperation du fichier journal de l'instance est OK :
EOF_CAT
    if egrep -e "Error: [0-9]*" $LOG_TEMP 2>/dev/null
    then cat<<EOF_CAT>>$FIC_LOG
- Les differentes erreurs localisees dans le fichier journal de l'instance :
$(awk '/Error\: [0-9]*/{print substr($0,index($0,$4))}' $LOG_TEMP 2>/dev/null|sort -u|awk '{print NR". "$0}')

EOF_CAT
      NB_ERR=$(($NB_ERR + 1))
      E_MAIL $NOM_SER $LOG_TEMP $FIC_LOG
      rm -f $LOG_TEMP
      continue
    else cat<<EOF_CAT>>$FIC_LOG

- Aucune erreur detectee au niveau du fichier journal de l'instance MSSQL.

- Fin   de surveillance du fichier journal de l'instance MSSQL hebergee par $NOM_SER $(date +'le %d/%m/%Y a %H:%M:%S')
EOF_CAT
      rm -f $LOG_TEMP
    fi
  fi
#
done
#
if [ $NB_ERR -ne 0 ]; then
  exit 1
else exit 0
fi
#




-------------------------------------------------------------------------------------generate_params_clone_db_mssql.sh---------------------------------------------------------






#!/bin/bash
#-----------------------------------------------------------------------------------------------------
#
# Nom : generate_params_clone_db_mssql.sh
#
# Date de creation : 19/11/2020.
#
# Auteur :
#
# Objectif : Generation des variables necessaire pour Cloner une base MSSQL VAL/REC par RUBRIK (option EXPORT).
#
# Interface : Un argument : un alias oracle qui fait reference a la base a clonee dans fichier parametre :
#             param_clone_dboracle_rubrik.psb
#-----------------------------------------------------------------------------------------------------
# Argument : alias mssql qui fait reference a la base a clonee
DB_ALIAS=$1
# Repertoire racine des diff. fichiers
REP_EXP="/home/oracle/adm/dba"
# Fichier journal
FIC_LOG=${REP_EXP}/log/generate_params_clone_db_mssql_${DB_ALIAS:-Marg}$(date +'_le%d%m%Y').log
# Fichier temporaire de gestion des traces.
FIC_TEMP=${REP_EXP}/tmp/fic_$$tmp$$.log
# fichier Temporaire qui contient les date des snapshot
FIC_TEMP_SNAP=${REP_EXP}/tmp/fic_snap_$$tmp$$.log
# Menage des fichiers journaux (7 jours).
find ${REP_EXP}/log/generate_params_clone_db_mssql_${DB_ALIAS:-Marg}_le[0-9]*.log -ctime +7 2>/dev/null -delete
#fichier des parametres concernes par les scripts de clonage
FIC_PAR=${REP_EXP}/par/param_clone_dbmssql_rubrik.psb
# fichier variables pour les scripts
FIC_SOURCE=${REP_EXP}/par/source_param_clone_dbmssql_${DB_ALIAS}.sh
# Date de clonage souhaite : faut respecter le format MM/DD/YYYY
DATE_CLONAGE="$2"
#
if ! cat<<EOF_CAT >$FIC_LOG
- Debut de recuperation des variables pour le clonage d'une base MSSQL  $(date +'le %d%m%Y a %H:%M:%S')
  Pour l'argument(s) $*
  Dans $FIC_PAR
EOF_CAT
then echo "- Probleme au niveau de la creation du fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; fi
#
# Controle de l'argument.
if [ $# -lt 1 ]; then cat<<EOF_CAT  >>$FIC_LOG

- Le script necessite 2 arguments :
      - OBLIGATOIRE : L'alias de la base MSSQL a clonee !
      - OPTIONNEL   : Date de clonage !
EOF_CAT
  exit 1
elif [ ! -f $FIC_PAR ] ; then cat<<EOF_CAT >>$FIC_LOG

- Le fichier des parametres inexistant !
  $FIC_PAR
EOF_CAT
  exit 1
elif ! /bin/egrep $DB_ALIAS $FIC_PAR >/dev/null 2>&1 ; then cat<<EOF_CAT  >>$FIC_LOG

- L'alias $DB_ALIAS Introuvable dans fichier de parametre :  $FIC_PAR !
EOF_CAT
  exit 1
else cat<<EOF_CAT  >>$FIC_LOG

- La liste des parametres de l'alias $DB_ALIAS de la base est :

$(sed -n "/\<$DB_ALIAS\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$DB_ALIAS {/d;/}/d;/^#/d;/UPWD_/s/[a-z]/\*/g")
EOF_CAT
fi

for params in $(sed -n "/\<$DB_ALIAS\> {/,/}/p" $FIC_PAR|sed -e "s/'//g;s/\"//g;/$DB_ALIAS {/d;/}/d;/^#/d"); do
  export $params
done
#
#generation des variables pour effectuer un Clonage d'une base MSSQL
#recuperer l'id rubrik de la base Source a Clonee
if ! $REP_EXP/sh/mssql_get_info_dbname_host.sh ${SOURCE_DB} ${SOURCE_HOST} >${FIC_TEMP} 2>/dev/null
then cat<<EOF_CAT  >>$FIC_LOG

- Probleme de generation de l'id rubrik de la base MSSQL source : $SOURCE_DB !
EOF_CAT
exit 1
else cat<<EOF_CAT  >>$FIC_LOG

- Generation de l'id rubrik de la base MSSQL source : $SOURCE_DB OK.
EOF_CAT
echo "RB_SRC_DATABASE_ID="$(cat ${FIC_TEMP} | grep DATABASE_ID | cut -d"=" -f2) >${FIC_SOURCE}
echo "RB_SRC_DATABASE_NAME="$(cat ${FIC_TEMP} | grep DATABASE_NAME | cut -d"=" -f2) >>${FIC_SOURCE}
echo "RB_SRC_HOST_NAME="$(cat ${FIC_TEMP} | grep -w DATABASE_HOST | cut -d"=" -f2) >>${FIC_SOURCE}
rm -rf ${FIC_TEMP}
fi
#
# Recuperation de la date de snapshot Rubrik pour la base en question
#    --> recuperer l'id de la base
db_id=$(cat ${FIC_SOURCE} | grep RB_SRC_DATABASE_ID | cut -d"=" -f2)

if ! $REP_EXP/sh/mssql_get_info_DateSnap_db.sh ${db_id} >${FIC_TEMP_SNAP} 2>/dev/null
then cat<<EOF_CAT >>$FIC_LOG

- Probleme de recuperation de la date de toutes les snapshots rubrik disponible de la base $SOURCE_DB !
EOF_CAT
exit 1
else cat<<EOF_CAT >>$FIC_LOG

- Recuperation de la date de toutes les snapshots rubrik disponible de la base $SOURCE_DB OK.
EOF_CAT
fi

#si la date de clonage n'est pas fourni, faut recuperer la date de derniere snapshot valide
if [ ! -z "$DATE_CLONAGE" ]
then
echo "RB_SRC_DB_SNAP_DATE="'"'$( /bin/grep $(date --date="${DATE_CLONAGE}" +"%Y-%m-%d") ${FIC_TEMP_SNAP} | tail -1)'"'  >>${FIC_SOURCE}
else
echo "RB_SRC_DB_SNAP_DATE="'"'$(cat ${FIC_TEMP_SNAP} | sort -M | tail -1)'"'  >>${FIC_SOURCE}
fi
rm -rf ${FIC_TEMP_SNAP}
#
#recuperer l'id rubrik de l'instance de la machine auxiliare ou faut cloner la base
if ! $REP_EXP/sh/mssql_get_info_sqlserver_host.sh ${TARGET_HOST} >${FIC_TEMP} 2>/dev/null
then cat<<EOF_CAT  >>$FIC_LOG

- Probleme de generation de l'id rubrik de l'instance de la machine target ${TARGET_HOST} !
EOF_CAT
exit 1
else cat<<EOF_CAT >>$FIC_LOG

- Probleme de generation de l'id rubrik de l'instance de la machine target ${TARGET_HOST} !
EOF_CAT
exit 1
else cat<<EOF_CAT >>$FIC_LOG

- Generation de l'id rubrik de l'instance de la machine target ${TARGET_HOST} OK.
EOF_CAT
echo "RB_TARGET_HOST_NAME="$(cat ${FIC_TEMP} | grep HOST_NAME | cut -d"=" -f2) >>${FIC_SOURCE}
echo "RB_TARGET_HOST_ID="$(cat ${FIC_TEMP} | grep HOST_ID  | cut -d"=" -f2) >>${FIC_SOURCE}
echo "RB_TARGET_INSTANCE_ID="$(cat ${FIC_TEMP} | grep INSTANCE_ID | cut -d"=" -f2) >>${FIC_SOURCE}
rm -rf ${FIC_TEMP}
fi

# generation d'autres parametres necessaire pour faire le clonage via RUBRIK
if ! cat<<EOF_CAT >>${FIC_SOURCE} 2>/dev/null
RB_TARGET_DATABASE_NAME=${TARGET_DB}
RB_FinishRecovery=$FinishRecovery
RB_AllowOverwrite=$AllowOverwrite
RB_MaxDataStreams=$MaxDataStreams
MAP_FILES=${MAP_FILES}
RB_FIC_MAPPING=${FIC_MAPPING}
EOF_CAT
then cat<<EOF_CAT >>$FIC_LOG

- Probleme de generation d'autres parametres pour Clonage de la base $SOURCE_DB !
EOF_CAT
  exit 1
else cat<<EOF_CAT >>$FIC_LOG

- Generation d'autres parametres pour Clonage de la base $SOURCE_DB OK.
EOF_CAT
fi

if ! cat<<EOF_CAT  >>$FIC_LOG

- Fin de recuperation des variables pour le clonage d'une MSSQL $(date +'le %d%m%Y a %H:%M:%S')
EOF_CAT
then echo "- Probleme d'ecriture dans le fichier log ci-dessous :\n    |\n    \`--> $FIC_LOG"
  exit 1; else exit 0; fi
#



            



                                                                                                                               






                                                                                                                                                                                                    








