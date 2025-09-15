
# define new tables
# psql -U $DBOWNER -h $DBHOST -d $DBNAME -f src/clients.sql

# add partitions to audit tables

create table if not exists audit_log_objects_clients
    partition of audit_log_objects for values in ('clients');
create table if not exists audit_log_objects_client_ips
    partition of audit_log_objects for values in ('client_ips');
