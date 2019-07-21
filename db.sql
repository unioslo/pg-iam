
create extension pgcrypto;


drop table if exists audit_log;
create table if not exists audit_log(
    event_time timestamptz default now(),
    table_name text not null,
    row_id uuid not null,
    column_name text not null,
    old_data text,
    new_data text
);


create or replace function update_audit_log()
    returns trigger as $$
    declare old_data text;
    declare new_data text;
    declare colname text;
    declare table_name text;
    begin
        table_name := TG_TABLE_NAME::text;
        for colname in execute
            format('select c.column_name::text
                    from pg_catalog.pg_statio_all_tables as st
                    inner join information_schema.columns c
                    on c.table_schema = st.schemaname and c.table_name = st.relname
                    left join pg_catalog.pg_description pgd
                    on pgd.objoid = st.relid
                    and pgd.objsubid = c.ordinal_position
                    where st.relname = $1') using table_name
        loop
            execute format('select ($1).%s::text', colname) using OLD into old_data;
            execute format('select ($1).%s::text', colname) using NEW into new_data;
            if old_data != new_data then
                insert into audit_log (table_name, row_id, column_name, old_data, new_data)
                    values (table_name, OLD.row_id, colname, old_data, new_data);
            end if;
        end loop;
        return new;
    end;
$$ language plpgsql;


drop table if exists persons cascade;
create table if not exists persons(
    row_id uuid unique not null default gen_random_uuid(),
    person_id uuid unique not null default gen_random_uuid(),
    person_activated boolean not null default 't',
    person_expiry_date date,
    person_group text,
    given_names text not null,
    surname text not null,
    national_id_number text,
    passport_number text,
    password text,
    otp_secret text,
    person_metadata json
);


create trigger persons_audit after update on persons
    for each row execute procedure update_audit_log();


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


create or replace function person_management()
    returns trigger as $$
    declare new_pid text;
    declare new_pgrp text;
    declare exp date;
    declare unam text;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.person_group is null then
                new_pgrp := NEW.person_id || '-group';
                update persons set person_group = new_pgrp where person_id = NEW.person_id;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_desciption, group_expiry_date)
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


drop table if exists users cascade;
create table if not exists users(
    row_id uuid unique not null default gen_random_uuid(),
    person_id uuid not null references persons (person_id) on delete cascade,
    user_id uuid unique not null default gen_random_uuid(),
    user_activated boolean not null default 't',
    user_expiry_date date,
    user_name text unique not null,
    user_group text,
    user_metadata json
);


create trigger users_audit after update on users
    for each row execute procedure update_audit_log();


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
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_user_immutability before update on users
    for each row execute procedure user_immutability();


create or replace function user_management()
    returns trigger as $$
    declare new_unam text;
    declare new_ugrp text;
    declare person_exp date;
    declare user_exp date;
    begin
        if (TG_OP = 'INSERT') then
            if OLD.user_group is null then
                new_ugrp := NEW.user_name || '-group';
                update users set user_group = new_ugrp where user_name = NEW.user_name;
                insert into groups (group_name, group_class, group_type, group_primary_member, group_desciption)
                    values (new_ugrp, 'primary', 'user', NEW.user_name, 'user group');
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


drop table if exists groups cascade;
create table if not exists groups(
    row_id uuid unique not null default gen_random_uuid(),
    group_id uuid unique not null default gen_random_uuid(),
    group_activated boolean not null default 't',
    group_expiry_date date,
    group_name text unique not null,
    group_class text check (group_class in ('primary', 'secondary')),
    group_type text check (group_type in ('person', 'user', 'generic')),
    group_primary_member text,
    group_desciption text,
    group_metadata json
);


create trigger groups_audit after update on groups
    for each row execute procedure update_audit_log();


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
        end if;
    return new;
    end;
$$ language plpgsql;
create trigger ensure_group_immutability before update on groups
    for each row execute procedure group_immutability();


create or replace function group_management()
    returns trigger as $$
    declare primary_member_state boolean;
    declare curr_user_exp date;
    begin
        if OLD.group_activated != NEW.group_activated then
            if OLD.group_type = 'person' then
                select person_activated from persons where person_group = OLD.group_name into primary_member_state;
                if NEW.group_activated != primary_member_state then
                    raise exception using message = 'person groups can only be deactived by deactivating persons';
                end if;
            elsif OLD.group_type = 'user' then
                select user_activated from users where user_group = OLD.group_name into primary_member_state;
                if NEW.group_activated != primary_member_state then
                    raise exception using message = 'user groups can only be deactived by deactivating users';
                end if;
            end if;
        elsif OLD.group_expiry_date != NEW.group_expiry_date then
            select user_expiry_date from users where user_name = NEW.group_primary_member into curr_user_exp;
            if NEW.group_expiry_date != curr_user_exp then
                raise exception using message = 'primary group dates are modified via modifications on persons/users';
            end if;
        end if;
        return new;
    end;
$$ language plpgsql;
create trigger group_management_trigger before update on groups
    for each row execute procedure group_management();


drop table if exists group_memberships cascade;
create table if not exists group_memberships(
    group_name text not null references groups (group_name) on delete cascade,
    group_member_name text not null references groups (group_name) on delete cascade,
    unique (group_name, group_member_name)
);


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


create view first_order_members as
    select gm.group_name, gm.group_member_name, g.group_class, g.group_type, g.group_primary_member
    from group_memberships gm, groups g
    where gm.group_member_name = g.group_name;


create table if not exists members(group_name text, group_member_name text, group_class text, group_primary_member text);
create or replace function group_get_children(parent_group text)
    returns setof members as $$
    declare num int;
    declare gn text;
    declare gmn text;
    declare gpm text;
    declare gc text;
    declare row record;
    declare current_member text;
    declare new_current_member text;
    declare recursive_current_member text;
    begin
        create temporary table if not exists sec(group_name text, group_member_name text, group_class text, group_primary_member text) on commit drop;
        create temporary table if not exists mem(group_name text, group_member_name text, group_class text, group_primary_member text) on commit drop;
        delete from sec;
        delete from mem;
        select count(*) from first_order_members where group_name = parent_group
            and group_class = 'secondary' into num;
        if num = 0 then
            return query execute format ('select group_name, group_member_name, group_class, group_primary_member
                from first_order_members where group_name = $1 order by group_primary_member') using parent_group;
        else
            for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                from first_order_members where group_name = parent_group
                and group_class = 'primary' loop
                insert into mem values (gn, gmn, gc, gpm);
            end loop;
            for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                from first_order_members where group_name = parent_group
                and group_class = 'secondary' loop
                insert into sec values (gn, gmn, gc, gpm);
            end loop;
            select count(*) from sec into num;
            while num > 0 loop
                select group_member_name from sec limit 1 into current_member;
                select group_name, group_member_name, group_class, group_primary_member
                    from sec where group_member_name = current_member
                    into gn, gmn, gc, gpm;
                if gc = 'primary' then
                    insert into mem values (gn, gmn, gc, gpm);
                elsif gc = 'secondary' then
                    insert into mem values (gn, gmn, gc, gpm);
                    new_current_member := gmn;
                    -- first add primary groups to members, and remove them from sec
                    for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                        from first_order_members where group_name = new_current_member loop
                        if gc = 'primary' then
                            insert into mem values (gn, gmn, gc, gpm);
                            delete from sec where group_member_name = gmn;
                        else
                            recursive_current_member := gmn;
                            -- this new secondary member can have both primary and seconday
                            -- members itself, but just add all its members to sec, and we will handle them
                            for gn, gmn, gc, gpm in select group_name, group_member_name, group_class, group_primary_member
                                from first_order_members where group_name = recursive_current_member loop
                                insert into sec values (gn, gmn, gc, gpm);
                            end loop;
                        end if;
                    end loop;
                end if;
                delete from sec where group_member_name = current_member;
                select count(*) from sec into num;
            end loop;
            return query select * from mem order by group_primary_member;
        end if;
    end;
$$ language plpgsql;


create table if not exists memberships(member_name text, member_group_name text);
create or replace function group_get_parents(child_group text)
    returns setof memberships as $$
    declare num int;
    declare mgn text;
    declare mn text;
    declare gn text;
    begin
        create temporary table if not exists candidates(member_name text, member_group_name text) on commit drop;
        create temporary table if not exists parents(member_name text, member_group_name text) on commit drop;
        delete from candidates;
        delete from parents;
        for gn in select group_name from first_order_members where group_member_name = child_group loop
            insert into candidates values (child_group, gn);
        end loop;
        select count(*) from candidates into num;
        while num > 0 loop
            select member_name, member_group_name from candidates limit 1 into mn, mgn;
            insert into parents values (mn, mgn);
            delete from candidates where member_name = mn and member_group_name = mgn;
            -- now check if the current candidate has parents
            -- so we find all recursive memberships
            for gn in select group_name from first_order_members where group_member_name = mgn loop
                insert into candidates values (mgn, gn);
            end loop;
            select count(*) from candidates into num;
        end loop;
        return query select * from parents;
    end;
$$ language plpgsql;


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
        assert (select NEW.group_member_name in
            (select group_name from group_get_children(NEW.group_name) where group_name != NEW.group_name)) = 'f', response;
        return new;
    end;
$$ language plpgsql;
create trigger group_memberships_dag_requirements_trigger before insert on group_memberships
    for each row execute procedure group_memberships_check_dag_requirements();


drop table if exists group_moderators cascade;
create table if not exists group_moderators(
    group_name text not null references groups (group_name) on delete cascade,
    group_moderator_name text not null references groups (group_name) on delete cascade,
    unique (group_name, group_moderator_name)
);


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


create or replace function group_moderators_check_dag_requirements()
    returns trigger as $$
    declare response text;
    declare new_grp text;
    declare new_mod text;
    begin
        assert NEW.group_name != NEW.group_moderator_name, 'groups cannot be moderators of themselves';
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
        response := 'Making ' || NEW.group_name || ' a moderator of '
                   || NEW.group_moderator_name || ' will create a cyclical graph - which is not allowed.';
        assert (select count(*) from group_moderators
                where group_name = NEW.group_moderator_name
                and group_moderator_name = NEW.group_name) = 0, response;
        return new;
    end;
$$ language plpgsql;
create trigger group_memberships_dag_requirements_trigger after insert on group_moderators
    for each row execute procedure group_moderators_check_dag_requirements();


drop table if exists capabilities cascade;
create table if not exists capabilities(
    row_id uuid unique not null default gen_random_uuid(),
    capability_id uuid unique not null default gen_random_uuid(),
    capability_type text unique not null,
    capability_default_claims json,
    capability_required_groups text[] not null,
    capability_group_match_method text not null check (capability_group_match_method in ('exact', 'wildcard')),
    capability_lifetime int not null check (capability_lifetime > 0), -- minutes
    capability_description text not null,
    capability_expiry_date date
);


create trigger capabilities_audit after update on capabilities
    for each row execute procedure update_audit_log();


create or replace function capabilities_immutability()
    returns trigger as $$
    begin
        assert OLD.row_id = NEW.row_id, 'row_id is immutable';
        assert OLD.capability_id = NEW.capability_id, 'capability_id is immutable';
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_immutability before update on capabilities
    for each row execute procedure capabilities_immutability();


create or replace function capabilities_group_check()
    returns trigger as $$
    declare new_grps text[];
    declare new_grp text;
    declare num int;
    begin
        for new_grp in select unnest(NEW.capability_required_groups) loop
            select count(*) from groups where group_name like '%' || new_grp || '%' into num;
            assert num > 0, new_grp || ' does not exist';
        end loop;
        return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_group_check before insert or update on capabilities
    for each row execute procedure capabilities_group_check();


drop table if exists capabilities_grants;
create table capabilities_grants(
    row_id uuid unique not null default gen_random_uuid(),
    capability_id uuid references capabilities (capability_id) on delete cascade,
    capability_type text references capabilities (capability_type),
    capability_http_method text not null check (capability_http_method in ('OPTIONS', 'HEAD', 'GET', 'PUT', 'POST', 'PATCH', 'DELETE')),
    capability_uri_pattern text not null -- string or regex referring to a set of resources
);


create trigger capabilities_grants_audit after update on capabilities_grants
    for each row execute procedure update_audit_log();


create or replace function capabilities_grants_immutability()
    returns trigger as $$
    begin
        assert OLD.row_id = NEW.row_id, 'row_id is immutable';
        assert OLD.capability_id = NEW.capability_id, 'capability_id is immutable';
    return new;
    end;
$$ language plpgsql;
create trigger ensure_capabilities_grants_immutability before update on capabilities_grants
    for each row execute procedure capability_grants_immutability();


-- RPCs
-- returns full graph info, including transitive group memberships
-- callers who are only interested in leaf info (the list of memberships
-- regardless of structure) can look at the 'member_group' key in the group list
-- e.g. groups: [{..., member_group: g1}, {..., member_group: g2}, ...]


create or replace function capability_grants(capability_type text)
    returns json as $$
    declare data json;
    begin
        assert (select exists(select 1 from capabilities where capabilities.capability_type = $1)) = 't',
            'capability_type does not exist';
        select json_agg(json_build_object(
                    'http_method', capability_http_method,
                    'uri_pattern', capability_uri_pattern))
            from capabilities_grants where capabilities_grants.capability_type = $1 into data;
        return data;
    end;
$$ language plpgsql;


create or replace function grp_cpbts(grp text, grants boolean default 'f')
    returns json as $$
    declare ctype text;
    declare cgrps text[];
    declare rgrp text;
    declare reg text;
    declare matches boolean;
    declare grant_data json;
    declare data json;
    begin
        assert (select exists(select 1 from groups where group_name = grp)) = 't', 'group does not exist';
        create temporary table if not exists cpb(ct text unique not null) on commit drop;
        delete from cpb;
        -- exact group matches
        for ctype in select capability_type from capabilities
            where capability_group_match_method = 'exact'
            and array[grp] && capability_required_groups loop
            insert into cpb values (ctype);
        end loop;
        -- wildcard group matches
        for ctype, cgrps in select capability_type, capability_required_groups from capabilities
            where capability_group_match_method = 'wildcard' loop
            for rgrp in select unnest(cgrps) loop
                reg := '.*' || rgrp || '.*';
                if grp ~ reg then
                    begin
                        insert into cpb values (ctype);
                    exception when unique_violation then
                        null;
                    end;
                end if;
            end loop;
        end loop;
        select json_agg(ct) from cpb into data;
        if grants = 'f' then
            return json_build_object('group', grp, 'capabilities', data);
        else
            select json_agg(json_build_object(capability_type, capability_grants(capability_type)))
                from capabilities where capability_type in (select * from cpb) into grant_data;
            return json_build_object('group', grp, 'capabilities', data, 'grants', grant_data);
        end if;
    end;
$$ language plpgsql;


create or replace function get_memberships(grp text)
    returns json as $$
    declare data json;
    begin
        execute format(
            'select json_agg(json_build_object(
                $1, member_name,
                $2, member_group_name,
                $3, group_activated,
                $4, group_expiry_date))
            from (select member_name, member_group_name from group_get_parents($5))a
            join (select group_name, group_activated, group_expiry_date from groups)b
            on a.member_group_name = b.group_name')
            using 'member_name', 'member_group', 'group_activated', 'group_expiry_date', grp
            into data;
        return data;
    end;
$$ language plpgsql;


create or replace function person_groups(person_id text)
    returns json as $$
    declare pid uuid;
    declare pgrp text;
    declare res json;
    declare pgroups json;
    declare data json;
    begin
        pid := $1::uuid;
        assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
        select person_group from persons where persons.person_id = pid into pgrp;
        select get_memberships(pgrp) into pgroups;
        select json_build_object('person_group', pgrp, 'groups', pgroups) into data;
        return data;
    end;
$$ language plpgsql;


create or replace function person_capabilities(person_id text, grants boolean default 'f')
    returns json as $$
    declare pid uuid;
    declare pgrp text;
    declare data json;
    begin
        pid := $1::uuid;
        assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
        select person_group from persons where persons.person_id = pid into pgrp;
        select json_agg(grp_cpbts(member_group_name, grants)) from group_get_parents(pgrp) into data;
        return data;
    end;
$$ language plpgsql;


-- person_access -> for person group, and all users, list all groups, capabilities, grants


create or replace function user_groups(user_name text)
    returns json as $$
    declare ugrp text;
    declare ugroups json;
    declare exst boolean;
    declare data json;
    begin
        execute format('select exists(select 1 from users where users.user_name = $1)') using $1 into exst;
        assert exst = 't', 'user does not exist';
        select user_group from users where users.user_name = $1 into ugrp;
        select get_memberships(ugrp) into ugroups;
        select json_build_object('user_group', ugrp, 'groups', ugroups) into data;
        return data;
    end;
$$ language plpgsql;


create or replace function user_capabilities(user_name text, grants boolean default 'f')
    returns json as $$
    declare ugrp text;
    declare exst boolean;
    declare data json;
    begin
        execute format('select exists(select 1 from users where users.user_name = $1)') using $1 into exst;
        assert exst = 't', 'user does not exist';
        select user_group from users where users.user_name = $1 into ugrp;
        select json_agg(grp_cpbts(member_group_name, grants)) from group_get_parents(ugrp) into data;
        return data;
    end;
$$ language plpgsql;


create or replace function group_member_add(group_name text, person_id text default null, user_name text default null)
    returns json as $$
    declare pgrp text;
    declare ugrp text;
    declare gnam text;
    declare pid text;
    declare unam text;
    begin
        gnam := $1;
        pid := $2::uuid;
        unam := $3;
        assert (select exists(select 1 from groups where groups.group_name = gnam)) = 't', 'group does not exist';
        if person_id is not null then
            assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
            select person_group from persons where persons.person_id = pid into pgrp;
            execute format('insert into group_memberships values ($1, $2)') using gnam, pgrp;
        elsif user_name is not null then
            assert (select exists(select 1 from users where users.user_name = unam)) = 't', 'user does not exist';
            select user_group from users where users.user_name = unam into ugrp;
            execute format('insert into group_memberships values ($1, $2)') using gnam, ugrp;
        end if;
        return json_build_object('message', 'member added');
    end;
$$ language plpgsql;


create or replace function group_member_remove(group_name text, person_id text default null, user_name text default null)
    returns json as $$
    declare pgrp text;
    declare ugrp text;
    declare gnam text;
    declare pid text;
    declare unam text;
    begin
        gnam := $1;
        pid := $2::uuid;
        unam := $3;
        assert (select exists(select 1 from groups where groups.group_name = gnam)) = 't', 'group does not exist';
        if person_id is not null then
            assert (select exists(select 1 from persons where persons.person_id = pid)) = 't', 'person does not exist';
            select person_group from persons where persons.person_id = pid into pgrp;
            execute format('delete from group_memberships where group_name = $1 and group_member_name = $2') using gnam, pgrp;
        elsif user_name is not null then
            assert (select exists(select 1 from users where users.user_name = unam)) = 't', 'user does not exist';
            select user_group from users where users.user_name = unam into ugrp;
            execute format('delete from group_memberships where group_name = $1 and group_member_name = $2') using gnam, ugrp;
        end if;
        return json_build_object('message', 'member removed');
    end;
$$ language plpgsql;


create or replace function group_members(group_name text)
    returns json as $$
    declare data json;
    begin
        assert (select exists(select 1 from groups where groups.group_name = $1)) = 't', 'group does not exist';
        -- group_get_children
        return json_build_object();
    end;
$$ language plpgsql;


create or replace function group_moderators(group_name text)
    returns json as $$
    declare data json;
    begin
        assert (select exists(select 1 from groups where groups.group_name = $1)) = 't', 'group does not exist';
        select json_agg(gm.group_moderator_name) from group_moderators gm
            where gm.group_name = $1 into data;
        return json_build_object('moderators', data);
    end;
$$ language plpgsql;


create or replace function group_capabilities(group_name text, grants boolean default 'f')
    returns json as $$
    declare data json;
    begin
        select grp_cpbts(group_name, grants) into data;
        return data;
    end;
$$ language plpgsql;
