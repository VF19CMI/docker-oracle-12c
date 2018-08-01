echo "XE:$ORACLE_HOME:N" >> /etc/oratab
chown oracle:dba /etc/oratab
chmod 664 /etc/oratab
rm -rf /u01/app/oracle-product/12.1.0/xe/dbs
ln -s /u01/app/oracle/dbs /u01/app/oracle-product/12.1.0/xe/dbs
#Startup Database
su oracle -c "/u01/app/oracle/product/12.1.0/xe/bin/tnslsnr &"
su oracle -c 'echo startup\; | $ORACLE_HOME/bin/sqlplus -S / as sysdba'
