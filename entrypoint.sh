#!/bin/bash
set -e

# Prevent owner issues on mounted folders, if desired
if [ "$ENABLE_OWNERSHIP_FIX" = true ] ; then
	chown -R oracle:dba /u01/app/oracle
	chown -R oracle:dba /docker-entrypoint-initdb.d/
fi

rm -f /u01/app/oracle/product
ln -s /u01/app/oracle-product /u01/app/oracle/product

#Run Oracle root scripts
/u01/app/oraInventory/orainstRoot.sh > /dev/null 2>&1
echo | /u01/app/oracle/product/12.1.0/xe/root.sh > /dev/null 2>&1 || true

if [ -z "$CHARACTER_SET" ]; then
	if [ "${USE_UTF8_IF_CHARSET_EMPTY}" == "true" ]; then
		export CHARACTER_SET="AL32UTF8"
	fi
fi

if [ -n "$CHARACTER_SET" ]; then
	export CHARSET_MOD="NLS_LANG=.$CHARACTER_SET"
	export CHARSET_INIT="-characterSet $CHARACTER_SET"
fi


impdp () {
	set +e
	DUMP_FILE=$(basename "$1")
	DUMP_NAME=${DUMP_FILE%.dmp} 
	cat > /tmp/impdp.sql << EOL
-- Impdp User
CREATE USER IMPDP IDENTIFIED BY IMPDP;
ALTER USER IMPDP ACCOUNT UNLOCK;
GRANT dba TO IMPDP WITH ADMIN OPTION;
-- New Scheme User
create or replace directory IMPDP as '/docker-entrypoint-initdb.d';
create tablespace $DUMP_NAME datafile '/u01/app/oracle/oradata/$DUMP_NAME.dbf' size 1000M autoextend on next 100M maxsize unlimited;
create user $DUMP_NAME identified by $DUMP_NAME default tablespace $DUMP_NAME;
alter user $DUMP_NAME quota unlimited on $DUMP_NAME;
alter user $DUMP_NAME default role all;
grant connect, resource to $DUMP_NAME;
exit;
EOL

	su oracle -c "$CHARSET_MOD $ORACLE_HOME/bin/sqlplus -S / as sysdba @/tmp/impdp.sql"
	su oracle -c "$CHARSET_MOD $ORACLE_HOME/bin/impdp IMPDP/IMPDP directory=IMPDP dumpfile=$DUMP_FILE $IMPDP_OPTIONS"
	#Disable IMPDP user
	echo -e 'ALTER USER IMPDP ACCOUNT LOCK;\nexit;' | su oracle -c "$CHARSET_MOD $ORACLE_HOME/bin/sqlplus -S / as sysdba"
	set -e
}

case "$1" in
	'')
		#Check for mounted database files
		if [ "$(ls -A /u01/app/oracle/oradata 2>/dev/null)" ]; then
			echo "found files in /u01/app/oracle/oradata Using them instead of initial database"
			echo "XE:$ORACLE_HOME:N" >> /etc/oratab
			chown oracle:dba /etc/oratab
			chmod 664 /etc/oratab
			rm -rf /u01/app/oracle-product/12.1.0/xe/dbs
			ln -s /u01/app/oracle/dbs /u01/app/oracle-product/12.1.0/xe/dbs
			#Startup Database
			su oracle -c "/u01/app/oracle/product/12.1.0/xe/bin/tnslsnr &"
			su oracle -c 'echo startup\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'
		else
			echo "Database not initialized. Initializing database."
			export IMPORT_FROM_VOLUME=true


			#printf "Setting up:\nprocesses=$processes\nsessions=$sessions\ntransactions=$transactions\n"
			set +e
			mv /u01/app/oracle-product/12.1.0/xe/dbs /u01/app/oracle/dbs
			set -e

			ln -s /u01/app/oracle/dbs /u01/app/oracle-product/12.1.0/xe/dbs

			echo "Starting tnslsnr"
			su oracle -c "/u01/app/oracle/product/12.1.0/xe/bin/tnslsnr &"
			#create DB for SID: xe
			su oracle -c "$ORACLE_HOME/bin/dbca -silent -createDatabase -templateName General_Purpose.dbc -gdbname xe -sid xe -responseFile NO_VALUE $CHARSET_INIT -totalMemory $DBCA_TOTAL_MEMORY -emConfiguration LOCAL -pdbAdminPassword oracle -sysPassword oracle -systemPassword oracle"
		fi

    echo 'Disabling web management console'
    su oracle -c 'echo EXEC DBMS_XDB.sethttpport\(0\)\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'

		echo "Database ready to use. Enjoy! ;)"

		##
		## Workaround for graceful shutdown.
		##
		;;
	*)
		echo "Database is not configured. Please run '/entrypoint.sh' if needed."
		exec "$@"
		;;
esac
