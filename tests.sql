
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
            insert into users (person_id, user_name, uid) values (pid, 'p33-sconne', 0);
            assert false;
        exception when others then
            raise notice 'cannot assign uid between 0 and 999, as expected';
        end;
        begin
            update users set user_posix_uid = '2000' where user_name = 'p11-sconne';
            assert false;
        exception when others then
            raise notice 'uid is immutable';
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
            assert false;
        exception when others then
            raise notice 'cannot assign gid between 0 and 999, as expected';
        end;
        begin
            update groups set group_posix_gid = '2000' where group_name = 'p11-sconne-group';
            assert false;
        exception when others then
            raise notice 'gid is immutable';
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
            assert false;
        exception when others then
            raise notice 'persons identifiers are ensured to be unique';
        end;
        begin
            insert into person (full_name, identifiers)
                values ('Jackson Pollock', '{"k3": 99}'::json);
            assert false;
        exception when others then
            raise notice 'persons identifiers are ensured to be json arrays';
        end;
        -- person attribute immutability
        begin
            update persons set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false;
        exception when others then
            raise notice 'row_id immutable';
        end;
        begin
            update persons set person_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false;
        exception when others then
            raise notice 'person_id immutable';
        end;
        begin
            update persons set person_group = 'e14c538a-4b8b-4393-9fb2-056e363899e1-group';
            assert false;
        exception when others then
            raise notice 'person_group immutable';
        end;
        -- user attribute immutability
        begin
            update users set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false;
        exception when others then
            raise notice 'row_id immutable';
        end;
        begin
            update users set user_id = 'a3981c7f-8e41-4222-9183-1815b6ec9c3b';
            assert false;
        exception when others then
            raise notice 'user_id immutable';
        end;
        begin
            update users set user_name = 'p11-scnr';
            assert false;
        exception when others then
            raise notice 'user_name immutable';
        end;
        begin
            update users set user_group = 'p11-s-group';
            assert false;
        exception when others then
            raise notice 'user_group immutable';
        end;
        -- group attribute immutability
        begin
            update groups set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false;
        exception when others then
            raise notice 'row_id immutable';
        end;
        begin
            update groups set group_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false;
        exception when others then
            raise notice 'group_id immutable';
        end;
        begin
            update groups set group_name = 'p22-lcd-group';
            assert false;
        exception when others then
            raise notice 'group_name immutable';
        end;
        begin
            update groups set group_class = 'secondary';
            assert false;
        exception when others then
            raise notice 'group_class immutable';
        end;
        begin
            update groups set group_type = 'person';
            assert false;
        exception when others then
            raise notice 'group_type immutable';
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
            assert false;
        exception when others then
            raise notice 'cannot remove gids for web groups - as expected';
        end;
        delete from groups where group_name = 'p11-wonderful-group';
        -- states; cascades, constraints
        set session "request.identity" = 'milen';
        update persons set person_activated = 'f';
        assert (select count(*) from users where user_activated = 't') = 0,
            'person state changes not propagating to users';
        assert (select count(*) from groups where group_activated = 't') = 0,
            'person state changes not propagating to groups';
        -- try change group states, expect fail
        -- create secondary group, change state, delete it again
        -- expiry dates: cascades, constraints
        update persons set person_expiry_date = '2019-09-09';
        update users set user_expiry_date = '2000-08-08' where user_name like 'p11-%';
        begin
            update groups set group_expiry_date = '2000-01-01' where group_primary_member = 'p11-sconne';
            assert false;
        exception when others then
            raise notice 'user group exp updates only allowed via primary';
        end;
        begin
            update groups set group_expiry_date = '2000-01-01' where group_primary_member = pid::text;
            assert false;
        exception when others then
            raise notice 'person group exp updates only allowed via primary';
        end;
        -- deletion; cascades, constraints
        begin
            delete from groups where group_type = 'person';
        exception when others then
            raise notice 'person group deletion protected';
        end;
        begin
            delete from groups where group_type = 'user';
        exception when others then
            raise notice 'user group deletion protected';
        end;
        begin
            delete from groups where group_class = 'primary';
        exception when others then
            raise notice 'primary group deletion protected';
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
            insert into group_moderators (group_name, group_member_name)
                values ('p77-clinical-group', 'p11-special-group');
            assert false;
        exception when others then
            raise notice 'group_memberships: referential constraints work';
        end;
        -- redundancy
        begin
            insert into group_memberships (group_name, group_member_name) values ('p11-export-group','p11-publication-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_memberships: redundancy check works';
        end;
        -- cyclicality
        begin
            insert into group_memberships (group_name, group_member_name) values ('p11-publication-group','p11-export-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_memberships: cyclicality check works';
        end;
        begin
            insert into group_memberships (group_name, group_member_name) values ('p11-admin-group','p11-export-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_memberships: cyclicality check works';
        end;
        -- immutability
        begin
            update group_memberships set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false;
        exception when others then
            raise notice 'group_memberships: row_id immutable';
        end;
        begin
            update group_memberships set group_name = 'p11-clinical-group' where group_name = 'p11-special-group';
            assert false;
        exception when others then
            raise notice 'group_memberships: group_name immutable';
        end;
        begin
            update group_memberships set group_member_name = 'p11-clinical-group' where group_name = 'p11-special-group';
            assert false;
        exception when others then
            raise notice 'group_memberships: group_member_name immutable';
        end;
        -- group classes
        begin
            insert into group_memberships values ('p11-sconne-group', 'p11-special-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_memberships: primary groups cannot have new members';
        end;
        -- new relations and group activation state
        begin
            update groups set group_activated = 'f' where group_name = 'p11-import-group';
            insert into group_memberships (group_name, group_member_name) values ('p11-publication-group','p11-import-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_memberships: deactivated groups cannot be used in new relations';
        end;
        -- new relations and group expiry
        begin
            update groups set group_expiry_date = '2017-01-01' where group_name = 'p11-import-group';
            insert into group_memberships (group_name, group_member_name) values ('p11-publication-group','p11-import-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_memberships: expired groups cannot be used in new relations';
        end;
        -- shouldnt be able to be a member of itself
        begin
            insert into group_moderators (group_name, group_member_name)
                values ('p11-special-group', 'p11-special-group');
            assert false;
        exception when others then
            raise notice 'group_memberships: redundancy check - groups cannot be members of themselves';
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
                values ('p77-clinical-group', 'p11-special-group');
            assert false;
        exception when others then
            raise notice 'group_moderators: referential constraints work';
        end;
        -- immutability
        begin
            update group_moderators set row_id = 'e14c538a-4b8b-4393-9fb2-056e363899e1';
            assert false;
        exception when others then
            raise notice 'group_moderators: row_id immutable';
        end;
        begin
            update group_moderators set group_name = 'p11-admin-group' where group_name = 'p11-import-group';
            assert false;
        exception when others then
            raise notice 'group_moderators: group_name immutable';
        end;
        begin
            update group_moderators set group_member_name = 'p11-export-group' where group_name = 'p11-import-group';
            assert false;
        exception when others then
            raise notice 'group_moderators: group_member_name immutable';
        end;
        -- redundancy
        begin
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-clinical-group', 'p11-special-group');
        exception when others then
            raise notice 'group_moderators: redundancy check works - cannot recreate existing relations';
        end;
        -- cyclicality
        begin
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-special-group', 'p11-clinical-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_moderators: cyclicality check works';
        end;
        -- new relations and group activation state
        begin
            update groups set group_activated = 'f' where group_name = 'p11-export-group';
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-export-group', 'p11-admin-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_moderators: deactivated groups cannot be used';
        end;
        -- new relations and group expiry
        begin
            update groups set group_expiry_date = '2011-01-01' where group_name = 'p11-export-group';
            insert into group_moderators (group_name, group_moderator_name)
                values ('p11-export-group', 'p11-admin-group');
            assert false;
        exception when assert_failure then
            raise notice 'group_moderators: expired groups cannot be used';
        end;
        update groups set group_expiry_date = '2011-01-01' where group_name = 'p11-export-group';
        --delete from persons;
        --delete from groups;
        return true;
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
            assert false;
        exception when assert_failure then
            raise notice 'capabilities_http: row_id immutable';
        end;
        begin
            update capabilities_http set capability_id = '35b77cf9-0a6f-49d7-83df-e388d75c4b0b';
            assert false;
        exception when assert_failure then
            raise notice 'capabilities_http: capability_id immutable';
        end;
        -- uniqueness
        begin
            insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date)
                values ('admin', '{api.com}', '{"role": "admin_user"}',
                        '{"admin-group", "special-group"}', 'wildcard',
                        '123', 'bla', current_date);
            assert false;
        exception when others then
            raise notice 'capabilities_http: name uniqueness guaranteed';
        end;
        begin
            update capabilities_http set capability_required_groups = '{self,self}'
                where capability_name = 'admin';
        exception when assert_failure then
            raise notice 'capabilities_http: required groups are guaranteed unique';
        end;
        -- referential constraints
        begin
            insert into capabilities_http (capability_name, capability_hostnames, capability_default_claims,
                                  capability_required_groups, capability_group_match_method,
                                  capability_lifetime, capability_description, capability_expiry_date)
            values ('admin2', '{api.com}', '{"role": "admin_user"}',
                    '{"admin2-group", "very-special-group"}', 'wildcard',
                    '123', 'bla', current_date);
            assert false;
        exception when assert_failure then
            raise notice 'capabilities_http: group must exist to be referenced in new capability';
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
            assert false;
        exception when assert_failure then
            raise notice 'capabilities_http_grants: row_id immutable';
        end;
        begin
            update capabilities_http_grants set capability_grant_id = '35b77cf9-0a6f-49d7-83df-e388d75c4b0b';
            assert false;
        exception when assert_failure then
            raise notice 'capabilities_http_grants: capability_grant_id immutable';
        end;
        -- referential constraints
        begin
            select capability_id from capabilities_http where capability_name = 'export' into cid;
            insert into capabilities_http_grants (capability_names_allowed,
                                                  capability_grant_hostnames, capability_grant_namespace,
                                                  capability_grant_http_method, capability_grant_uri_pattern,
                                                  capability_grant_required_groups)
                                          values ('{export}',
                                                  '{api.com}', 'files',
                                                  'GET', '/(.*)/admin',
                                                  '{"my-own-crazy-group"}');
        exception when assert_failure then
            raise notice 'capabilities_http_grants: required groups need to exist when referenced, by default';
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
            assert false;
        exception when others then
            raise notice 'capabilities_http_grants: cannot set rank to negative - as expected';
        end;
        -- monotonicity
        begin
            select capability_grant_rank_set(grid::text, 9) into ans;
            assert false;
        exception when assert_failure then
            raise notice 'capabilities_http_grants: rank is monotonically increasing - as expected';
        end;
        -- uniqueness
        begin
            insert into capabilities_http_grants (capability_names_allowed,
                                                  capability_grant_hostnames, capability_grant_namespace,
                                                  capability_grant_http_method, capability_grant_uri_pattern,
                                                  capability_grant_required_groups, capability_grant_group_existence_check,
                                                  capability_grant_rank)
                                          values ('{export}'
                                                  '{api.com}', 'files',
                                                  'HEAD', '/(.*)/export',
                                                  '{"my-own-custom-export-group"}', 'f',
                                                  1);
            assert false;
        exception when others then
            raise notice 'capabilities_http_grants: rank values must be unique within their grant sets - as expected';
        end;
        begin
            update capabilities_http_grants set capability_grant_required_groups = '{self,self}'
                where capability_grant_id = grid;
        exception when assert_failure then
            raise notice 'capabilities_http_grants: groups are ensured to be unique';
        end;
        -- reject if grant id not found
        begin
            select capability_grant_rank_set(grid::text, 9) into ans;
            assert false;
        exception when assert_failure then
            raise notice 'capabilities_http_grants: rank is monotonically increasing - as expected';
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
        exception when assert_failure then
            raise notice 'capabilities_http_grants: protection against removing a capability_name, when grants refer only to that name works';
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
        exception when assert_failure then
            raise notice 'automatic deletion of capability instances works';
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
        exception when assert_failure then
            raise notice 'cannot use expired capability instance - as expected';
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
        exception when assert_failure then
            raise notice 'cannot use capability instance before start time - as expected';
        end;
        -- immutable cols
        begin
            update capabilities_http_instances set row_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where instance_id = iid;
        exception when assert_failure then
            raise notice 'capabilities_http_instances: row_id immutable';
        end;
        begin
            update capabilities_http_instances set capability_name = 'parsley'
                where instance_id = iid;
        exception when assert_failure then
            raise notice 'capabilities_http_instances: capability_name immutable';
        end;
        begin
            update capabilities_http_instances set instance_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where instance_id = iid;
        exception when assert_failure then
            raise notice 'capabilities_http_instances: instance_id immutable';
        end;
        return true;
    end;
$$ language plpgsql;


create or replace function test_audit()
    returns boolean as $$
    declare pid uuid;
    declare rid uuid;
    declare msg text;
    begin
        select person_id from persons limit 1 into pid;
        select row_id from persons where person_id = pid into rid;
        update persons set person_activated = 'f' where person_id = pid;
        msg := 'audit_log does not work';
        -- todo: redo this, add relations audit table
        --assert (select old_data from audit_log
          --      where row_id = rid and column_name = 'person_activated') = 'true', msg;
        --assert (select new_data from audit_log
          --      where row_id = rid and column_name = 'person_activated') = 'false', msg;
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
        select person_id from persons where full_name like '%Dali' into pid;
        select group_member_add('p11-surrealist-group', pid::text) into ans;
        select person_groups(pid::text) into data;
        err := 'person_groups issue';
        assert data->>'person_id' = pid::text, err;
        -- person_capabilities
        insert into capabilities_http (
            capability_name, capability_hostnames, capability_default_claims,
            capability_required_groups, capability_group_match_method,
            capability_lifetime, capability_description, capability_expiry_date)
            values ('p11-art', '{api.com}', '{"role": "p11_art_user"}',
                    '{"p11-surrealist-group", "p11-admin-group"}', 'exact',
                    '123', 'bla', current_date);
        insert into capabilities_http_grants (capability_names_allowed,
                                              capability_grant_hostnames, capability_grant_namespace,
                                              capability_grant_http_method, capability_grant_uri_pattern,
                                              capability_grant_required_groups)
                                      values ('{export}',
                                              '{api.com}', 'files',
                                              'GET', '/(.*)/art',
                                              '{surrealist-group}');
        select person_capabilities(pid::text, 't') into data;
        err := 'person_capabilities issue';
        assert data->>'person_id' = pid::text, err;
        assert data->'person_capabilities'->0->>'group_name' = 'p11-surrealist-group', err;
        -- person_access
        err := 'person_access issue';
        select person_access(pid::text) into data;
        assert data->'person_group_access' is not null, err;
        assert data->'user_group_access' is null, err;
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
        assert data->'user_capabilities'->0->'group_capabilities_http'->>0 = 'p11-art', err;
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
        assert data->'group_capabilities_http'->>0 = 'p11-art', err;
        return true;
    end;
$$ language plpgsql;


create or replace function test_institutions()
    returns boolean as $$
    declare grp text;
    begin
        insert into institutions (institution_name, institution_long_name)
            values ('uil', 'University of Leon');
        -- defaults
        assert (select institution_group from institutions
                where institution_name = 'uil') = 'uil-group',
            'institution group name default broken';
        assert (select institution_activated from institutions
                where institution_name = 'uil') = 't',
            'institution activation default broken';
        begin
            update institutions set row_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where institution_name = 'uil';
            assert false, 'institutions: row_id mutable';
        exception when others then
            raise notice 'institutions: row_id immutable';
        end;
        begin
            update institutions set institution_id = '44c23dc9-d759-4c1f-a72e-04e10dbe2523'
                where institution_name = 'uil';
            assert false, 'institutions: institution_id mutable';
        exception when others then
            raise notice 'institutions: institution_id immutable';
        end;
        begin
            update institutions set institution_name = 'liu'
                where institution_name = 'uil';
            assert false, 'institutions: institution_name mutable';
        exception when others then
            raise notice 'institutions: institution_name immutable';
        end;
        begin
            update institutions set institution_group = 'foo-group'
                where institution_name = 'uil';
            assert false, 'institutions: institution_group mutable';
        exception when others then
            raise notice 'institutions: institution_group immutable';
        end;
        -- groups
        select institution_group from institutions
            where institution_name = 'uil' into grp;
        assert (select count(*) from groups where group_name = grp) = 1,
            'institution group not generated correctly';
        assert (select group_type from groups where group_name = grp) = 'web',
            'institution group generated with incorrect type';
        update institutions set institution_activated = 'f' where institution_name = 'uil';
        assert (select group_activated from groups where group_name = grp) = 'f',
            'institution group activation status management not working';
        begin
            update groups set group_activated = 't' where group_name = grp;
            assert false, 'institution group activation mutable on groups';
        exception when others then
            raise notice 'institution group activation not mutable on groups';
        end;
        begin
            update groups set group_expiry_date = '2020-01-01' where group_name = grp;
            assert false, 'institution group_expiry_date mutable on groups';
        exception when others then
            raise notice 'institution group_expiry_date not mutable on groups';
        end;
        return true;
    end;
$$ language plpgsql;


create or replace function test_projects()
    returns boolean as $$
    begin

        -- immutability

        -- groups

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
select test_capabilities_http();
select test_audit();
select test_capability_instances();
select test_funcs();
select test_institutions();
select test_projects();
select test_cascading_deletes(:keep_test);

drop function if exists check_no_data(boolean);
drop function if exists test_persons_users_groups();
drop function if exists test_group_memeberships_moderators();
drop function if exists test_capabilities_http();
drop function if exists test_audit();
drop function if exists test_funcs();
drop function if exists test_institutions();
drop function if exists test_projects();
drop function if exists test_cascading_deletes(boolean);
