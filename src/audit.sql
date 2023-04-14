
create schema if not exists pgiam;

\set drop_table_flag `echo "$DROP_TABLES"`
create or replace function drop_tables(drop_table_flag boolean default 'true')
    returns boolean as $$
    declare ans boolean;
    begin
        if drop_table_flag = 'true' then
            raise notice 'DROPPING AUDIT TABLES';
            drop table if exists audit_log_objects cascade;
            drop table if exists audit_log_relations cascade;
        else
            raise notice 'NOT dropping tables - only functions will be replaced';
        end if;
    return true;
    end;
$$ language plpgsql;
select drop_tables(:drop_table_flag);


create table if not exists audit_log_objects(
    identity text default null,
    operation text not null,
    event_time timestamptz default current_timestamp,
    table_name text not null,
    row_id uuid not null,
    column_name text,
    old_data text,
    new_data text
) partition by list (table_name);
create table if not exists audit_log_objects_persons
    partition of audit_log_objects for values in ('persons');
create table if not exists audit_log_objects_users
    partition of audit_log_objects for values in ('users');
create table if not exists audit_log_objects_groups
    partition of audit_log_objects for values in ('groups');
create table if not exists audit_log_objects_capabilities_http
    partition of audit_log_objects for values in ('capabilities_http');
create table if not exists audit_log_objects_capabilities_http_instances
    partition of audit_log_objects for values in ('capabilities_http_instances');
create table if not exists audit_log_objects_capabilities_http_grants
    partition of audit_log_objects for values in ('capabilities_http_grants');
create table if not exists audit_log_objects_institutions
    partition of audit_log_objects for values in ('institutions');
create table if not exists audit_log_objects_projects
    partition of audit_log_objects for values in ('projects');


create table if not exists audit_log_relations(
    identity text default null,
    operation text not null,
    event_time timestamptz default current_timestamp,
    table_name text not null,
    parent text,
    child text,
    start_date timestamptz,
    end_date timestamptz,
    weekdays jsonb
) partition by list (table_name);
create table if not exists audit_log_relations_group_memberships
    partition of audit_log_relations for values in ('group_memberships');
create table if not exists audit_log_relations_group_moderators
    partition of audit_log_relations for values in ('group_moderators');
create table if not exists audit_log_relations_group_affiliations
    partition of audit_log_relations for values in ('group_affiliations');


drop function if exists update_audit_log_objects() cascade;
create or replace function update_audit_log_objects()
    returns trigger as $$
    declare old_data text;
    declare new_data text;
    declare colname text;
    declare table_name text;
    declare session_identity text;
    begin
        table_name := TG_TABLE_NAME::text;
        session_identity := current_setting('session.identity', 't');
        for colname in execute
            format('select c.column_name::text
                    from pg_catalog.pg_statio_all_tables as st
                    inner join information_schema.columns c
                    on c.table_schema = st.schemaname and c.table_name = st.relname
                    left join pg_catalog.pg_description pgd
                    on pgd.objoid = st.relid
                    and pgd.objsubid = c.ordinal_position
                    where st.relname = $1
                    and st.schemaname = $2') using table_name, 'public'
        loop
            execute format('select ($1).%s::text', colname) using OLD into old_data;
            execute format('select ($1).%s::text', colname) using NEW into new_data;
            if old_data != new_data or (old_data is null and new_data is not null) then
                insert into audit_log_objects (identity, operation, table_name, row_id, column_name, old_data, new_data)
                    values (session_identity, TG_OP, table_name, NEW.row_id, colname, old_data, new_data);
            end if;
        end loop;
        if TG_OP = 'DELETE' then
            insert into audit_log_objects (identity, operation, table_name, row_id, column_name, old_data, new_data)
                values (session_identity, TG_OP, table_name, OLD.row_id, null, null, null);
        end if;
        return new;
    end;
$$ language plpgsql;


drop function if exists update_audit_log_relations() cascade;
create or replace function update_audit_log_relations()
    returns trigger as $$
    declare table_name text;
    declare parent text;
    declare child text;
    declare session_identity text;
    declare start_date timestamptz := null;
    declare end_date timestamptz := null;
    declare weekdays jsonb := null;
    begin
        session_identity := current_setting('session.identity', 't');
        table_name := TG_TABLE_NAME::text;
        if TG_OP in ('INSERT', 'UPDATE') then
            if table_name = 'group_memberships' then
                parent := NEW.group_name;
                child := NEW.group_member_name;
                start_date := NEW.start_date;
                end_date := NEW.end_date;
                weekdays := NEW.weekdays;
            elsif table_name = 'group_moderators' then
                parent := NEW.group_name;
                child := NEW.group_moderator_name;
            elsif table_name = 'group_affiliations' then
                parent := NEW.parent_group;
                child := NEW.child_group;
            end if;
        elsif TG_OP = 'DELETE' then
            if table_name = 'group_memberships' then
                parent := OLD.group_name;
                child := OLD.group_member_name;
                start_date := OLD.start_date;
                end_date := OLD.end_date;
                weekdays := OLD.weekdays;
            elsif table_name = 'group_moderators' then
                parent := OLD.group_name;
                child := OLD.group_moderator_name;
            elsif table_name = 'group_affiliations' then
                parent := OLD.parent_group;
                child := OLD.child_group;
            end if;
        end if;
        insert into audit_log_relations(
            identity, operation, table_name, parent, child, start_date, end_date, weekdays
        ) values (
            session_identity, TG_OP, table_name, parent, child, start_date, end_date, weekdays
        );
        return new;
    end;
$$ language plpgsql;
