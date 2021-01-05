
-- using install.sh
-- replace functions
-- modify audit tables
-- define organisational tables

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
