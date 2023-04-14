
\set drop_table_flag `echo "$DROP_TABLES"`
create or replace function drop_tables(drop_table_flag boolean default 'true')
    returns boolean as $$
    declare ans boolean;
    begin
        if drop_table_flag = 'true' then
            raise notice 'DROPPING ORGANISATION TABLES';
            drop table if exists institutions cascade;
            drop table if exists projects cascade;
        else
            raise notice 'NOT dropping tables - only functions will be replaced';
        end if;
    return true;
    end;
$$ language plpgsql;
select drop_tables(:drop_table_flag);


create table if not exists institutions(
    row_id uuid unique not null default gen_random_uuid(),
    institution_id uuid unique not null default gen_random_uuid(),
    institution_name text not null primary key,
    institution_long_name text not null,
    institution_group text,
    institution_activated boolean not null default 't',
    institution_expiry_date timestamptz,
    institution_metadata jsonb
);

create trigger institutions_audit after update or insert or delete on institutions
    for each row execute procedure update_audit_log_objects();

drop function if exists institution_immutability() cascade;
create or replace function institution_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise integrity_constraint_violation
            using message = 'row_id is immutable';
        elsif OLD.institution_id != NEW.institution_id then
            raise integrity_constraint_violation
            using message = 'institution_id is immutable';
        elsif OLD.institution_name != NEW.institution_name then
            raise integrity_constraint_violation
            using message = 'institution_name is immutable';
        elsif OLD.institution_group != NEW.institution_group then
            raise integrity_constraint_violation
            using message = 'institution_group is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_institution_immutability before update on institutions
    for each row execute procedure institution_immutability();


drop function if exists institution_management() cascade;
create or replace function institution_management()
    returns trigger as $$
    declare new_grp text;
    begin
        if (TG_OP = 'INSERT') then
            new_grp := NEW.institution_name || '-group';
            update institutions set institution_group = new_grp
                where institution_name = NEW.institution_name;
            insert into groups (
                group_name,
                group_class,
                group_type,
                group_expiry_date,
                group_description
            ) values (
                new_grp,
                'secondary',
                'institution',
                NEW.institution_expiry_date,
                'institution group'
            );
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.institution_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.institution_activated != NEW.institution_activated then
                update groups set group_activated = NEW.institution_activated
                    where group_name = OLD.institution_group;
            end if;
            if OLD.institution_expiry_date != NEW.institution_expiry_date then
                update groups set group_expiry_date = NEW.institution_expiry_date
                    where group_name = OLD.institution_group;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger institution_group_trigger after insert or delete or update on institutions
    for each row execute procedure institution_management();


create trigger institutions_channel_notify after update or insert or delete on institutions
    for each row execute procedure notify_listeners();


drop function if exists institution_member_add(text, text);
create or replace function institution_member_add(
    institution text,
    member text
) returns json as $$
    declare inst_group text;
    declare mem_group text;
    begin
        inst_group := find_group(institution);
        mem_group := find_group(member);
        insert into group_memberships(
            group_name, group_member_name
        ) values (
            inst_group, mem_group
        );
        return json_build_object(
            'message', 'added ' || member || ' to ' || institution
        );
    end;
$$ language plpgsql;


drop function if exists institution_member_remove(text, text);
create or replace function institution_member_remove(
    institution text,
    member text
) returns json as $$
    declare inst_group text;
    declare mem_group text;
    begin
        inst_group := find_group(institution);
        mem_group := find_group(member);
        delete from group_memberships
            where group_name = inst_group
            and group_member_name = mem_group;
        return json_build_object(
            'message', 'removed ' || member || ' from ' || institution
        );
    end;
$$ language plpgsql;


drop function if exists institution_members(text);
create or replace function institution_members(
    institution text
) returns json as $$
    begin
        return group_members(find_group(institution));
    end;
$$ language plpgsql;


drop function if exists institution_group_add(text, text);
create or replace function institution_group_add(
    institution text,
    group_name text
) returns json as $$
    declare inst_group text;
    begin
        inst_group := find_group(institution);
        perform find_group(group_name);
        insert into group_affiliations(
            parent_group, child_group
        ) values (
            inst_group, group_name
        );
        return json_build_object(
            'message', 'added ' || group_name || ' to ' || institution
        );
    end;
$$ language plpgsql;


drop function if exists institution_group_remove(text, text);
create or replace function institution_group_remove(
    institution text,
    group_name text
) returns json as $$
    declare inst_group text;
    begin
        inst_group := find_group(institution);
        perform find_group(group_name);
        delete from group_affiliations
            where parent_group = inst_group
            and child_group = group_name;
        return json_build_object(
            'message', 'removed ' || group_name || ' from ' || institution
        );
    end;
$$ language plpgsql;


drop function if exists institution_groups(text) cascade;
create or replace function institution_groups(institution text)
    returns json as $$
    begin
        return group_affiliates(find_group(institution));
    end;
$$ language plpgsql;


create table if not exists projects(
    row_id uuid unique not null default gen_random_uuid(),
    project_id uuid unique not null default gen_random_uuid(),
    project_number text not null primary key,
    project_name text not null,
    project_long_name text,
    project_activated boolean not null default 't',
    project_start_date timestamptz not null,
    project_end_date timestamptz not null,
    project_group text,
    project_metadata jsonb
);

create trigger projects_audit after update or insert or delete on projects
    for each row execute procedure update_audit_log_objects();

drop function if exists project_immutability() cascade;
create or replace function project_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise integrity_constraint_violation
            using message = 'row_id is immutable';
        elsif OLD.project_id != NEW.project_id then
            raise integrity_constraint_violation
            using message = 'project_id is immutable';
        elsif OLD.project_number != NEW.project_number then
            raise integrity_constraint_violation
            using message = 'project_number is immutable';
        elsif OLD.project_group != NEW.project_group then
            raise integrity_constraint_violation
            using message = 'project_group is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_project_immutability before update on projects
    for each row execute procedure project_immutability();


drop function if exists project_management() cascade;
create or replace function project_management()
    returns trigger as $$
    declare new_grp text;
    begin
        if (TG_OP = 'INSERT') then
            new_grp := NEW.project_number || '-group';
            update projects set project_group = new_grp
                where project_number = NEW.project_number;
            insert into groups (
                group_name,
                group_class,
                group_type,
                group_primary_member,
                group_expiry_date,
                group_description
            ) values (
                new_grp,
                'primary',
                'project',
                NEW.project_number,
                NEW.project_end_date,
                'project group'
            );
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.project_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.project_activated != NEW.project_activated then
                update groups set group_activated = NEW.project_activated
                    where group_name = OLD.project_group;
            end if;
            if OLD.project_end_date != NEW.project_end_date then
                update groups set group_expiry_date = NEW.project_end_date
                    where group_name = OLD.project_group;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger project_group_trigger after insert or delete or update on projects
    for each row execute procedure project_management();

create trigger projects_channel_notify after update or insert or delete on projects
    for each row execute procedure notify_listeners();


drop function if exists project_group_add(text, text) cascade;
create or replace function project_group_add(
    project text,
    group_name text
) returns json as $$
    declare project_group text;
    begin
        project_group = find_group(project);
        perform find_group(group_name);
        insert into group_affiliations values (project_group, group_name);
        return json_build_object(
            'message', 'added ' || group_name || ' to ' || project
        );
    end;
$$ language plpgsql;


drop function if exists project_group_remove(text, text) cascade;
create or replace function project_group_remove(
    project text,
    group_name text
) returns json as $$
    declare project_group text;
    begin
        project_group = find_group(project);
        perform find_group(group_name);
        delete from group_affiliations
            where parent_group = project_group
            and child_group = group_name;
        return json_build_object(
            'message', 'removed ' || group_name || ' from ' || project
        );
    end;
$$ language plpgsql;


drop function if exists project_institutions(text) cascade;
create or replace function project_institutions(project text)
    returns json as $$
    declare project_group text;
    declare data json;
    begin
        project_group = find_group(project);
        select json_agg(
            json_build_object(
                'institution', institution_name,
                'institution_group', member_group_name,
                'member', member_name
            )
        ) from group_get_parents(project_group)
        left join institutions on member_group_name = institution_group into data;
        return json_build_object('project', project, 'institutions', data);
    end;
$$ language plpgsql;


drop function if exists project_groups(text) cascade;
create or replace function project_groups(project text)
    returns json as $$
    declare project_group text;
    begin
        project_group = find_group(project);
        return group_affiliates(project_group);
    end;
$$ language plpgsql;
