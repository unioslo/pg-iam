/*

export SUPERUSER=
export DBOWNER=
export DBNAME=
export DBHOST=

./install.sh --only-replace-functions --setup
# saying yes to all

psql -U $DBOWNER -h $BHOST -d $DBNAME -f mgrt/1.5-to-2.0.sql

./install.sh  --setup
# defining the institutional tabless

*/

-- drop constraints
alter table users drop constraint users_user_group_posix_gid_check;
alter table users drop constraint users_user_posix_uid_check;
alter table groups drop constraint groups_group_posix_gid_check;

-- add new ones
alter table capabilities_http_grants add constraint capabilities_http_grants_grant_max_num_usages_check check (capability_grant_max_num_usages >= 0);
alter table users add constraint users_user_group_posix_gid_check check (user_group_posix_gid > 999);
alter table groups add constraint groups_group_posix_gid_check check (group_posix_gid > 999);

-- then make the audit changes
drop trigger capabilities_http_grants_audit on capabilities_http_grants;
create trigger capabilities_http_grants_audit after update or insert or delete on capabilities_http_grants
    for each row execute procedure update_audit_log_objects();

-- change now() to current_timestamp
-- (to not be affected by session-speifics)
alter table audit_log_objects alter column event_time set default current_timestamp;
alter table audit_log_relations alter column event_time set default current_timestamp;

-- fix typo
drop trigger apabilities_http_grants_correct_names_allowed on capabilities_http_grants;
create trigger capabilities_http_grants_correct_names_allowed before insert or update on capabilities_http_grants
    for each row execute procedure ensure_correct_capability_names_allowed();
