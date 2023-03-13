
alter table group_memberships add column if not exists start_date timestamptz;
alter table group_memberships add column if not exists end_date timestamptz;
alter table group_memberships add column if not exists weekdays jsonb;
alter table group_memberships add constraint group_memberships_check check (start_date < end_date);

alter table audit_log_relations add column if not exists start_date timestamptz;
alter table audit_log_relations add column if not exists end_date timestamptz;
alter table audit_log_relations add column if not exists weekdays jsonb;
