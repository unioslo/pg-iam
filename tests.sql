
\set keep_test `echo "$KEEP_TEST_DATA"`
\set del_data `echo "$DELETE_EXISTING_DATA"`


create or replace function test_persons_users_groups()
    returns boolean as $$
    declare pid uuid;
    declare num int;
    declare uid int;
    declare gid int;
    declare pgrp text;
    begin
        insert into persons (full_name, person_expiry_date)
            values ('Sarah Conner', '2020-10-01');
        select person_id from persons where full_name like '%Conner' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-sconne', '2020-03-28');
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p66-sconne', '2019-12-01');

        -- creation
        assert (select count(*) from persons) = 1, 'person creation issue';
        assert (select count(*) from users) = 2, 'user creation issue';
        assert (select count(*) from groups) = 3, 'group creation issue';

        -- posix uids
        select user_posix_uid from users where user_name = 'p66-sconne' into uid;
        assert (select generate_new_posix_uid() = uid + 1), 'uid generation not monotonically increasing';
        begin
            update users set user_posix_uid = '2000' where user_name = 'p11-sconne';
            assert false, 'user_posix_uid is mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;

        -- posix gids
        select  group_posix_gid from groups where group_name = 'p66-sconne-group' into gid;
        assert (select generate_new_posix_gid() = gid + 1), 'gid generation not monotonically increasing';
        select person_group from persons where person_id = pid into pgrp;
        select group_posix_gid from groups where group_name = pgrp into gid;
        assert gid is null, 'person groups are being assigned gids';
        begin
            insert into groups (group_name, group_type, group_posix_gid)
                values ('g1', 'generic', 0);
            assert false, 'can assign gid between 0 and 999';
        exception when check_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_posix_gid = '2000' where group_name = 'p11-sconne-group';
            assert false, 'group_posix_gid is mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        insert into users (person_id, user_name, user_expiry_date, user_group_posix_gid)
            values (pid, 'p89-sconne', '2019-12-01', 9001);
        assert (select group_posix_gid from groups where group_name = 'p89-sconne-group') = 9001,
            'cannot explicitly set user gid';
        assert (select user_group_posix_gid from users where user_group = 'p89-sconne-group') = 9001,
            'user group gids are nor being synced to the users table';

        -- person identifiers uniqueness
        begin
            insert into persons (full_name, identifiers)
                values ('Piet Mondrian', '[{"k1": 0}, {"k2": 1}]'::json);
            insert into persons (full_name, identifiers)
                values ('Piet Mondrian', '[{"k2": 1}]'::json);
            assert false, 'persons identifiers are not ensured to be unique';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into persons (full_name, identifiers)
                values ('Jackson Pollock', '{"k3": 99}'::json);
            assert false, 'persons identifiers are not ensured to be json arrays';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;

        -- person attribute immutability
        begin
            update persons set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false, 'row_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update persons set person_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false, 'person_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update persons set person_group = 'e14c538a-4b8b-4393-9fb2-056e363899e1-group';
            assert false, 'person_group mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;

        -- user attribute immutability
        begin
            update users set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false, 'row_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update users set user_id = 'a3981c7f-8e41-4222-9183-1815b6ec9c3b';
            assert false, 'user_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update users set user_name = 'p11-scnr';
            assert false, 'user_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update users set user_group = 'p11-s-group';
            assert false, 'user_group mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;

        -- group attribute immutability
        begin
            update groups set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false, 'row_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false, 'group_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_name = 'p22-lcd-group';
            assert false, 'group_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_class = 'secondary';
            assert false, 'group_class mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_type = 'person';
            assert false, 'group_type mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;

        -- web groups, and their gid life-cycle
        insert into groups (group_name, group_class, group_type)
            values ('p11-wonderful-group', 'secondary', 'web');
        assert (select group_posix_gid from groups where group_name = 'p11-wonderful-group') is null,
            'web groups are not allowed to not have gids - while they should be';
        update groups set group_posix_gid = (select max(group_posix_gid) + 1 from groups)
            where group_name = 'p11-wonderful-group';
        begin
            update groups set group_posix_gid = null where group_name = 'p11-wonderful-group';
            assert false, 'can remove gids for web groups';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        delete from groups where group_name = 'p11-wonderful-group';

        -- states; cascades, constraints
        set session "request.identity" = 'milen';

        -- activation status
        update persons set person_activated = 'f';
        assert (select count(*) from users where user_activated = 't') = 0,
            'person state changes not propagating to users';
        assert (select count(*) from groups where group_activated = 't') = 0,
            'person state changes not propagating to groups';
        begin
            update groups set group_activated = 't'
                where group_name = pid::text || '-group';
            assert false, 'person groups can be dectivated directly on group table';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_activated = 't'
                where group_name = 'p66-sconne-group';
            assert false, 'user groups can be dectivated directly on group table';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;

        -- expiry dates
        update persons set person_expiry_date = '2019-09-09';
        update users set user_expiry_date = '2000-08-08' where user_name like 'p11-%';
        begin
            update groups set group_expiry_date = '2000-01-01'
                where group_primary_member = 'p11-sconne';
            assert false, 'user group exp updates bypasses restriction via primary';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_expiry_date = '2000-01-01'
                where group_primary_member = pid::text;
            assert false, 'person group exp updates bypasses restriction via primary';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update users set user_expiry_date = '2030-01-01'
                where user_name like 'p66-s%';
            assert false, 'users can expire _after_ persons - update';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into users (person_id, user_name, user_expiry_date)
                values (pid, 'lol-user', '2080-01-01');
            assert false, 'users can expire _after_ persons - insert';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;

        -- deletion; cascades, constraints
        begin
            delete from groups where group_type = 'person';
            assert false, 'person group deletion not protected';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            delete from groups where group_type = 'user';
            assert false, 'user group deletion not protected';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            delete from groups where group_class = 'primary';
            assert false, 'primary group deletion not protected';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        delete from persons;
        assert (select count(*) from users) = 0, 'cascading delete from person to users not working';
        assert (select count(*) from groups) = 0, 'cascading delete from person to groups not working';
    return true;
    end;
$$ language plpgsql;


create or replace function test_group_memeberships_moderators()
    returns boolean as $$
    declare pid uuid;
    declare row record;
    declare out json;
    begin
        -- create persons and users
        insert into persons (full_name, person_expiry_date)
            values ('Sarah Conner', '2050-10-01');
        select person_id from persons where full_name like '%Conner' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-sconne', '2050-03-28');
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p66-sconne', '2019-12-01');
        insert into persons (full_name, person_expiry_date)
            values ('John Conner2', '2050-10-01');
        select person_id from persons where full_name like '%Conner2' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-jconn', '2050-03-28');
        insert into persons (full_name, person_expiry_date)
            values ('Frank Castle', '2050-10-01');
        select person_id from persons where full_name like '%Castle' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-fcl', '2050-03-28');
        insert into persons (full_name, person_expiry_date)
            values ('Virginia Woolf', '2050-10-01');
        select person_id from persons where full_name like '%Woolf' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-vwf', '2050-03-28');
        insert into persons (full_name, person_expiry_date)
            values ('David Gilgamesh', '2050-10-01');
        select person_id from persons where full_name like '%Gilgamesh' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-dgmsh', '2050-03-28');
        -- create groups
        insert into groups (group_name, group_class, group_type)
            values ('p11-admin-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p11-export-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p11-publication-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p11-clinical-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p11-import-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p11-special-group', 'secondary', 'generic');
        -- add members
        insert into group_memberships (group_name, group_member_name)
            values ('p11-export-group', 'p11-admin-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-export-group', 'p11-sconne-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-export-group', 'p11-jconn-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-export-group', 'p11-clinical-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-admin-group', 'p11-fcl-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-publication-group', 'p11-vwf-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-admin-group', 'p11-publication-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-clinical-group', 'p11-dgmsh-group');
        insert into group_memberships (group_name, group_member_name)
            values ('p11-special-group', 'p11-import-group');
        /*
        This gives a valid group membership graph as follows:

            p11-export-group
                -> p11-sconne-group
                -> p11-jconn-group
                -> p11-clinical-group
                    -> p11-dgmsh-group
                -> p11-admin-group
                    -> p11-fcl-group
                    -> p11-publication-group
                        -> p11-vwf-group

        We should be able to resolve such DAGs, of arbitrary depth
        until we can report back the list of all group_primary_member(s).
        And optionally, the structure of the graph. In this case the list is:

            p11-sconne
            p11-jconn
            p11-dgmsh
            p11-fcl
            p11-vwf

        */
        raise notice 'group_name, group_member_name, group_class, group_type, group_primary_member';
        for row in select * from pgiam.first_order_members loop
            raise notice '%', row;
        end loop;


        /* GROUP MEMBERS */

        -- referential constraints
        begin
            insert into group_memberships (group_name, group_member_name)
                values ('p77-clinical-group', 'p11-special-group');
            assert false, 'group_memberships: referential constraints do not work';
        exception when foreign_key_violation then
            raise notice '%', sqlerrm;
        end;
        -- redundancy
        begin
            insert into group_memberships (group_name, group_member_name) values ('p11-export-group','p11-publication-group');
            assert false, 'group_memberships: redundancy check not working';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- cyclicality
        begin
            insert into group_memberships (group_name, group_member_name) values ('p11-publication-group','p11-export-group');
            assert false, 'group_memberships: cyclicality check not working';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into group_memberships (group_name, group_member_name) values ('p11-admin-group','p11-export-group');
            assert false, 'group_memberships: cyclicality check not working, for transitive members';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- immutability
        begin
            update group_memberships set group_name = 'p11-clinical-group' where group_name = 'p11-special-group';
            assert false, 'group_memberships: group_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update group_memberships set group_member_name = 'p11-clinical-group' where group_name = 'p11-special-group';
            assert false, 'group_memberships: group_member_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- group classes
        begin
            insert into group_memberships values ('p11-sconne-group', 'p11-special-group');
            assert false, 'group_memberships: primary groups cannot have new members';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- new relations and group activation state
        begin
            update groups set group_activated = 'f' where group_name = 'p11-import-group';
            insert into group_memberships (group_name, group_member_name) values ('p11-publication-group','p11-import-group');
            assert false, 'group_memberships: deactivated groups cannot be used in new relations';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- new relations and group expiry
        begin
            update groups set group_expiry_date = '2017-01-01' where group_name = 'p11-import-group';
            insert into group_memberships (group_name, group_member_name) values ('p11-publication-group','p11-import-group');
            assert false, 'group_memberships: expired groups cannot be used in new relations';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- shouldnt be able to be a member of itself
        begin
            insert into group_memberships (group_name, group_member_name)
                values ('p11-special-group', 'p11-special-group');
            assert false, 'group_memberships: redundancy check - groups can be members of themselves';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;

        -- safeguards in group_member_add
        begin
            perform group_member_add('lol', 'p11-import-group');
            assert false, 'group_member_add does not detect non-existent group';
        exception when foreign_key_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            perform group_member_add('p11-import-group', 'yeah');
            assert false, 'group_member_add does not detect non-existent group';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;
        begin
            perform group_member_add('p11-import-group', '59c1987e-fa15-4509-9b4e-12557fdb9ed9');
            assert false, 'group_member_add does not detect non-existent person_id';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;

        /* GROUP MODERATORS */

        insert into group_moderators (group_name, group_moderator_name)
            values ('p11-import-group', 'p11-admin-group');
        insert into group_moderators (group_name, group_moderator_name)
            values ('p11-clinical-group', 'p11-special-group');
        -- self-moderation
        insert into group_moderators (group_name, group_moderator_name)
            values ('p11-admin-group', 'p11-admin-group');
        -- referential constraints
        begin
            insert into group_moderators (group_name, group_moderator_name)
                values ('p79-clinical-group', 'p11-special-group');
            assert false,  'group_moderators: referential constraints do not work';
        exception when foreign_key_violation then
            raise notice '%', sqlerrm;
        end;
        -- immutability
        begin
            update group_moderators set group_name = 'p11-admin-group' where group_name = 'p11-import-group';
            assert false, 'group_moderators: group_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update group_moderators set group_moderator_name = 'p11-export-group' where group_name = 'p11-import-group';
            assert false, 'group_moderators: group_moderator_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- redundancy
        begin
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-clinical-group', 'p11-special-group');
            assert false, 'group_moderators: redundancy check - can recreate existing relations';
        exception when unique_violation then
            raise notice '%', sqlerrm;
        end;
        -- cyclicality
        begin
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-special-group', 'p11-clinical-group');
            assert false, 'group_moderators: cyclicality check not working';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- new relations and group activation state
        begin
            insert into groups (group_name, group_class, group_type)
                values ('p11-lol-group', 'secondary', 'generic');
            update groups set group_activated = 'f' where group_name = 'p11-lol-group';
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-lol-group', 'p11-admin-group');
            assert false, 'group_moderators: deactivated groups can be used';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- new relations and group expiry
        begin
            insert into groups (group_name, group_class, group_type)
                values ('p11-lol-group', 'secondary', 'generic');
            update groups set group_expiry_date = '2011-01-01' where group_name = 'p11-lol-group';
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-lol-group', 'p11-admin-group');
            assert false, 'group_moderators: expired groups cannot be used';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        update groups set group_expiry_date = '2011-01-01' where group_name = 'p11-export-group';
        --delete from persons;
        --delete from groups;
        return true;
    end;
$$ language plpgsql;


create or replace function test_group_membership_constraints()
    returns boolean as $$
    declare mems json;
    declare grps json;
    declare tomorrow jsonb;
    declare hour_from_now jsonb;
    declare num int;
    begin
        -- create persons, users, groups
        insert into persons (full_name, person_expiry_date)
            values ('Bruce Wayne', '2050-10-01');
        insert into persons (full_name, person_expiry_date)
            values ('Peter Parker', '2060-10-01');
        insert into persons (full_name, person_expiry_date)
            values ('Frida Kahlo', '2077-10-01');
        insert into persons (full_name, person_expiry_date)
            values ('Carol Danvers', '2080-10-01');
        insert into persons (full_name, person_expiry_date)
            values ('Breyten Breytenbach', '2090-10-01');
        insert into users (person_id, user_name, user_expiry_date)
            values (
                (select person_id from persons where full_name like 'Bruce%'),
                'p12-bwn',
                '2050-03-28'
            );
        insert into users (person_id, user_name, user_expiry_date)
            values (
                (select person_id from persons where full_name like 'Peter%'),
                'p12-pp',
                '2060-10-01'
            );
        insert into users (person_id, user_name, user_expiry_date)
            values (
                (select person_id from persons where full_name like 'Frida%'),
                'p12-fkl',
                '2060-10-01'
            );
        insert into users (person_id, user_name, user_expiry_date)
            values (
                (select person_id from persons where full_name like 'Carol%'),
                'p12-cld',
                '2060-10-01'
            );
        insert into users (person_id, user_name, user_expiry_date)
            values (
                (select person_id from persons where full_name like 'Breyten%'),
                'p12-brb',
                '2060-10-01'
            );
        insert into groups (group_name, group_class, group_type)
            values ('p12-admin-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p12-export-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p12-temp-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p12-guest-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type, group_expiry_date)
            values ('p12-lol-group', 'secondary', 'generic', '2090-01-01');

        -- check membership data validation
        -- start and end date constraints
        begin
            perform group_member_add('p12-lol-group', 'p12-brb', null, '2091-01-01');
            assert false, 'membership: end_date can exceed group expiry check works';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into group_memberships(
                group_name, group_member_name, start_date, end_date
            ) values (
                'p12-admin-group', 'p12-brb-group', '2080-01-01', '2000-01-01'
            );
            assert false, 'membership: start_date < end_date check works';
        exception when check_violation then
            raise notice '%', sqlerrm;
        end;
        -- weekdays constraints
        begin
            insert into group_memberships(
                group_name, group_member_name, weekdays
            ) values (
                'p12-admin-group', 'p12-brb-group', '{"Lol": {}}'::jsonb
            );
            assert false, 'membership: weekdays wrong key name refused';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into group_memberships(
                group_name, group_member_name, weekdays
            ) values (
                'p12-admin-group', 'p12-brb-group', '{"mon": {"end": "12:00"}}'::jsonb
            );
            assert false, 'membership: weekdays missing start time';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into group_memberships(
                group_name, group_member_name, weekdays
            ) values (
                'p12-admin-group', 'p12-brb-group', '{"mon": {"start": "12:00"}}'::jsonb
            );
            assert false, 'membership: weekdays missing end date';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into group_memberships(
                group_name, group_member_name, weekdays
            ) values (
                'p12-admin-group', 'p12-brb-group', '{"mon": {"start": "13:00", "end": "12:00"}}'::jsonb
            );
            assert false, 'membership: weekdays start > end time';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;

        -- create a valid membership graph
        /*

        p12-export-group
            -> p12-bwn-group -> p12-bwn
            -> p12-admin-group
                -> p12-pp-group -> p12-pp
                -> p12-temp-group
                    -> p12-fkl-group -> p12-fkl (initial: not active yet)
                -> p12-guest-group
                    -> p12-cld-group -> p12-cld (initial: expired)

        */
        perform group_member_add('p12-export-group', 'p12-bwn');
        perform group_member_add('p12-export-group', 'p12-admin-group');
        perform group_member_add('p12-admin-group', 'p12-pp');
        perform group_member_add('p12-admin-group', 'p12-temp-group');
        perform group_member_add('p12-temp-group', 'p12-fkl', '2080-01-01', '2081-11-01');
        perform group_member_add('p12-admin-group', 'p12-guest-group');
        perform group_member_add('p12-guest-group', 'p12-cld', '2020-01-01', '2021-03-01');

        -- check membership reporting (without and with constraint enforcement)
        -- group_members
        select group_members('p12-export-group') into mems;
        assert json_array_length(mems->'direct_members') = 2, 'not reporting direct_members correctly';
        assert json_array_length(mems->'transitive_members') = 5, 'not reporting transitive_members correctly';
        assert json_array_length(mems->'ultimate_members') = 4, 'not reporting ultimate_members correctly';

        -- with constraint filtering
        select group_members('p12-export-group', 't') into mems;
        assert json_array_length(mems->'direct_members') = 2, 'not reporting direct_members correctly';
        assert json_array_length(mems->'transitive_members') = 3, 'not reporting transitive_members correctly';
        assert json_array_length(mems->'ultimate_members') = 2, 'not filtering ultimate_members correctly';

        -- add a weekday filter allowing only tomorrow
        select ('{"' || day_from_ts(current_timestamp + interval '1 day') ||
                '": {"start": "08:00", "end": "19:00"}}')::jsonb
            into tomorrow;
        update group_memberships set weekdays = tomorrow
            where group_name = 'p12-export-group'
            and group_member_name = 'p12-bwn-group';

        -- using current_timestamp (default)
        select group_members('p12-export-group', 't') into mems;
        assert json_array_length(mems->'ultimate_members') = 1, 'not filtering ultimate_members correctly (defaut client_timestamp)';

        -- pretend we're at time zone 0
        -- add a weekday filter or after an hour from now (relative to time zone 0), today
        select ('{"' || day_from_ts(current_timestamp at time zone '0') ||
                '": {"start": "' || (current_time at time zone '0' + interval '1 hour')::time ||
                '",  "end": "' || (current_time at time zone '0' + interval '3 hour')::time || '"}}')::jsonb
            into hour_from_now;
        update group_memberships set weekdays = hour_from_now
            where group_name = 'p12-export-group'
            and group_member_name = 'p12-bwn-group';

        -- using client_timestamp provided by the caller (within the allowed time period)
        select group_members('p12-export-group', 't', (current_timestamp at time zone '0' + interval '2 hour')) into mems;
        assert json_array_length(mems->'ultimate_members') = 2, 'not filtering ultimate_members correctly (caller client_timestamp)';

        -- using client_timestamp provided by the caller (outside the allowed time period)
        select group_members('p12-export-group', 't', (current_timestamp at time zone '0' + interval '4 hour')) into mems;
        assert json_array_length(mems->'ultimate_members') = 1, 'not filtering ultimate_members correctly (caller client_timestamp)';

        -- ensure working limits on client timestamp
        begin
            select group_members('p12-export-group', 't', (current_timestamp + interval '4 days')) into mems;
            assert false, 'membership: impossible client_timestamp refused';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;

        -- user_groups

        select user_groups('p12-fkl') into grps;
        assert json_array_length(grps->'user_groups') = 4, 'user_groups issue (no filtering)';
        select user_groups('p12-fkl', 't') into grps;
        assert json_array_length(grps->'user_groups') = 1, 'user_groups issue (with filtering - start date)';
        select user_groups('p12-bwn') into grps;
        assert json_array_length(grps->'user_groups') = 2, 'user_groups issue (no filtering)';
        select user_groups('p12-bwn', 't', (current_timestamp at time zone '0' + interval '4 hour')) into grps;
        assert json_array_length(grps->'user_groups') = 1, 'user_groups issue (with filtering - weekdays)';

        -- check audit

        select count(*) from audit_log_relations
            where parent = 'p12-export-group'
            and operation = 'UPDATE'
            and weekdays is not null
            into num;
        assert num > 0, 'audit_log_relations not recording changes to weekdays';

        -- delete persons, users, and groups
        delete from persons where
            full_name like 'Bruce%'
            or full_name like 'Peter%'
            or full_name like 'Frida%'
            or full_name like 'Carol%'
            or full_name like 'Breyten%';
        delete from groups where group_name like 'p12%';

        return 'true';
    end;
$$ language plpgsql;


create or replace function test_capabilities_http()
    returns boolean as $$
    declare cid uuid;
    declare grid uuid;
    declare ans boolean;
    declare grid1 uuid;
    declare grid2 uuid;
    declare grid3 uuid;
    declare grid4 uuid;
    begin
        insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date)
            values ('p11import', '{api.com}', '{"role": "p11_import_user"}',
                    '{"p11-export-group", "p11-special-group"}', 'exact',
                    '123', 'bla', current_date);
        insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date)
            values ('export', '{api.com}', '{"role": "export_user"}',
                    '{"admin-group", "export-group"}', 'wildcard',
                    '123', 'bla', current_date);
        insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date)
            values ('admin', '{api.com}', '{"role": "admin_user"}',
                    '{"admin-group", "special-group"}', 'wildcard',
                    '123', 'bla', current_date);
        -- immutability
        begin
            update capabilities_http set row_id = '35b77cf9-0a6f-49d7-83df-e388d75c4b0b';
            assert false, 'capabilities_http: row_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update capabilities_http set capability_id = '35b77cf9-0a6f-49d7-83df-e388d75c4b0b';
            assert false, 'capabilities_http: capability_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update capabilities_http set capability_name = 'lol';
            assert false, 'capabilities_http: capability_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- uniqueness
        begin
            insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date)
                values ('admin', '{api.com}', '{"role": "admin_user"}',
                        '{"admin-group", "special-group"}', 'wildcard',
                        '123', 'bla', current_date);
            assert false, 'capabilities_http: name uniqueness not guaranteed';
        exception when others then
            raise notice '%', sqlerrm;
        end;
        begin
            update capabilities_http set capability_required_groups = '{self,self}'
                where capability_name = 'admin';
            assert false, 'capabilities_http: required groups are guaranteed unique';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- referential constraints
        begin
            insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date)
            values ('admin2', '{api.com}', '{"role": "admin_user"}',
                    '{"admin2-group", "very-special-group"}', 'wildcard',
                    '123', 'bla', current_date);
            assert false, 'capabilities_http: optional group existence check not working';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- ability to override group references
        insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date,
                                  capability_group_existence_check)
            values ('admin2', '{api.com}', '{"role": "admin_user"}',
                    '{"admin2-group", "very-special-group"}', 'wildcard',
                    '123', 'bla', current_date, 'f');
        delete from capabilities_http where capability_name = 'admin2';
        insert into capabilities_http_grants (capability_grant_rank, capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern)
                                      values (null, '{export}',
                                              '{api.com}', 'files',
                                              'PUT', '/p11/files');
        insert into capabilities_http_grants (capability_grant_rank, capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern)
                                      values (1, '{export}',
                                              '{api.com}', 'files',
                                              'GET', '/(.*)/export');
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern)
                                      values ('{export}',
                                              '{api.com}', 'files',
                                              'DELETE', '/(.*)/files');
        insert into capabilities_http_grants (capability_grant_rank, capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern)
                                      values (2, '{export,admin}',
                                              '{api.com}', 'files',
                                              'GET', '/(.*)/admin');
        -- immutability
        begin
            update capabilities_http_grants set row_id = '35b77cf9-0a6f-49d7-83df-e388d75c4b0b';
            assert false, 'capabilities_http_grants: row_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update capabilities_http_grants set capability_grant_id = '35b77cf9-0a6f-49d7-83df-e388d75c4b0b';
            assert false, 'capabilities_http_grants: capability_grant_id immutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- referential constraints
        begin
            insert into capabilities_http_grants (capability_names_allowed,
                                                  capability_grant_hostnames, capability_grant_namespace,
                                                  capability_grant_http_method, capability_grant_uri_pattern,
                                                  capability_grant_required_groups)
                                          values ('{i-do-not-exist}',
                                                  '{api.com}', 'files',
                                                  'GET', '/(.*)/admin',
                                                  '{"p11-export-group"}');
            assert false, 'possible to reference non-existent capability from grants';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into capabilities_http_grants (capability_names_allowed,
                                                  capability_grant_hostnames, capability_grant_namespace,
                                                  capability_grant_http_method, capability_grant_uri_pattern,
                                                  capability_grant_required_groups)
                                          values ('{export}',
                                                  '{api.com}', 'files',
                                                  'GET', '/(.*)/admin',
                                                  '{"my-own-crazy-group"}');
            assert false, 'capabilities_http_grants: required groups need to exist when referenced, by default';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- ability to override group references
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern,
                                              capability_grant_required_groups, capability_grant_group_existence_check)
                                      values ('{export}',
                                              '{api.com}', 'files',
                                              'GET', '/(.*)/admin',
                                              '{"my-own-crazy-group"}', 'f');
        -- add some more test data
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern,
                                              capability_grant_required_groups, capability_grant_group_existence_check)
                                      values ('{export}',
                                              '{api.com}', 'files',
                                              'GET', '/(.*)/export',
                                              '{"my-own-custom-export-group"}', 'f');
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern,
                                              capability_grant_required_groups, capability_grant_group_existence_check)
                                      values ('{export}',
                                              '{api.com}', 'files',
                                              'HEAD', '/(.*)/export',
                                              '{"my-own-custom-export-group"}', 'f');
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern,
                                              capability_grant_required_groups, capability_grant_group_existence_check)
                                      values ('{export}',
                                              '{api.com}', 'files',
                                              'GET', '/something',
                                              '{"my-own-custom-export-group"}', 'f');
        -- grant ranking
        -- generation
        assert 1 in (select capability_grant_rank from capabilities_http_grants
             where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'),
             'rank generation issue: 1';
        assert 2 in (select capability_grant_rank from capabilities_http_grants
             where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'),
             'rank generation issue: 2';
        assert 3 in (select capability_grant_rank from capabilities_http_grants
             where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'),
             'rank generation issue: 3';
        assert 6 not in (select capability_grant_rank from capabilities_http_grants
             where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'),
             'rank generation issue: 6';
        -- natural numbers
        select capability_grant_id from capabilities_http_grants
            where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'
            and capability_grant_rank = 1 into grid;
        begin
            select capability_grant_rank_set(grid::text, -9) into ans;
            assert false, 'capabilities_http_grants: can set rank to negative';
        exception when check_violation then
            raise notice '%', sqlerrm;
        end;
        -- monotonicity
        begin
            select capability_grant_rank_set(grid::text, 9) into ans;
            assert false, 'capabilities_http_grants: rank is not monotonically increasing';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        -- uniqueness
        begin
            insert into capabilities_http_grants (
                capability_names_allowed,
                capability_grant_hostnames,
                capability_grant_namespace,
                capability_grant_http_method,
                capability_grant_uri_pattern,
                capability_grant_required_groups,
                capability_grant_group_existence_check,
                capability_grant_rank
            )
            values (
                '{export}',
                '{api.com}',
                'files',
                'HEAD',
                '/(.*)/export',
                '{"my-own-custom-export-group"}',
                'f',
                1
            );
            assert false, 'capabilities_http_grants: rank values issue: not unique within their grant sets';
        exception when unique_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update capabilities_http_grants set capability_grant_required_groups = '{self,self}'
                where capability_grant_id = grid;
            assert false, 'capabilities_http_grants: groups are not ensured to be unique';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- reject if grant id not found
        begin
            select capability_grant_rank_set('a7068767-752b-463d-9828-07badb675591', 9) into ans;
            assert false, 'capabilities_http_grants: non-existent grant ID not rejected';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;
        -- correct reorder
        select capability_grant_id from capabilities_http_grants
            where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'
            and capability_grant_rank = 1 into grid1;
        select capability_grant_id from capabilities_http_grants
            where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'
            and capability_grant_rank = 2 into grid2;
        select capability_grant_id from capabilities_http_grants
            where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'
            and capability_grant_rank = 3 into grid3;
        select capability_grant_id from capabilities_http_grants
            where capability_grant_hostnames = array['api.com'] and capability_grant_http_method = 'GET'
            and capability_grant_rank = 4 into grid4;
        /*
        id , rank_before, rank_after
        id1, 1          , 2
        id2, 2          , 3
        id3, 3          , 1
        id4, 4          , 4
        */
        select capability_grant_rank_set(grid3::text, 1) into ans;
        assert (select capability_grant_rank from capabilities_http_grants
                where capability_grant_id = grid3) = 1, 'rank set issue - id3';
        assert (select capability_grant_rank from capabilities_http_grants
                where capability_grant_id = grid1) = 2, 'rank set issue - id1';
        assert (select capability_grant_rank from capabilities_http_grants
                where capability_grant_id = grid2) = 3, 'rank set issue - id2';
        assert (select capability_grant_rank from capabilities_http_grants
                where capability_grant_id = grid4) = 4, 'rank set issue - id4';
        raise notice 'capabilities_http_grants: capability_grant_rank_set works';
        -- irrelevant rankings not affected (within and between rank sets)
        assert (select max(capability_grant_rank) from capabilities_http_grants
                where capability_grant_hostnames = array['api.com']
                and capability_grant_http_method = 'HEAD') = 1,
            'per capability, per http_method ranking broken';
        -- deletes (keep rank consistent)
        select capability_grant_delete(grid2::text) into ans;
        assert (select capability_grant_rank from capabilities_http_grants
                where capability_grant_id = grid4) = 3, 'rank delete issue - id4';
        -- test self and moderator keywords
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_name,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern,
                                              capability_grant_required_groups)
                                      values ('{export,admin}',
                                              'allow_get',
                                              '{api.com}', 'files',
                                              'GET', '/(.*)/admin/profile/([a-zA-Z0-9])',
                                              '{"self"}');
        select capability_grant_group_add('allow_get', 'moderator') into ans;
        assert array['moderator'] <@ (select capability_grant_required_groups from capabilities_http_grants
                                      where capability_grant_name = 'allow_get'), 'capability_grant_group_add issue';
        select capability_grant_id from capabilities_http_grants where capability_grant_name = 'allow_get' into grid1;
        select capability_grant_group_remove(grid1::text, 'moderator') into ans;
        assert array['self'] = (select capability_grant_required_groups from capabilities_http_grants
                                where capability_grant_name = 'allow_get'), 'capability_grant_group_remove issue';
        -- test that deleting a capability_name automatically removes it from any references in capability_names_allowed
        insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                       capability_required_groups, capability_group_match_method,
                                       capability_lifetime, capability_description, capability_expiry_date)
                               values ('edit', '{api.com}', '{"role": "editor"}',
                                      '{"p11-export-group", "p11-special-group"}', 'exact',
                                      '123', 'bla', current_date);
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_name,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern,
                                              capability_grant_required_groups)
                                      values ('{admin,edit}',
                                              'allow_edit',
                                              '{api.com}', 'files',
                                              'PATCH', '/(.*)/admin/profile/([a-zA-Z0-9])',
                                              '{self}');
        delete from capabilities_http where capability_name = 'edit';
        assert (select capability_names_allowed from capabilities_http_grants where capability_grant_name = 'allow_edit')
            = array['admin'], 'capabilities_http_grants: automatic deletion of references to capability_name in grants does not work';
        begin
            delete from capabilities_http where capability_name = 'export';
            assert false,'capabilities_http_grants: protection against removing a capability_name, when grants refer only to that name does not works';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        return true;
    end;
$$ language plpgsql;


create or replace function test_capability_instances()
    returns boolean as $$
    declare iid uuid;
    declare instance json;
    begin
        insert into capabilities_http_instances
            (capability_name, instance_start_date, instance_end_date,
             instance_usages_remaining, instance_metadata)
        values ('export', now() - interval '1 hour', current_timestamp + '2 hours',
                3, '{"claims": {"proj": "p11", "user": "p11-anonymous"}}');
        select instance_id from capabilities_http_instances into iid;
        select capability_instance_get(iid::text) into instance;
        -- decrementing instance_usages_remaining
        assert (select instance_usages_remaining from capabilities_http_instances
                where instance_id = iid) = 2,
            'instance_usages_remaining not being decremented after instance creation';
        assert instance->>'instance_usages_remaining' = 2::text,
            'instance_usages_remaining incorrectly reported by instance creation function';
        -- auto deletion
        select capability_instance_get(iid::text) into instance;
        select capability_instance_get(iid::text) into instance;
        begin
            select capability_instance_get(iid::text) into instance;
            assert false, 'automatic deletion of capability instances not working';
        exception when invalid_parameter_value then
            raise notice '%', sqlerrm;
        end;
        -- cannot use if expired
        insert into capabilities_http_instances
            (capability_name, instance_start_date, instance_end_date,
             instance_usages_remaining, instance_metadata)
        values ('export', now() - interval '3 hour', now() - interval '2 hour',
                3, '{"claims": {"proj": "p11", "user": "p11-anonymous"}}');
        select instance_id from capabilities_http_instances into iid;
        begin
            select capability_instance_get(iid::text) into instance;
            assert false, 'expired capability instance usage not denied';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        delete from capabilities_http_instances where instance_id = iid;
        -- cannot use if not active yet
        insert into capabilities_http_instances
            (capability_name, instance_start_date, instance_end_date,
             instance_usages_remaining, instance_metadata)
        values ('export', now() + interval '3 hour', now() + interval '4 hour',
                3, '{"claims": {"proj": "p11", "user": "p11-anonymous"}}');
        select instance_id from capabilities_http_instances into iid;
        begin
            select capability_instance_get(iid::text) into instance;
            assert false, 'using capability instance before start time is possible';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        -- immutable cols
        begin
            update capabilities_http_instances set row_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where instance_id = iid;
            assert false, 'capabilities_http_instances: row_id immutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update capabilities_http_instances set capability_name = 'parsley'
                where instance_id = iid;
            assert false, 'capabilities_http_instances: capability_name immutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update capabilities_http_instances set instance_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where instance_id = iid;
            assert false, 'capabilities_http_instances: instance_id immutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        return true;
    end;
$$ language plpgsql;


create or replace function test_audit()
    returns boolean as $$
    declare pid uuid;
    declare rid uuid;
    declare grp text;
    begin
        select person_id from persons limit 1 into pid;
        select row_id from persons where person_id = pid into rid;
        update persons set person_activated = 'f' where person_id = pid;
        assert (select count(*) from audit_log_objects
                where row_id = rid) > 0, 'issue with audit_log_objects';
        select group_name from groups where group_class = 'secondary' limit 1 into grp;
        assert (select count(*) from audit_log_relations
                where parent = grp) > 0, 'issue with audit_log_relations';
        return true;
    end;
$$ language plpgsql;


create or replace function test_funcs()
    returns boolean as $$
    declare data json;
    declare pgrp text;
    declare pid uuid;
    declare cid uuid;
    declare err text;
    declare ans text;
    begin
        -- person_groups
        insert into persons (full_name, person_expiry_date)
            values ('Salvador Dali', '2050-10-01');
        select person_group from persons where full_name like '%Dali' into pgrp;
        insert into groups (group_name, group_class, group_type)
            values ('p11-surrealist-group', 'secondary', 'generic');
        insert into groups (group_name, group_class, group_type)
            values ('p11-pointilism-group', 'secondary', 'generic');
        select person_id from persons where full_name like '%Dali' into pid;
        select group_member_add('p11-surrealist-group', pid::text) into ans;
        select group_member_add('p11-pointilism-group', pid::text) into ans;
        select person_groups(pid::text) into data;
        err := 'person_groups issue';
        assert data->>'person_id' = pid::text, err;

        -- person_capabilities
        insert into capabilities_http (
            capability_name,
            capability_hostnames,
            capability_required_groups,
            capability_group_match_method,
            capability_lifetime,
            capability_description,
            capability_expiry_date
        ) values (
            'p11-art',
            '{api.com}',
            '{"p11-surrealist-group", "p11-admin-group"}',
            'exact',
            123,
            'bla',
            current_date
        );
        insert into capabilities_http (
            capability_name,
            capability_hostnames,
            capability_required_groups,
            capability_group_match_method,
            capability_lifetime,
            capability_description
        ) values (
            'anything',
            '{api.com}',
            null,
            'exact',
            60,
            'a good capability'
        );
        insert into capabilities_http (
            capability_name,
            capability_hostnames,
            capability_required_groups,
            capability_group_match_method,
            capability_lifetime,
            capability_description
        ) values (
            'nothing',
            '{api.com}',
            '{surrealist-group}',
            'wildcard',
            60,
            'a very good capability'
        );
        insert into capabilities_http_grants (
            capability_names_allowed,
            capability_grant_hostnames,
            capability_grant_namespace,
            capability_grant_http_method,
            capability_grant_uri_pattern,
            capability_grant_required_groups
        ) values (
            '{export,p11-art}',
            '{api.com}',
            'files',
            'GET',
            '/(.*)/art',
            '{surrealist-group}'
        );
        insert into capabilities_http_grants (
            capability_names_allowed,
            capability_grant_hostnames,
            capability_grant_namespace,
            capability_grant_http_method,
            capability_grant_uri_pattern,
            capability_grant_required_groups
        ) values (
            '{anything}',
            '{api.com}',
            'things',
            'PUT',
            '/moar/.+',
            null
        );
        insert into capabilities_http_grants (
            capability_names_allowed,
            capability_grant_hostnames,
            capability_grant_namespace,
            capability_grant_http_method,
            capability_grant_uri_pattern,
            capability_grant_required_groups
        ) values (
            '{nothing}',
            '{api.com}',
            'things',
            'GET',
            '/neither-perception-nor-non-perception',
            null
        );
        insert into capabilities_http_grants (
            capability_names_allowed,
            capability_grant_hostnames,
            capability_grant_namespace,
            capability_grant_http_method,
            capability_grant_uri_pattern,
            capability_grant_required_groups
        ) values (
            '{nothing,anything}',
            '{api.com}',
            'things',
            'GET',
            '/anatta/.+',
            '{self}'
        );
        insert into capabilities_http_grants (
            capability_names_allowed,
            capability_grant_hostnames,
            capability_grant_namespace,
            capability_grant_http_method,
            capability_grant_uri_pattern,
            capability_grant_required_groups
        ) values (
            '{nothing,anything}',
            '{api.com}',
            'things',
            'GET',
            '/groups/memberships/.+',
            '{moderator,admin-group}'
        );
        insert into capabilities_http_grants (
            capability_names_allowed,
            capability_grant_hostnames,
            capability_grant_namespace,
            capability_grant_http_method,
            capability_grant_uri_pattern,
            capability_grant_required_groups
        ) values (
            '{nothing}',
            '{api.com}',
            'things',
            'GET',
            '/lol/cats/.+',
            '{pointilism-group}'
        );
        select person_capabilities(pid::text, 't') into data;
        err := 'person_capabilities issue';
        assert data->>'person_id' = pid::text, err;
        assert data->'person_capabilities'->0->>'group_name' = 'p11-surrealist-group', err;

        -- person_access
        err := 'person_access issue';
        select person_access(pid::text) into data;
        assert data->'person_group_access' is not null, err;
        assert data->'user_group_access' is null, err;
        assert data->'groupless_access'->'capabilities_http'->>0 = 'anything', err || ' groupless_access';
        assert json_array_length(data->'groupless_access'->'capabilities_http_grants') = 3, err || ' groupless_access';
        assert json_array_length(
                data->'person_group_access'->'person_capabilities'->0->'capabilities_http_grants'
            ) = 5, err || ' person_group_access';

        -- group_member_add (with a user)
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-dali', '2040-12-01');
        select group_member_add('p11-surrealist-group', 'p11-dali') into ans;
        assert (select count(*) from group_memberships where group_member_name = 'p11-dali-group') = 1, 'group_member_add issue';

        -- user_groups
        select user_groups('p11-dali') into data;
        err := 'user_groups issue';
        assert data->>'user_name' = 'p11-dali', err;
        assert data->'user_groups'->1->>'member_name' = 'p11-dali-group', err;
        assert data->'user_groups'->1->>'member_group' = 'p11-surrealist-group', err;
        assert data->'user_groups'->1->>'group_activated' = 'true', err;
        assert data->'user_groups'->1->>'group_expiry_date' is null, err;

        -- user_capabilities
        select user_capabilities('p11-dali', 't') into data;
        err := 'user_capabilities issue';
        assert data->>'user_name' = 'p11-dali', err;
        assert data->'user_capabilities'->0->>'group_name' = 'p11-surrealist-group', err;
        assert data->'user_capabilities'->0->'capabilities_http'->>0 = 'p11-art', err;

        -- group_members
        insert into persons (full_name, person_expiry_date)
            values ('Andre Breton', '2050-10-01');
        select person_group from persons where full_name like '%Breton' into pgrp;
        insert into groups (group_name, group_class, group_type)
            values ('p11-painter-group', 'secondary', 'generic');
        select person_id from persons where full_name like '%Breton' into pid;
        insert into users (person_id, user_name, user_expiry_date)
            values (pid, 'p11-abtn', '2050-01-01');
        select group_member_add('p11-painter-group', 'p11-abtn') into ans;
        select group_member_add('p11-surrealist-group', 'p11-painter-group') into ans;
        select group_members('p11-surrealist-group') into data;
        select person_group from persons where full_name like '%Dali' into pgrp;
        err := 'group_members issue';
        assert data->'direct_members'->0->>'group_member' = pgrp, err;
        assert data->'direct_members'->1->>'group_member' = 'p11-dali-group', err;
        assert data->'direct_members'->2->>'group_member' = 'p11-painter-group', err;
        assert data->'transitive_members'->0->>'group' = 'p11-painter-group', err;
        assert data->'transitive_members'->0->>'group_member' = 'p11-abtn-group', err;
        assert data->'transitive_members'->0->>'primary_member' = 'p11-abtn', err;
        assert data->'transitive_members'->0->>'activated' = 'true', err;
        assert data->'transitive_members'->0->>'expiry_date' is null, err;
        select person_id from persons where full_name like '%Dali' into pid;
        assert data->'ultimate_members'->>0 = pid::text, err;
        assert data->'ultimate_members'->>1 = 'p11-abtn', err;
        assert data->'ultimate_members'->>2 = 'p11-dali', err;

        -- group_moderators
        insert into group_moderators values ('p11-surrealist-group', 'p11-painter-group');
        select group_moderators('p11-surrealist-group') into data;
        err := 'group_moderators issue';
        assert data->>'group_name' = 'p11-surrealist-group', err;
        assert data->'group_moderators' is not null, err;

        -- user_moderators
        select user_moderators('p11-abtn') into data;
        assert data->'user_moderators'->>0 = 'p11-surrealist-group', err;
        err := 'user_moderators issue';

        -- group_member_remove
        select group_member_remove('p11-surrealist-group', 'p11-dali') into ans;
        assert (select count(*) from group_memberships
                where group_member_name = 'p11-dali-group'
                and group_name = 'p11-surrealist-group') = 0,
            'group_member_remove issue';

        -- group_capabilities
        select group_capabilities('p11-surrealist-group') into data;
        err := 'group_capabilities issue';
        assert data->>'group_name' = 'p11-surrealist-group', err;
        assert data->'capabilities_http'->>0 = 'p11-art', err;
        return true;
    end;
$$ language plpgsql;


create or replace function test_institutions()
    returns boolean as $$
    declare grp text;
    begin
        insert into institutions (institution_name, institution_long_name, institution_expiry_date)
            values ('uil', 'University of Leon', '2060-01-01');
        -- defaults
        assert (select institution_group from institutions
                where institution_name = 'uil') = 'uil-group',
            'institution group name default broken';
        assert (select institution_activated from institutions
                where institution_name = 'uil') = 't',
            'institution activation default broken';
        -- immutability
        begin
            update institutions set row_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where institution_name = 'uil';
            assert false, 'institutions: row_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update institutions set institution_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where institution_name = 'uil';
            assert false, 'institutions: institution_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update institutions set institution_name = 'liu'
                where institution_name = 'uil';
            assert false, 'institutions: institution_name mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update institutions set institution_group = 'foo-group'
                where institution_name = 'uil';
            assert false, 'institutions: institution_group mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- groups
        select institution_group from institutions
            where institution_name = 'uil' into grp;
        assert (select count(*) from groups where group_name = grp) = 1,
            'institution group not generated correctly';
        assert (select group_type from groups where group_name = grp) = 'institution',
            'institution group generated with incorrect type';
        -- syncing exp dates
        assert (select group_expiry_date from groups where group_name = grp) = '2060-01-01',
            'institution_expiry_date not being synced to groups on creation';
        update institutions set institution_activated = 'f' where institution_name = 'uil';
        assert (select group_activated from groups where group_name = grp) = 'f',
            'institution group activation status management not working';
        begin
            update groups set group_activated = 't' where group_name = grp;
            assert false, 'institution group activation mutable on groups';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_expiry_date = '2020-01-01' where group_name = grp;
            assert false, 'institution group_expiry_date mutable on groups';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        return true;
    end;
$$ language plpgsql;


create or replace function test_projects()
    returns boolean as $$
    declare grp text;
    begin
        insert into projects (project_number, project_name, project_start_date, project_end_date)
            values ('p11', 'raka', '2020-01-02', '2050-01-01');
        -- defaults
        assert (select project_group from projects where project_name = 'raka') = 'p11-group',
            'project group generation not working';
        assert (select project_activated from projects where project_name = 'raka') = 't',
            'project activation default not working';
        -- immutability
        begin
            update projects set row_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where project_name = 'raka';
            assert false, 'projects: row_id mutable';
        exception when integrity_constraint_violation then
            raise notice 'projects: row_id immutable';
        end;
        begin
            update projects set project_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where project_name = 'raka';
            assert false, 'projects: project_id mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update projects set project_number = 'lolcat'
                where project_name = 'raka';
            assert false, 'projects: project_number mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update projects set project_group = 'some-group'
                where project_name = 'raka';
            assert false, 'projects: project_group mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- groups
        select project_group from projects
            where project_number = 'p11' into grp;
        assert (select count(*) from groups where group_name = grp) = 1,
            'project group generation not working';
        assert (select group_type from groups where group_name = grp) = 'project',
            'project group generated with incorrect type';
        assert (select group_expiry_date from groups where group_name = grp) = '2050-01-01',
            'project_end_date not being synced to groups on creation';
        update projects set project_activated = 'f' where project_group = grp;
        assert (select group_activated from groups where group_name = grp) = 'f',
            'project group management not working';
        begin
            update groups set group_activated = 't' where group_name = grp;
            assert false, 'project group activation mutable on groups';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_expiry_date = '2020-01-01' where group_name = grp;
            assert false, 'project group_expiry_date mutable on groups';
        exception when restrict_violation then
            raise notice '%', sqlerrm;
        end;
        return true;
    end;
$$ language plpgsql;


create or replace function test_organisations()
    returns boolean as $$
    declare data json;
    begin
        insert into institutions(
            institution_name, institution_long_name, institution_expiry_date
        ) values (
            'corp', 'abstract tech', '3000-01-01'
        );
        insert into institutions(
            institution_name, institution_long_name, institution_expiry_date
        ) values (
            'megacorp', 'initech', '2050-10-11'
        );
        insert into projects(
            project_number, project_name, project_start_date, project_end_date
        ) values (
            'p99', 'project 99', '2000-12-01', '2080-01-01'
        );
        insert into projects(
            project_number, project_name, project_start_date, project_end_date
        ) values (
            'p100', 'project 100', '2002-05-18', '2080-01-01'
        );
        insert into groups (
            group_name, group_class, group_type
        ) values (
            'megacorp-admin-group', 'secondary', 'web'
        );
        insert into groups (
            group_name, group_class, group_type
        ) values (
            'p99-admin-group', 'secondary', 'generic'
        );
        insert into groups (
            group_name, group_class, group_type
        ) values (
            'p99-weirdo-group', 'secondary', 'generic'
        );
        insert into groups (
            group_name, group_class, group_type
        ) values (
            'p100-admin-group', 'secondary', 'generic'
        );

        -- institutional hierarchies
        perform institution_member_add('corp', 'megacorp');
        perform institution_member_add('megacorp', 'p99');
        perform institution_member_add('megacorp', 'p100');
        select institution_members('corp') into data;
        assert data->>'group_name' = 'corp-group';
        assert data->'transitive_members'->0->>'group_member' = 'p100-group';
        assert json_array_length(data->'ultimate_members') = 2;

        -- institutional groups, adding
        perform institution_group_add('megacorp', 'megacorp-admin-group');
        select institution_groups('megacorp') into data;
        assert json_array_length(data->'group_affiliates') = 1;

        -- projects, adding
        perform project_group_add('p99', 'p99-admin-group');
        perform project_group_add('p99', 'p99-weirdo-group');
        perform project_group_add('p100', 'p100-admin-group');
        select project_groups('p99') into data;
        assert json_array_length(data->'group_affiliates') = 2;
        select project_institutions('p99') into data;
        assert json_array_length(data->'institutions') = 2;

        -- group affiliations
        -- adding
        insert into group_affiliations values ('megacorp-admin-group', 'p99-admin-group');
        insert into group_affiliations values ('megacorp-admin-group', 'p100-admin-group');
        select group_affiliates('megacorp-admin-group') into data;
        assert json_array_length(data->'group_affiliates') = 2, 'issue: group_affiliates';
        select group_affiliations('p99-admin-group') into data;
        assert json_array_length(data->'group_affiliations') = 2, 'issue: group_affiliations';
        -- removing
        delete from group_affiliations
            where parent_group = 'megacorp-admin-group'
            and child_group = 'p100-admin-group';
        select group_affiliates('megacorp-admin-group') into data;
        assert json_array_length(data->'group_affiliates') = 1, 'issue: group_affiliates';
        select group_affiliations('p100-admin-group') into data;
        assert json_array_length(data->'group_affiliations') = 1, 'issue: group_affiliations';

        -- projects groups, removing
        perform project_group_remove('p99', 'p99-weirdo-group');
        select project_groups('p99') into data;
        assert json_array_length(data->'group_affiliates') = 1;

        -- institutional groups, removing
        perform institution_group_remove('megacorp', 'megacorp-admin-group');
        select institution_groups('megacorp') into data;
        assert data->>'group_affiliates' is null;

        -- institutions, remove projects
        perform institution_member_remove('megacorp', 'p100');
        select institution_members('megacorp') into data;
        assert json_array_length(data->'ultimate_members') = 1;

        -- presence in audit tables
        assert (select count(*) from audit_log_relations
                where table_name = 'group_affiliations') > 0,
            'affiliations - audit issue ';

        -- group_affiliations table constraints
        -- with itself
        begin
            insert into group_affiliations values ('p99-admin-group', 'p99-admin-group');
            assert false, 'possible to affiliate a group with itself';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- inactive
        begin
            update groups set group_activated = 'f'
                where group_name = 'p99-admin-group';
            insert into group_affiliations values ('p99-admin-group', 'p99-weirdo-group');
            assert false, 'possible to use inactive group as parent in affiliation';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_activated = 'f'
                where group_name = 'p99-admin-group';
            insert into group_affiliations values ('p99-weirdo-group', 'p99-admin-group');
            assert false, 'possible to use inactive group as child in affiliation';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- expired
        begin
            update groups set group_expiry_date = '2000-01-01'
                where group_name = 'p99-admin-group';
            insert into group_affiliations values ('p99-admin-group', 'p99-weirdo-group');
            assert false, 'possible to use expired group as parent in affiliation';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            update groups set group_expiry_date = '2000-01-01'
                where group_name = 'p99-admin-group';
            insert into group_affiliations values ('p99-weirdo-group', 'p99-admin-group');
            assert false, 'possible to use expired group as child in affiliation';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- circular
        begin
            insert into group_affiliations values ('p99-weirdo-group', 'p99-admin-group');
            insert into group_affiliations values ('p99-admin-group', 'p99-weirdo-group');
            assert false, 'can create circular affiliations';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- immutable
        begin
            insert into group_affiliations values ('p100-admin-group', 'p99-admin-group');
            update group_affiliations set parent_group = 'p99-weirdo-group'
                where parent_group = 'p100-admin-group'
                and child_group = 'p99-admin-group';
            assert false, 'parent_group is mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        begin
            insert into group_affiliations values ('p100-admin-group', 'p99-admin-group');
            update group_affiliations set child_group = 'p99-weirdo-group'
                where parent_group = 'p100-admin-group'
                and child_group = 'p99-admin-group';
            assert false, 'child_group is mutable';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;
        -- group existence
        begin
            insert into group_affiliations values ('lolcat', 'lol');
            assert false, 'non-existent groups can be used in affiliations';
        exception when integrity_constraint_violation then
            raise notice '%', sqlerrm;
        end;

        delete from institutions where institution_name like 'mega%';
        delete from projects where project_number in ('p99', 'p100');
        delete from groups where group_name like 'p99-%' or group_name like 'p100-%' or group_name = 'megacorp-admin-group';
        return true;
    end;
$$ language plpgsql;


create or replace function test_cascading_deletes(keep_data boolean default 'false')
    returns boolean as $$
    begin
        if keep_data = 'true' then
            -- if KEEP_TEST_DATA is set to true this will not run
            -- this can be handy for keeping test data in the DB
            -- for interactive test and dev purposes
            raise info 'Keeping test data';
            return true;
        end if;
        -- otherwise we delete all of it, and check test_cascading_deletes
        raise info 'deleting existing data';
        delete from persons;
        delete from groups;
        delete from audit_log_objects;
        delete from audit_log_relations;
        delete from capabilities_http_grants;
        delete from capabilities_http;
        delete from institutions;
        delete from projects;
        return true;
    end;
$$ language plpgsql;


create or replace function check_no_data(del_existing boolean default 'false')
    returns boolean as $$
    declare ans boolean;
    begin
        -- by default, tests can only be run when _all_ tables are empty
        -- to help mitigate a tragic production accident
        if del_existing = 'true' then
            select test_cascading_deletes(false) into ans;
        end if;
        assert (select count(*) from persons) = 0, 'persons not empty';
        assert (select count(*) from users) = 0, 'users not empty';
        assert (select count(*) from groups) = 0, 'groups not empty';
        assert (select count(*) from capabilities_http) = 0, 'capabilities_http not empty';
        assert (select count(*) from capabilities_http_grants) = 0, 'capabilities_http_grants not empty';
        assert (select count(*) from institutions) = 0, 'institutions not empty';
        assert (select count(*) from projects) = 0, 'projects not empty';
        return true;
    end;
$$ language plpgsql;


select check_no_data(:del_data);
select test_persons_users_groups();
select test_group_memeberships_moderators();
select test_group_membership_constraints();
select test_capabilities_http();
select test_audit();
select test_capability_instances();
select test_funcs();
select test_institutions();
select test_projects();
select test_organisations();
select test_cascading_deletes(:keep_test);

drop function if exists check_no_data(boolean);
drop function if exists test_persons_users_groups();
drop function if exists test_group_memeberships_moderators();
drop function if exists test_group_membership_constraints();
drop function if exists test_capabilities_http();
drop function if exists test_audit();
drop function if exists test_funcs();
drop function if exists test_institutions();
drop function if exists test_projects();
drop function if exists test_organisations;
drop function if exists test_cascading_deletes(boolean);
