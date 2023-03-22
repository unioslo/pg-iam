
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

select group_member_add('surrealist-group', 'dali');
select group_member_add('art-group', 'abtn', '2020-01-11', '2030-10-01', '{"mon": {"start": "08:00", "end": "17:00"}}'::jsonb);
select group_member_add('admin-group', 'jm');
select group_member_add('surrealist-group', 'art-group');
select group_member_add('art-group', 'admin-group', '2020-01-11', '2030-10-01');
insert into group_moderators (group_name, group_moderator_name) values ('art-group', 'admin-group');
insert into group_moderators (group_name, group_moderator_name) values ('surrealist-group', 'admin-group');

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
