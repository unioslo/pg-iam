
alter table group_memberships add column if not exists start_date timestamptz;
alter table group_memberships add column if not exists end_date timestamptz;
alter table group_memberships add column if not exists weekdays jsonb;

alter table audit_log_relations add column if not exists start_date timestamptz;
alter table audit_log_relations add column if not exists end_date timestamptz;
alter table audit_log_relations add column if not exists weekdays jsonb;
