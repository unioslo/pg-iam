
create schema if not exists pgiam;

\set drop_table_flag `echo "$DROP_TABLES"`
create or replace function drop_tables(drop_table_flag boolean default 'true')
    returns boolean as $$
    declare ans boolean;
    begin
        if drop_table_flag = 'true' then
            raise notice 'DROPPING IDENTITIES AND GROUPS TABLES';
            drop table if exists persons cascade;
            drop table if exists users cascade;
            drop table if exists groups cascade;
            drop table if exists group_memberships cascade;
            drop table if exists group_moderators cascade;
        else
            raise notice 'NOT dropping tables - only functions will be replaced';
        end if;
    return true;
    end;
$$ language plpgsql;
select drop_tables(:drop_table_flag);


create table if not exists persons(
    row_id uuid unique not null default gen_random_uuid(),
    person_id uuid unique not null primary key default gen_random_uuid(),
    person_activated boolean not null default 't',
    person_expiry_date timestamptz,
    person_group text,
    full_name text not null,
    identifiers jsonb, -- e.g. [{k1: v1, k2: v2}, {...}]
    password text,
    otp_secret text,
    email text,
    person_metadata jsonb
);


create trigger persons_audit after update or insert or delete on persons
    for each row execute procedure update_audit_log_objects();


drop function if exists person_immutability() cascade;
create or replace function person_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise exception using message = 'row_id is immutable';
        elsif OLD.person_id != NEW.person_id then
            raise exception using message = 'person_id is immutable';
        elsif OLD.person_group != NEW.person_group then
            raise exception using message = 'person_group is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_person_immutability before update on persons
    for each row execute procedure person_immutability();


drop function if exists person_uniqueness() cascade;
create or replace function person_uniqueness()
    returns trigger as $$
    declare element jsonb;
    begin
        begin
            for element in select jsonb_array_elements(NEW.identifiers) loop
                if 't' in (select element <@ jsonb_array_elements(identifiers) from persons) then
                    raise integrity_constraint_violation
                        using message = 'value already contained in identifiers';
                end if;
            end loop;
        exception when invalid_parameter_value then
            raise exception
                using message = 'identifiers should be a json array, like [{k,v}, {...}]';
        end;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_person_uniqueness before insert on persons
    for each row execute procedure person_uniqueness();


drop function if exists person_management() cascade;
create or replace function person_management()
    returns trigger as $$
    declare new_pid text;
    declare new_pgrp text;
    declare exp timestamptz;
    declare unam text;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.person_group is null then
                new_pgrp := NEW.person_id || '-group';
                update persons set person_group = new_pgrp where person_id = NEW.person_id;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_description, group_expiry_date)
                    values (new_pgrp, 'primary', 'person', NEW.person_id, 'personal group', NEW.person_expiry_date);
            end if;
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.person_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.person_activated != NEW.person_activated then
                update users set user_activated = NEW.person_activated where person_id = OLD.person_id;
                update groups set group_activated = NEW.person_activated where group_name = OLD.person_group;
            end if;
            if OLD.person_expiry_date != NEW.person_expiry_date then
                new_pgrp := NEW.person_id || '-group';
                update groups set group_expiry_date = NEW.person_expiry_date where group_name = new_pgrp;
                for exp, unam in select user_expiry_date, user_name from users where person_id = NEW.person_id loop
                    if NEW.person_expiry_date < exp then
                        update users set user_expiry_date = NEW.person_expiry_date where person_id = NEW.person_id;
                        update groups set group_expiry_date = NEW.person_expiry_date where group_primary_member = unam;
                    end if;
                end loop;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger person_group_trigger after insert or delete or update on persons
    for each row execute procedure person_management();


create trigger persons_channel_notify after insert or delete or update on persons
    for each row execute procedure notify_listeners();


-- cannot drop this since default value of column depends on it
-- so we always only replace it, unless all tables are dropped
-- in which case we will recreate the default value anyways
create or replace function generate_new_posix_id(table_name text, colum_name text)
    returns int as $$
    declare current_max_id int;
    declare new_id int;
    begin
        execute format('select max(%I) from %I',
            quote_ident(colum_name), quote_ident(table_name))
            into current_max_id;
        if current_max_id is null then
            new_id := 1000;
        elsif current_max_id >= 0 and current_max_id <= 999 then
            new_id := 1000;
        else
            new_id := current_max_id + 1;
        end if;
        return new_id;
    end;
$$ language plpgsql;


-- cannot drop this since default value of column depends on it
-- so we always only replace it, unless all tables are dropped
-- in which case we will recreate the default value anyways
create or replace function generate_new_posix_uid()
    returns int as $$
    declare new_uid int;
    begin
        select generate_new_posix_id('users', 'user_posix_uid') into new_uid;
        return new_uid;
    end;
$$ language plpgsql;


create table if not exists users(
    row_id uuid unique not null default gen_random_uuid(),
    person_id uuid not null references persons (person_id) on delete cascade,
    user_id uuid unique not null default gen_random_uuid(),
    user_activated boolean not null default 't',
    user_expiry_date timestamptz,
    user_name text unique not null primary key,
    user_group text,
    user_posix_uid int unique default generate_new_posix_uid(),
    user_group_posix_gid int check (user_group_posix_gid > 999),
    user_metadata jsonb
);


create trigger users_audit after update or insert or delete on users
    for each row execute procedure update_audit_log_objects();


drop function if exists user_immutability() cascade;
create or replace function user_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise exception using message = 'row_id is immutable';
        elsif OLD.user_id != NEW.user_id then
            raise exception using message = 'user_id is immutable';
        elsif OLD.user_name != NEW.user_name then
            raise exception using message = 'user_name is immutable';
        elsif OLD.user_group != NEW.user_group then
            raise exception using message = 'user_group is immutable';
        elsif OLD.user_posix_uid != NEW.user_posix_uid then
            raise exception using message = 'user_posix_uid is immutable';
        elsif NEW.user_posix_uid is null and NEW.user_posix_uid is not null then
            raise exception using message = 'user_posix_uid cannot be set to null once set';
        elsif NEW.user_group_posix_gid is null and OLD.user_group_posix_gid is not null then
            raise exception using message = 'user_group_posix_gid cannot be set to null once set';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_user_immutability before update on users
    for each row execute procedure user_immutability();


drop function if exists user_management() cascade;
create or replace function user_management()
    returns trigger as $$
    declare new_unam text;
    declare new_ugrp text;
    declare person_exp timestamptz;
    declare user_exp timestamptz;
    declare ugroup_posix_gid int;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.user_group is null then
                new_ugrp := NEW.user_name || '-group';
                update users set user_group = new_ugrp where user_name = NEW.user_name;
                -- if caller provides user_group_posix_gid then set it, otherwise don't
                if NEW.user_group_posix_gid is not null then
                    ugroup_posix_gid := NEW.user_group_posix_gid;
                else
                    ugroup_posix_gid := null;
                end if;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_description, group_posix_gid)
                    values (new_ugrp, 'primary', 'user', NEW.user_name, 'user group', ugroup_posix_gid);
                select person_expiry_date from persons where person_id = NEW.person_id into person_exp;
                if NEW.user_expiry_date is not null then
                    if NEW.user_expiry_date > person_exp then
                        raise exception using message = 'a user cannot expire _after_ the person';
                    end if;
                    user_exp := NEW.user_expiry_date;
                else
                    user_exp := person_exp;
                end if;
                update users set user_expiry_date = user_exp where user_name = NEW.user_name;
                update groups set group_expiry_date = user_exp where group_name = new_ugrp;
            end if;
        elsif (TG_OP = 'DELETE') then
            delete from groups where group_name = OLD.user_group;
        elsif (TG_OP = 'UPDATE') then
            if OLD.user_activated != NEW.user_activated then
                update groups set group_activated = NEW.user_activated where group_name = OLD.user_group;
            end if;
            if OLD.user_expiry_date != NEW.user_expiry_date then
                select person_expiry_date from persons where person_id = NEW.person_id into person_exp;
                if NEW.user_expiry_date > person_exp then
                    raise exception using message = 'a user cannot expire _after_ the person';
                else
                    update groups set group_expiry_date = NEW.user_expiry_date where group_primary_member = NEW.user_name;
                end if;
            end if;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger user_group_trigger after insert or delete or update on users
    for each row execute procedure user_management();

-- cannot drop this since default value of column depends on it
-- so we always only replace it, unless all tables are dropped
-- in which case we will recreate the default value anyways
create or replace function generate_new_posix_gid()
    returns int as $$
    declare new_gid int;
    begin
        select generate_new_posix_id('groups', 'group_posix_gid') into new_gid;
        return new_gid;
    end;
$$ language plpgsql;


create trigger users_channel_notify after insert or delete or update on users
    for each row execute procedure notify_listeners();


create table if not exists groups(
    row_id uuid unique not null default gen_random_uuid(),
    group_id uuid unique not null default gen_random_uuid(),
    group_activated boolean not null default 't',
    group_expiry_date timestamptz,
    group_name text unique not null primary key,
    group_class text check (group_class in ('primary', 'secondary')),
    group_type text check (group_type in ('person', 'user', 'generic', 'web')),
    group_primary_member text,
    group_description text,
    group_posix_gid int unique check (group_posix_gid > 999),
    group_metadata jsonb
);


drop function if exists posix_gid() cascade;
create or replace function posix_gid()
    returns trigger as $$
    begin
        if NEW.group_type not in ('person', 'web') then
            if NEW.group_posix_gid is null then
                -- only auto select if nothing is provided
                -- to enable the transition historical data
                -- risk: possibility to generate holes
                select generate_new_posix_gid() into NEW.group_posix_gid;
            end if;
        else
            NEW.group_posix_gid := null;
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger set_posix_gid before insert on groups
    for each row execute procedure posix_gid();


drop function if exists sync_posix_gid_to_users() cascade;
create or replace function sync_posix_gid_to_users()
    returns trigger as $$
    begin
        if NEW.group_type = 'user' then
            update users set user_group_posix_gid = NEW.group_posix_gid
                where user_group = NEW.group_name;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger sync_user_group_posix_gid after insert on groups
    for each row execute procedure sync_posix_gid_to_users();


create trigger groups_audit after update or insert or delete on groups
    for each row execute procedure update_audit_log_objects();


drop function if exists group_deletion() cascade;
create or replace function group_deletion()
    returns trigger as $$
    declare amount int;
    begin
        if OLD.group_type = 'person' then
            select count(*) from persons where person_group = OLD.group_name into amount;
            if amount = 1 then
                raise exception using
                message = 'person groups are automatically created and deleted based on person objects';
            end if;
        elsif OLD.group_type = 'user' then
            select count(*) from users where user_group = OLD.group_name into amount;
            if amount = 1 then
                raise exception using
                message = 'user groups are automatically created and deleted based on user objects';
            end if;
        end if;
    return old;
    end;
$$ language plpgsql;
create trigger ensure_group_deletion_policy before delete on groups
    for each row execute procedure group_deletion();


drop function if exists group_immutability() cascade;
create or replace function group_immutability()
    returns trigger as $$
    begin
        if OLD.row_id != NEW.row_id then
            raise exception using message = 'row_id is immutable';
        elsif OLD.group_id != NEW.group_id then
            raise exception using message = 'group_id is immutable';
        elsif OLD.group_name != NEW.group_name then
            raise exception using message = 'group_name is immutable';
        elsif OLD.group_class != NEW.group_class then
            raise exception using message = 'group_class is immutable';
        elsif OLD.group_type != NEW.group_type then
            raise exception using message = 'group_type is immutable';
        elsif OLD.group_primary_member != NEW.group_primary_member then
            raise exception using message = 'group_primary_member is immutable';
        elsif OLD.group_posix_gid != NEW.group_posix_gid then
            raise exception using message = 'group_posix_gid is immutable';
        elsif NEW.group_posix_gid is null and OLD.group_posix_gid is not null then
            raise exception using message = 'group_posix_gid cannot be set to null once set';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_group_immutability before update on groups
    for each row execute procedure group_immutability();


drop function if exists group_management() cascade;
create or replace function group_management()
    returns trigger as $$
    declare primary_member_state boolean;
    declare curr_exp timestamptz;
    declare msg text;
    begin
        if OLD.group_activated != NEW.group_activated or
            (OLD.group_activated is null and NEW.group_activated is not null) then
            msg := 'group activation status is managed via';
            if OLD.group_type = 'person' then
                select person_activated from persons
                    where person_group = OLD.group_name
                    into primary_member_state;
                if NEW.group_activated != primary_member_state or primary_member_state is null then
                    raise exception using message = 'person ' || msg || ' persons';
                end if;
            elsif OLD.group_type = 'user' then
                select user_activated from users
                    where user_group = OLD.group_name
                    into primary_member_state;
                if NEW.group_activated != primary_member_state or primary_member_state is null then
                    raise exception using message = 'user ' || msg || ' users';
                end if;
            elsif OLD.group_name in (select institution_group from institutions) then
                select institution_activated from institutions
                    where institution_group = OLD.group_name
                    into primary_member_state;
                if NEW.group_activated != primary_member_state or primary_member_state is null then
                    raise exception using message = 'institution ' || msg || ' institutions';
                end if;
            elsif OLD.group_name in (select project_group from projects) then
                select project_activated from projects
                    where project_group = OLD.group_name
                    into primary_member_state;
                if NEW.group_activated != primary_member_state or primary_member_state is null then
                    raise exception using message = 'project ' || msg || ' projects';
                end if;
            end if;
        elsif OLD.group_expiry_date != NEW.group_expiry_date or
            (OLD.group_expiry_date is null and NEW.group_expiry_date is not null) then
            msg := 'group dates are modified via modifications on';
            if OLD.group_type = 'person' then
                select person_expiry_date from persons
                    where person_id = OLD.group_primary_member::uuid
                    into curr_exp;
                if NEW.group_expiry_date != curr_exp or curr_exp is null then
                    raise exception using message = 'person ' || msg || ' persons';
                end if;
            elsif OLD.group_type = 'user' then
                select user_expiry_date from users
                    where user_name = OLD.group_primary_member
                    into curr_exp;
                if NEW.group_expiry_date != curr_exp or curr_exp is null then
                    raise exception using message = 'user ' || msg || ' users';
                end if;
            elsif OLD.group_name in (select institution_group from institutions) then
                select institution_expiry_date from institutions
                    where institution_group = OLD.group_name
                    into curr_exp;
                if NEW.group_expiry_date != curr_exp or curr_exp is null then
                    raise exception using message = 'institution ' || msg || ' institutions';
                end if;
            elsif OLD.group_name in (select project_group from projects) then
                select project_end_date from projects
                    where project_group = OLD.group_name
                    into curr_exp;
                if NEW.group_expiry_date != curr_exp or curr_exp is null then
                    raise exception using message = 'project ' || msg || ' projects';
                end if;
            end if;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger group_management_trigger before update on groups
    for each row execute procedure group_management();


create trigger groups_channel_notify after insert or delete or update on groups
    for each row execute procedure notify_listeners();


create table if not exists group_memberships(
    group_name text not null references groups (group_name) on delete cascade,
    group_member_name text not null references groups (group_name) on delete cascade,
    start_date timestamptz check(start_date < end_date),
    end_date timestamptz,
    weekdays jsonb, -- {"mon": {"start": "08:00", "end": "17:00"}}
    unique (group_name, group_member_name)
);


drop function if exists group_memberships_constraint_check() cascade;
create or replace function group_memberships_constraint_check()
    returns trigger as $$
    declare group_exp timestamptz;
    declare day text;
    declare start_t timetz;
    declare end_t timetz;
    begin
        if NEW.end_date != OLD.end_date or NEW.end_date is not null then
            select group_expiry_date from groups
                where group_name in (NEW.group_name, OLD.group_name) into group_exp;
            if group_exp is not null and NEW.end_date > group_exp then
                raise exception using message = 'membership end_date cannot exceed group expiry date';
            end if;
        elsif NEW.weekdays != OLD.weekdays or NEW.weekdays is not null then
            for day in select jsonb_object_keys(NEW.weekdays) loop
                if day not in ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun') then
                    raise exception using message = 'unrecognised day ' || day;
                end if;
                start_t := cast(NEW.weekdays->day->>'start' as timetz);
                end_t := cast(NEW.weekdays->day->>'end' as timetz);
                if start_t is null then
                    raise exception using message = 'missing start time';
                elsif end_t is null then
                    raise exception using message = 'missing end time';
                elsif start_t > end_t then
                    raise exception using message = 'start time must be before end time';
                end if;
            end loop;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger group_memberships_constraints before insert or update on group_memberships
    for each row execute procedure group_memberships_constraint_check();


create trigger group_memberships_audit after update or insert or delete on group_memberships
    for each row execute procedure update_audit_log_relations();


drop function if exists group_memberships_immutability() cascade;
create or replace function group_memberships_immutability()
    returns trigger as $$
    begin
        if OLD.group_name != NEW.group_name then
            raise exception using message = 'group_name is immutable';
        elsif OLD.group_member_name != NEW.group_member_name then
            raise exception using message = 'group_member_name is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_group_memberships_immutability before update on group_memberships
    for each row execute procedure group_memberships_immutability();


create or replace view pgiam.first_order_members as
    select
        gm.group_name,
        gm.group_member_name,
        g.group_class,
        g.group_type,
        g.group_primary_member,
        gm.start_date,
        gm.end_date,
        gm.weekdays
    from group_memberships gm, groups g
    where gm.group_member_name = g.group_name;

drop function if exists day_from_ts(timestamptz) cascade;
create or replace function day_from_ts(ts timestamptz)
    returns text as $$
    declare days text[];
    declare out text;
    begin
        days := array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
        select days[(select extract (isodow from ts))] into out;
        return out;
    end;
$$ language plpgsql;

drop function if exists allowed_time(jsonb, timestamptz) cascade;
create or replace function allowed_time(
    weekdays jsonb,
    client_timestamp timestamptz
) returns boolean as $$
    declare day jsonb;
    begin
        if weekdays is null then return 'true'; end if;
        select weekdays->day_from_ts(client_timestamp) into day;
        if client_timestamp::timetz between
            cast(day->>'start' as timetz)
            and cast(day->>'end' as timetz)
        then
            return 'true';
        else
            return 'false';
        end if;
    end;
$$ language plpgsql;


drop function if exists include_membership(
    text, timestamptz, timestamptz, jsonb, text, boolean, timestamptz
) cascade;
create or replace function include_membership(
    source_group text,
    start_date timestamptz,
    end_date timestamptz,
    weekdays jsonb,
    target_group text,
    filter_inactive boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns boolean as $$
    declare source_exp timestamptz;
    declare source_activated boolean;
    declare target_exp timestamptz;
    declare target_activated boolean;
    begin
        if filter_inactive = 'false' then
            return 'true';
        end if;
        if client_timestamp not between
            (current_timestamp at time zone '+14')
            and (current_timestamp at time zone '-12') then
            raise exception using message = 'impossible client_timestamp';
        end if;
        select group_expiry_date, group_activated from groups
            where group_name = source_group into source_exp, source_activated;
        select group_expiry_date, group_activated from groups
            where group_name = target_group into target_exp, target_activated;
        if (
            (source_activated is null or source_activated = 't')
            and (source_exp is null or client_timestamp < source_exp)
            and (start_date is null or client_timestamp > start_date)
            and (end_date is null or client_timestamp < end_date)
            and (target_activated is null or target_activated = 't')
            and (target_exp is null or client_timestamp < target_exp)
            and allowed_time(weekdays, client_timestamp)
        ) then
            return 'true';
        else
            return 'false';
        end if;
    end;
$$ language plpgsql;


-- will have to return time constraints from here
drop table if exists pgiam.members cascade;
create table if not exists pgiam.members(
    group_name text,
    group_member_name text,
    group_class text,
    group_primary_member text,
    start_date timestamptz,
    end_date timestamptz,
    weekdays jsonb
);
drop function if exists group_get_children(text) cascade;
drop function if exists group_get_children(text, boolean) cascade;
drop function if exists group_get_children(text, boolean, timestamptz) cascade;
create or replace function group_get_children(
    parent_group text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns setof pgiam.members as $$
    declare num int;
    declare gn text;
    declare gmn text;
    declare gpm text;
    declare gc text;
    declare sd timestamptz;
    declare ed timestamptz;
    declare wkds jsonb;
    declare row record;
    declare current_member text;
    declare new_current_member text;
    declare recursive_current_member text;
    begin
        create temporary table if not exists sec(
            group_name text,
            group_member_name text,
            group_class text,
            group_primary_member text,
            start_date timestamptz,
            end_date timestamptz,
            weekdays jsonb
        ) on commit drop;
        create temporary table if not exists mem(
            group_name text,
            group_member_name text,
            group_class text,
            group_primary_member text,
            start_date timestamptz,
            end_date timestamptz,
            weekdays jsonb
        ) on commit drop;
        delete from sec;
        delete from mem;
        for gn, gmn, gc, gpm, sd, ed, wkds in
            select group_name, group_member_name, group_class,
                   group_primary_member, start_date, end_date, weekdays
            from pgiam.first_order_members where group_name = parent_group
            and group_class = 'primary' loop
            -- add option to pass parent here too
            if include_membership(gn, sd, ed, wkds, gmn, filter_memberships, client_timestamp) = 'true' then
                insert into mem values (gn, gmn, gc, gpm, sd, ed, wkds);
            end if;
        end loop;
        for gn, gmn, gc, gpm, sd, ed, wkds in
            select group_name, group_member_name, group_class,
                   group_primary_member, start_date, end_date, weekdays
            from pgiam.first_order_members where group_name = parent_group
            and group_class = 'secondary' loop
            if include_membership(gn, sd, ed, wkds, gmn, filter_memberships, client_timestamp) = 'true' then
                insert into sec values (gn, gmn, gc, gpm, sd, ed, wkds);
            end if;
        end loop;
        select count(*) from sec into num;
        while num > 0 loop
            select group_member_name from sec limit 1 into current_member;
            select group_name, group_member_name, group_class,
                   group_primary_member, start_date, end_date, weekdays
                from sec where group_member_name = current_member
                into gn, gmn, gc, gpm, sd, ed, wkds;
            if gc = 'primary' then
                if include_membership(gn, sd, ed, wkds, gmn, filter_memberships, client_timestamp) = 'true' then
                    insert into mem values (gn, gmn, gc, gpm, sd, ed, wkds);
                end if;
            elsif gc = 'secondary' then
                if include_membership(gn, sd, ed, wkds, gmn, filter_memberships, client_timestamp) = 'true' then
                    insert into mem values (gn, gmn, gc, gpm, sd, ed, wkds);
                end if;
                new_current_member := gmn;
                -- first add primary groups to members, and remove them from sec
                for gn, gmn, gc, gpm, sd, ed, wkds in
                    select group_name, group_member_name, group_class,
                           group_primary_member, start_date, end_date, weekdays
                    from pgiam.first_order_members where group_name = new_current_member loop
                    if gc = 'primary' then
                        if include_membership(gn, sd, ed, wkds, gmn, filter_memberships, client_timestamp) = 'true' then
                            insert into mem values (gn, gmn, gc, gpm, sd, ed, wkds);
                        end if;
                        delete from sec where group_member_name = gmn;
                    else
                        recursive_current_member := gmn;
                        if include_membership(gn, sd, ed, wkds, gmn, filter_memberships, client_timestamp) = 'true' then
                            insert into mem values (gn, gmn, gc, gpm, sd, ed, wkds);
                        end if;
                        -- this new secondary member can have both primary and seconday
                        -- members itself, but just add all its members to sec, and we will handle them
                        for gn, gmn, gc, gpm, sd, ed, wkds in
                            select group_name, group_member_name, group_class,
                                   group_primary_member, start_date, end_date, weekdays
                            from pgiam.first_order_members where group_name = recursive_current_member loop
                            if include_membership(gn, sd, ed, wkds, gmn, filter_memberships, client_timestamp) = 'true' then
                                insert into sec values (gn, gmn, gc, gpm, sd, ed, wkds);
                            end if;
                        end loop;
                    end if;
                end loop;
            end if;
            delete from sec where group_member_name = current_member;
            select count(*) from sec into num;
        end loop;
        return query select * from mem order by group_primary_member;
    end;
$$ language plpgsql;


-- consider allowing filtering on constraints here
drop table if exists pgiam.memberships cascade; -- return type
create table if not exists pgiam.memberships(
    member_name text,
    member_group_name text,
    start_date timestamptz,
    end_date timestamptz,
    weekdays jsonb
);
drop function if exists group_get_parents(text) cascade; -- changed signature
drop function if exists group_get_parents(text, boolean) cascade;
create or replace function group_get_parents(
    child_group text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns setof pgiam.memberships as $$
    declare num int;
    declare mgn text;
    declare mn text;
    declare gn text;
    declare sd timestamptz;
    declare ed timestamptz;
    declare grp_exp timestamptz;
    declare grp_actived boolean;
    declare wkds jsonb;
    begin
        create temporary table if not exists candidates(
            member_name text,
            member_group_name text,
            start_date timestamptz,
            end_date timestamptz,
            weekdays jsonb
        ) on commit drop;
        create temporary table if not exists parents(
            member_name text,
            member_group_name text,
            start_date timestamptz,
            end_date timestamptz,
            weekdays jsonb
        ) on commit drop;
        delete from candidates;
        delete from parents;
        for gn, sd, ed, wkds in select group_name, start_date, end_date, weekdays
            from pgiam.first_order_members where group_member_name = child_group loop
            -- also add the child to the filter
            if include_membership(gn, sd, ed, wkds, child_group, filter_memberships, client_timestamp) = 'true' then
                insert into candidates values (child_group, gn, sd, ed, wkds);
            end if;
        end loop;
        select count(*) from candidates into num;
        while num > 0 loop
            select member_name, member_group_name, start_date, end_date, weekdays
                from candidates limit 1 into mn, mgn, sd, ed, wkds;
            insert into parents values (mn, mgn, sd, ed, wkds);
            delete from candidates where member_name = mn and member_group_name = mgn;
            -- now check if the current candidate has parents
            -- so we find all recursive memberships
            for gn, sd, ed, wkds in select group_name, start_date, end_date, weekdays
                from pgiam.first_order_members where group_member_name = mgn loop
                if include_membership(gn, sd, ed, wkds, child_group, filter_memberships, client_timestamp) = 'true' then
                    insert into candidates values (mgn, gn, sd, ed, wkds);
                end if;
            end loop;
            select count(*) from candidates into num;
        end loop;
        return query select * from parents;
    end;
$$ language plpgsql;


drop function if exists group_memberships_check_dag_requirements() cascade;
create or replace function group_memberships_check_dag_requirements()
    returns trigger as $$
    declare response text;
    begin
        -- Ensure we have only Directed Acylic Graphs, where primary groups are only allowed in leaves
        -- if a any of the groups are currently inactive or expired, the membership cannot be created
        -- also disallow any self-referential entries
        assert NEW.group_name != NEW.group_member_name, 'groups cannot be members of themselves';
        response := NEW.group_name || ' is a primary group - which cannot have members other than its primary member';
        assert (select NEW.group_name in
            (select group_name from groups where group_class = 'primary')) = 'f', response;
        assert (select group_activated from groups where group_name = NEW.group_name) = 't',
            NEW.group_name || ' is deactived - to use it in new group memberships it must be active';
        assert (select group_activated from groups where group_name = NEW.group_member_name) = 't',
            NEW.group_member_name || ' is deactived - to use it in new group memberships it must be active';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_name) >= current_date,
            NEW.group_name || ' has expired - to use it in new group memberships its expiry date must be later than the current date';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_member_name) >= current_date,
            NEW.group_member_name || ' has expired - to use it in new group memberships its expiry date must be later than the current date';
        response := 'Making ' || NEW.group_member_name || ' a member of ' || NEW.group_name
                    || ' would create a cyclical graph which is not allowed';
        assert (select NEW.group_member_name in
            (select member_group_name from group_get_parents(NEW.group_name))) = 'f', response;
        response := NEW.group_member_name || ' is already a member of ' || NEW.group_name;
        assert (select NEW.group_member_name in
            (select group_member_name from group_get_children(NEW.group_name))) = 'f', response;
        return new;
    end;
$$ language plpgsql;
create trigger group_memberships_dag_requirements_trigger before insert on group_memberships
    for each row execute procedure group_memberships_check_dag_requirements();


create trigger group_memberships_channel_notify after insert or delete or update on group_memberships
    for each row execute procedure notify_listeners();


create table if not exists group_moderators(
    group_name text not null references groups (group_name) on delete cascade,
    group_moderator_name text not null references groups (group_name) on delete cascade,
    unique (group_name, group_moderator_name)
);


create trigger group_moderators_audit after update or insert or delete on group_moderators
    for each row execute procedure update_audit_log_relations();


drop function if exists group_moderators_immutability() cascade;
create or replace function group_moderators_immutability()
    returns trigger as $$
    begin
        if OLD.group_name != NEW.group_name then
            raise exception using message = 'group_name is immutable';
        elsif OLD.group_member_name != NEW.group_member_name then
            raise exception using message = 'group_member_name is immutable';
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_group_moderators_immutability before update on group_moderators
    for each row execute procedure group_moderators_immutability();


drop function if exists group_moderators_check_dag_requirements() cascade;
create or replace function group_moderators_check_dag_requirements()
    returns trigger as $$
    declare response text;
    declare new_grp text;
    declare new_mod text;
    begin
        response := NEW.group_name || ' is deactived - to use it in new group moderators it must be active';
        assert (select group_activated from groups where group_name = NEW.group_name) = 't', response;
        response := NEW.group_moderator_name || ' is deactived - to use it in new group moderators it must be active';
        assert (select group_activated from groups where group_name = NEW.group_moderator_name) = 't', response;
        response := NEW.group_name || ' has expired - to use it in new group moderators its expiry date must be later than the current date';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_name) >= current_date, response;
        response := NEW.group_moderator_name || ' has expired - to use it in new group moderators its expiry date must be later than the current date';
        assert (select case when group_expiry_date is not null then group_expiry_date else current_date end
                from groups where group_name = NEW.group_moderator_name) >= current_date, response;
        response := NEW.group_name || ' is a primary group, and cannot be moderated';
        assert (select group_class from groups where group_name = NEW.group_name) = 'secondary', response;
        if NEW.group_moderator_name != NEW.group_name then
            -- self-moderation is allowed
            response := 'Making ' || NEW.group_name || ' a moderator of '
                        || NEW.group_moderator_name || ' will create a cyclical graph - which is not allowed.';

            assert (select count(*) from group_moderators
                    where group_name = NEW.group_moderator_name
                    and group_moderator_name = NEW.group_name) = 0, response;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger group_memberships_dag_requirements_trigger after insert on group_moderators
    for each row execute procedure group_moderators_check_dag_requirements();


create trigger group_moderators_channel_notify after update or insert or delete on group_moderators
    for each row execute procedure notify_listeners();


drop function if exists get_memberships(text) cascade;
drop function if exists get_memberships(text, text) cascade;
drop function if exists get_memberships(text, text, boolean) cascade;
create or replace function get_memberships(
    member text,
    grp text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns json as $$
    declare data json;
    begin
        execute format(
            'select json_agg(json_build_object(
                $1, member_name,
                $2, member_group_name,
                $3, group_activated,
                $4, group_expiry_date,
                $5, json_build_object($6, start_date, $7, end_date, $8, weekdays)
            ))
            from (select member_name, member_group_name, start_date, end_date, weekdays
                  from group_get_parents($9, $10, $11)
                  union select %s, %s, null, null, null)a
            join (select group_name, group_activated, group_expiry_date from groups)b
            on a.member_group_name = b.group_name',
            quote_literal(member), quote_literal(grp)
        )
            using 'member_name', 'member_group', 'group_activated', 'group_expiry_date',
                  'constraints', 'start_date', 'end_date', 'weekdays',
                  grp, filter_memberships, client_timestamp
            into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists person_groups(text) cascade;
drop function if exists person_groups(text, boolean) cascade;
drop function if exists person_groups(text, boolean, timestamptz) cascade;
create or replace function person_groups(
    person_id text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns json as $$
    declare pid uuid;
    declare pgrp text;
    declare res json;
    declare pgroups json;
    declare data json;
    begin
        pid := $1::uuid;
        assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
        select person_group from persons where persons.person_id = pid into pgrp;
        select get_memberships(person_id, pgrp, filter_memberships, client_timestamp) into pgroups;
        select json_build_object(
            'person_id', person_id,
            'person_groups', pgroups
        ) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists user_groups(text) cascade;
drop function if exists user_groups(text, boolean) cascade;
drop function if exists user_groups(text, boolean, timestamptz) cascade;
create or replace function user_groups(
    user_name text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns json as $$
    declare ugrp text;
    declare ugroups json;
    declare exst boolean;
    declare data json;
    begin
        execute format('select exists(select 1 from users where users.user_name = $1)') using $1 into exst;
        assert exst = 't', 'user does not exist';
        select user_group from users where users.user_name = $1 into ugrp;
        select get_memberships(user_name, ugrp, filter_memberships, client_timestamp) into ugroups;
        select json_build_object(
            'user_name', user_name,
            'user_groups', ugroups
        ) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists user_moderators(text);
create or replace function user_moderators(user_name text)
    returns json as $$
    declare exst boolean;
    declare ugrps json;
    declare mods json;
    declare data json;
    begin
        execute format('select exists(select 1 from users where users.user_name = $1)') using $1 into exst;
        assert exst = 't', 'user does not exist';
        select user_groups->>'user_groups' from user_groups(user_name) into ugrps;
        if ugrps is null then
            mods := '[]'::json;
        else
            select json_agg(group_name) from group_moderators
                where group_moderator_name in
                (select json_array_elements(user_groups->'user_groups')->>'member_group'
                from user_groups(user_name)) into mods;
        end if;
        select json_build_object('user_name', user_name, 'user_moderators', mods) into data;
        return data;
    end;
$$ language plpgsql;

-- add optional params for adding constraints here
drop function if exists group_member_add(text, text) cascade;
drop function if exists group_member_add(text, text, timestamptz, timestamptz) cascade;
drop function if exists group_member_add(text, text, timestamptz, timestamptz, jsonb) cascade;
create or replace function group_member_add(
    group_name text,
    member text,
    start_date timestamptz default null,
    end_date timestamptz default null,
    weekdays jsonb default null
) returns json as $$
    declare gnam text;
    declare unam text;
    declare mem text;
    begin
        gnam := $1;
        assert (select exists(select 1 from groups where groups.group_name = gnam)) = 't', 'group does not exist';
        if member in (select groups.group_name from groups) then
            mem := member;
        else
            begin
                assert (select exists(select 1 from persons where persons.person_id = member::uuid)) = 't';
                select person_group from persons where persons.person_id = member::uuid into mem;
            exception when others or assert_failure then
                begin
                    assert (select exists(select 1 from users where users.user_name = member)) = 't';
                    select user_group from users where users.user_name = member into mem;
                exception when others or assert_failure then
                    return json_build_object('message', 'could not add member');
                end;
            end;
        end if;
        execute format('insert into group_memberships values ($1, $2, $3, $4, $5)')
            using gnam, mem, start_date, end_date, weekdays;
        return json_build_object('message', 'member added');
    end;
$$ language plpgsql;


drop function if exists group_member_remove(text, text) cascade;
create or replace function group_member_remove(group_name text, member text)
    returns json as $$
    declare gnam text;
    declare unam text;
    declare mem text;
    begin
        gnam := $1;
        assert (select exists(select 1 from groups where groups.group_name = gnam)) = 't', 'group does not exist';
        if member in (select groups.group_name from groups) then
            mem := member;
        else
            begin
                assert (select exists(select 1 from persons where persons.person_id = member::uuid)) = 't';
                select person_group from persons where persons.person_id = member::uuid into mem;
            exception when others or assert_failure then
                begin
                    assert (select exists(select 1 from users where users.user_name = member)) = 't';
                    select user_group from users where users.user_name = member into mem;
                exception when others or assert_failure then
                    return json_build_object('message', 'could not remove member');
                end;
            end;
        end if;
        execute format('delete from group_memberships where group_name = $1 and group_member_name = $2')
            using gnam, mem;
        return json_build_object('message', 'member removed');
    end;
$$ language plpgsql;


drop function if exists grp_mems(text) cascade;
drop function if exists grp_mems(text, boolean) cascade;
drop function if exists grp_mems(text, boolean, timestamptz) cascade;
create or replace function grp_mems(
    gn text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns table(
        group_name text,
        group_member_name text,
        group_primary_member text,
        group_activated boolean,
        group_expiry_date timestamptz,
        start_date timestamptz,
        end_date timestamptz,
        weekdays jsonb
    ) as $$
    select a.group_name,
           a.group_member_name,
           a.group_primary_member,
           b.group_activated,
           b.group_expiry_date,
           a.start_date,
           a.end_date,
           a.weekdays
    from (select group_name, group_member_name, group_primary_member, start_date, end_date, weekdays
          from group_get_children(gn, filter_memberships, client_timestamp))a
    join (select group_name, group_activated, group_expiry_date from groups)b
    on a.group_name = b.group_name
$$ language sql;


drop function if exists group_members(text) cascade;
drop function if exists group_members(text, boolean) cascade;
create or replace function group_members(
    group_name text,
    filter_memberships boolean default 'false',
    client_timestamp timestamptz default current_timestamp
) returns json as $$
    declare direct_data json;
    declare transitive_data json;
    declare primary_data json;
    declare data json;
    begin
        assert (select exists(select 1 from groups where groups.group_name = $1)) = 't', 'group does not exist';
        select json_agg(distinct group_primary_member) from group_get_children($1, filter_memberships, client_timestamp)
            where group_primary_member is not null into primary_data;
        select json_agg(json_build_object(
            'group', gm.group_name,
            'group_member', gm.group_member_name,
            'primary_member', gm.group_primary_member,
            'activated', gm.group_activated,
            'expiry_date', gm.group_expiry_date,
            'constraints', json_build_object(
                'start_date', gm.start_date,
                'end_date', gm.end_date,
                'weekdays', gm.weekdays
            )
        )) from grp_mems($1, filter_memberships, client_timestamp) gm
            where gm.group_name = $1 into direct_data;
        select json_agg(json_build_object(
            'group', gm.group_name,
            'group_member', gm.group_member_name,
            'primary_member', gm.group_primary_member,
            'activated', gm.group_activated,
            'expiry_date', gm.group_expiry_date,
            'constraints', json_build_object(
                'start_date', gm.start_date,
                'end_date', gm.end_date,
                'weekdays', gm.weekdays
            )
        )) from grp_mems($1, filter_memberships, client_timestamp) gm
            where gm.group_name != $1 into transitive_data;
        select json_build_object(
            'group_name', group_name,
            'direct_members', direct_data,
            'transitive_members', transitive_data,
            'ultimate_members', primary_data) into data;
        return data;
    end;
$$ language plpgsql;


drop function if exists group_moderators(text) cascade;
create or replace function group_moderators(group_name text)
    returns json as $$
    declare data json;
    begin
        assert (select exists(select 1 from groups where groups.group_name = $1)) = 't', 'group does not exist';
        select json_agg(json_build_object(
            'moderator', a.group_moderator_name,
            'activated', b.group_activated,
            'expiry_date', b.group_expiry_date)) from
        (select gm.group_name, gm.group_moderator_name
            from group_moderators gm where gm.group_name = $1)a join
        (select g.group_name, g.group_activated, g.group_expiry_date
            from groups g)b on a.group_name = b.group_name into data;
        return json_build_object('group_name', group_name, 'group_moderators', data);
    end;
$$ language plpgsql;
