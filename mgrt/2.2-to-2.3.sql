
set session "session.identity" = 'db-migration';

alter table group_memberships add column if not exists start_date timestamptz;
alter table group_memberships add column if not exists end_date timestamptz;
alter table group_memberships add column if not exists weekdays jsonb;
alter table group_memberships add constraint group_memberships_check check (start_date < end_date);

alter table audit_log_relations add column if not exists start_date timestamptz;
alter table audit_log_relations add column if not exists end_date timestamptz;
alter table audit_log_relations add column if not exists weekdays jsonb;

-- make group_class, group_type mutable
create or replace function group_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise integrity_constraint_violation
                using message = 'row_id is immutable';
        elsif OLD.group_id != NEW.group_id then
            raise integrity_constraint_violation
                using message = 'group_id is immutable';
        elsif OLD.group_name != NEW.group_name then
            raise integrity_constraint_violation
                using message = 'group_name is immutable';
        elsif OLD.group_primary_member != NEW.group_primary_member then
            raise integrity_constraint_violation
                using message = 'group_primary_member is immutable';
        elsif OLD.group_posix_gid != NEW.group_posix_gid then
            raise integrity_constraint_violation
                using message = 'group_posix_gid is immutable';
        elsif NEW.group_posix_gid is null and OLD.group_posix_gid is not null then
            raise integrity_constraint_violation
                using message = 'group_posix_gid cannot be set to null once set';
        end if;
    return new;
    end;
$$ language plpgsql;

-- define new group type
alter table groups drop constraint groups_group_type_check;
alter table groups add constraint groups_group_type_check
    check (group_type in ('person', 'user', 'generic', 'web', 'project', 'institution'));

-- change project groups
update groups set group_class = 'primary', group_type = 'project'
    where group_name in (select project_group from projects);

create or replace function update_organisational_groups()
    returns void as $$
    declare pnum text;
    declare grp text;
    begin
        for pnum, grp in select project_number, project_group from projects loop
            raise info 'updating % -> primary member: %', grp, pnum;
            update groups set group_primary_member = pnum
                where group_name = grp;
        end loop;
        for grp in select institution_group from institutions loop
            raise info 'updating % -> group_type: institution', grp;
            update groups set group_type = 'institution'
                where group_name = grp;
        end loop;
    end;
$$ language plpgsql;

select update_organisational_groups();

-- make group_class, group_type immutable again
create or replace function group_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise integrity_constraint_violation
                using message = 'row_id is immutable';
        elsif OLD.group_id != NEW.group_id then
            raise integrity_constraint_violation
                using message = 'group_id is immutable';
        elsif OLD.group_name != NEW.group_name then
            raise integrity_constraint_violation
                using message = 'group_name is immutable';
        elsif OLD.group_class != NEW.group_class then
            raise integrity_constraint_violation
                using message = 'group_class is immutable';
        elsif OLD.group_type != NEW.group_type then
            raise integrity_constraint_violation
                using message = 'group_type is immutable';
        elsif OLD.group_primary_member != NEW.group_primary_member then
            raise integrity_constraint_violation
                using message = 'group_primary_member is immutable';
        elsif OLD.group_posix_gid != NEW.group_posix_gid then
            raise integrity_constraint_violation
                using message = 'group_posix_gid is immutable';
        elsif NEW.group_posix_gid is null and OLD.group_posix_gid is not null then
            raise integrity_constraint_violation
                using message = 'group_posix_gid cannot be set to null once set';
        end if;
    return new;
    end;
$$ language plpgsql;
