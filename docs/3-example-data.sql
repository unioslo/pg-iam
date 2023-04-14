
set session "session.identity" = 'tester';

insert into persons (full_name, person_expiry_date)
    values ('Salvador Dali', '2050-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where full_name like '%Dali'), 'dali', '2040-12-01');
insert into persons (full_name, person_expiry_date)
    values ('Andre Breton', '2050-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where full_name like '%Breton'), 'abtn', '2050-01-01');
insert into persons (full_name, person_expiry_date)
    values ('Juan Miro', '2060-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where full_name like '%Miro'), 'jm', '2050-01-01');
-- the groups
insert into groups (group_name, group_class, group_type)
    values ('surrealist-group', 'secondary', 'generic');
insert into groups (group_name, group_class, group_type)
    values ('art-group', 'secondary', 'generic');
insert into groups (group_name, group_class, group_type)
    values ('admin-group', 'secondary', 'generic');

select person_id, person_activated, person_expiry_date, person_group, full_name from persons;

select person_id, user_name, user_group, user_activated, user_expiry_date from users;

select group_name, group_class, group_type, group_activated, group_expiry_date, group_primary_member from groups;

select group_member_add('surrealist-group', 'dali');
select group_member_add('art-group', 'abtn', '2020-01-11', '2030-10-01', '{"mon": {"start": "08:00", "end": "17:00"}}'::jsonb);
select group_member_add('admin-group', 'jm');
select group_member_add('surrealist-group', 'art-group');
select group_member_add('art-group', 'admin-group', '2020-01-11', '2030-10-01');
insert into group_moderators (group_name, group_moderator_name) values ('art-group', 'admin-group');
insert into group_moderators (group_name, group_moderator_name) values ('surrealist-group', 'admin-group');

select jsonb_pretty(group_members('surrealist-group')::jsonb);

select jsonb_pretty(group_moderators('surrealist-group')::jsonb);

insert into capabilities_http (
    capability_name,
    capability_hostnames,
    capability_required_groups,
    capability_group_match_method,
    capability_lifetime,
    capability_description,
    capability_expiry_date
) values (
    'surrealism',
    '{api.com}',
    '{"surrealist-group", "art-group", "admin-group"}',
    'exact',
    '30',
    'surrealist art collection access',
    '2020-10-01'
);
insert into capabilities_http (
    capability_name,
    capability_hostnames,
    capability_required_groups,
    capability_group_match_method,
    capability_lifetime,
    capability_description,
    capability_expiry_date
) values (
    'art',
    '{api.com}',
    '{"art-group", "admin-group"}',
    'exact',
    '30',
    'art collection access',
    '2030-10-01'
);
insert into capabilities_http (
    capability_name,
    capability_hostnames,
    capability_required_groups,
    capability_group_match_method,
    capability_lifetime,
    capability_description
) values (
    'maker',
    '{api.com}',
    null,
    'exact',
    '30',
    'generic access for creating art works'
);
insert into capabilities_http_grants (
    capability_names_allowed,
    capability_grant_name,
    capability_grant_namespace,
    capability_grant_http_method,
    capability_grant_hostnames,
    capability_grant_uri_pattern
) values (
    '{surrealism}',
    'get_surreal_things',
    'art',
    'GET',
    '{api.com}',
    '/art/surrealism/(.*)'
);
insert into capabilities_http_grants (
    capability_names_allowed,
    capability_grant_name,
    capability_grant_namespace,
    capability_grant_http_method,
    capability_grant_hostnames,
    capability_grant_uri_pattern
) values (
    '{art}',
    'browse_art',
    'art',
    'GET',
    '{api.com}',
    '/art/(.*)'
);
insert into capabilities_http_grants (
    capability_names_allowed,
    capability_grant_name,
    capability_grant_namespace,
    capability_grant_http_method,
    capability_grant_hostnames,
    capability_grant_uri_pattern
) values (
    '{maker}',
    'make_art',
    'art',
    'PUT',
    '{api.com}',
    '/art/works/.+'
);

select capability_name, capability_required_groups, capability_lifetime, capability_expiry_date from capabilities_http;

select capability_names_allowed, capability_grant_http_method, capability_grant_uri_pattern from capabilities_http_grants;

select jsonb_pretty(user_groups('jm')::jsonb);

select jsonb_pretty(person_access((select person_id::text from users where user_name = 'dali'))::jsonb);

update capabilities_http_grants set capability_grant_uri_pattern = '/art/(.*)' where capability_grant_name = 'get_surreal_things';

select * from audit_log_objects
    where row_id = (select row_id from capabilities_http_grants where capability_grant_name = 'get_surreal_things')
    and operation = 'UPDATE';

select * from audit_log_relations;

update groups set group_expiry_date = '2020-01-01' where group_name = 'surrealist-group';

select jsonb_pretty(user_groups('jm')::jsonb);
select jsonb_pretty(user_groups('jm', 't')::jsonb);

select jsonb_pretty(
    person_access(
        (select person_id::text from users where user_name = 'jm'), 't'
    )::jsonb
);

insert into institutions(
    institution_name, institution_long_name, institution_expiry_date
) values (
    'emanate', 'emanate - from which all creativity flows', '3000-01-01'
);
insert into institutions(
    institution_name, institution_long_name, institution_expiry_date
) values (
    'surrealism-inc', 'surrealism incorporated - commoditising your dreams', '2050-10-11'
);
insert into projects(
    project_number, project_name, project_start_date, project_end_date
) values (
    'p0', 'project zero', '2000-12-01', '2080-01-01'
);
insert into projects(
    project_number, project_name, project_start_date, project_end_date
) values (
    'p1', 'project one', '2002-05-18', '2080-01-01'
);
insert into groups (
    group_name, group_class, group_type
) values (
    'surrealism-inc-admin-group', 'secondary', 'web'
);
insert into groups (
    group_name, group_class, group_type
) values (
    'p0-admin-group', 'secondary', 'generic'
);
insert into groups (
    group_name, group_class, group_type
) values (
    'p0-weirdo-group', 'secondary', 'generic'
);

select institution_member_add('emanate', 'surrealism-inc');
select institution_member_add('surrealism-inc', 'p0');
select institution_member_add('surrealism-inc', 'p1');

select jsonb_pretty(institution_members('emanate')::jsonb);

select institution_group_add('surrealism-inc', 'surrealism-inc-admin-group');
select project_group_add('p0', 'p0-admin-group');
select project_group_add('p0', 'p0-weirdo-group');

select jsonb_pretty(institution_groups('surrealism-inc')::jsonb);
select jsonb_pretty(project_groups('p0')::jsonb);

insert into group_affiliations (
    parent_group, child_group
) values (
    'surrealism-inc-admin-group', 'p0-admin-group'
);

select jsonb_pretty(group_affiliates('surrealism-inc-admin-group')::jsonb);
select jsonb_pretty(group_affiliations('p0-admin-group')::jsonb);
