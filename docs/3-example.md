
# pg-iam in action

This example will demonstrate all the features mentioned in the `README`:

- create persons, users, and groups with optional expiry dates
- add users and/or groups to groups, using temporal constraints where needed
- allow groups to moderate memberships of other groups
- create capabilities, specify criteria for obtaining them
- specify the scope of the capabilities
- data integrity and consistency, immutable columns wherever possible
- audit log on all updates
- use SQL functions to get authorization related information for application development

# Use case 1: user access control

Suppose we have three users: Salvador Dali, Andre Breton, and Juan Miro. We now want Andre to have access to our whole art collection, but to restrict Salvador's access to surrealism only. Additionally, we want Juan to have the same access as Andre, but the additional right to determine who can have these different levels of access in the future. Let's see how to accomplish this.

### Create persons, users, groups

First we will create two persons, each with one account, and two groups which we will use to enforce access control policies.

```sql
set session "session.identity" = 'tester';
-- persons, users
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
```

Each person has an automatically created person group, and is activated by default.

```txt
select person_id, person_activated, person_expiry_date, person_group, full_name from persons;
              person_id               | person_activated |   person_expiry_date   |                person_group                |   full_name
--------------------------------------+------------------+------------------------+--------------------------------------------+---------------
 38d49b94-26ae-45cd-b654-52d4c455561f | t                | 2050-10-01 00:00:00+02 | 38d49b94-26ae-45cd-b654-52d4c455561f-group | Salvador Dali
 d2de6e6f-48aa-4617-9b00-f26e702cafd9 | t                | 2050-10-01 00:00:00+02 | d2de6e6f-48aa-4617-9b00-f26e702cafd9-group | Andre Breton
 46dc5c2b-65ac-4b10-b6d2-39e48208897e | t                | 2060-10-01 00:00:00+02 | 46dc5c2b-65ac-4b10-b6d2-39e48208897e-group | Juan Miro
```

Users also have automatically created groups, activation statuses, and expiry dates have been set.

```txt
tsd_idp=> select person_id, user_name, user_group, user_activated, user_expiry_date from users;
              person_id               | user_name | user_group | user_activated |    user_expiry_date
--------------------------------------+-----------+------------+----------------+------------------------
 38d49b94-26ae-45cd-b654-52d4c455561f | dali      | dali-group | t              | 2040-12-01 00:00:00+01
 d2de6e6f-48aa-4617-9b00-f26e702cafd9 | abtn      | abtn-group | t              | 2050-01-01 00:00:00+01
 46dc5c2b-65ac-4b10-b6d2-39e48208897e | jm        | jm-group   | t              | 2050-01-01 00:00:00+01
```

The automatically created groups are present in the `groups` table, while the group we created is also there. The person and user groups are `primary`, and have `group_primary_member`s, while the created groups are `secondary` and have no `group_primary_member`. In this case, neither have expiry dates set.

```txt
select group_name, group_class, group_type, group_activated, group_expiry_date, group_primary_member from groups;
                 group_name                 | group_class | group_type | group_activated |   group_expiry_date    |         group_primary_member
--------------------------------------------+-------------+------------+-----------------+------------------------+--------------------------------------
 38d49b94-26ae-45cd-b654-52d4c455561f-group | primary     | person     | t               | 2050-10-01 00:00:00+02 | 38d49b94-26ae-45cd-b654-52d4c455561f
 dali-group                                 | primary     | user       | t               | 2040-12-01 00:00:00+01 | dali
 d2de6e6f-48aa-4617-9b00-f26e702cafd9-group | primary     | person     | t               | 2050-10-01 00:00:00+02 | d2de6e6f-48aa-4617-9b00-f26e702cafd9
 abtn-group                                 | primary     | user       | t               | 2050-01-01 00:00:00+01 | abtn
 46dc5c2b-65ac-4b10-b6d2-39e48208897e-group | primary     | person     | t               | 2060-10-01 00:00:00+02 | 46dc5c2b-65ac-4b10-b6d2-39e48208897e
 jm-group                                   | primary     | user       | t               | 2050-01-01 00:00:00+01 | jm
 surrealist-group                           | secondary   | generic    | t               |                        |
 art-group                                  | secondary   | generic    | t               |                        |
 admin-group                                | secondary   | generic    | t               |                        |      |                   |
```

### Set up group memberships, and moderators

We want `Dali` to be in the `surrealist` group directly, but `Breton` will be included only via his membership to the `art` group. Let's suppose that the members of the `art` group should only have access to the resources protected by the `surrealist` group on Mondays between 08:00 and 17:00 (imagine they are expensive consultants who work by the hour). Let's further suppose that they are all employed for a time limited period. The `admin` group is also time limited, but can access the resources any time of day, any day of the week. We can then use temporal constraints on group membership to enforce these restrictions.

Using the helper function `group_member_add` has the advantage of allowing us to use user names to specify who we want to include in the group. We can also (optionally) pass temporal constraint paremeters along with the membership specification.

In the implementation, only groups are members of other groups, so one could also simple insert the values into the `group_memberships` table if the application so pleased. Be that as it may, we proceed as follows:

```sql
select group_member_add('surrealist-group', 'dali');
select group_member_add('art-group', 'abtn', '2020-01-11', '2030-10-01', '{"mon": {"start": "08:00", "end": "17:00"}}'::jsonb);
select group_member_add('admin-group', 'jm');
select group_member_add('surrealist-group', 'art-group');
select group_member_add('art-group', 'admin-group', '2020-01-11', '2030-10-01');
insert into group_moderators (group_name, group_moderator_name) values ('art-group', 'admin-group');
insert into group_moderators (group_name, group_moderator_name) values ('surrealist-group', 'admin-group');
```

We have now created a graph of members. If we want to get the information about this graph, and all the members of the root node of `p11-surrealist-group`, then we can use the helper function `group_members`:

```txt
select group_members('surrealist-group');
-----------------------------------------------------------
 {                                                        +
     "group_name": "surrealist-group",                    +
     "direct_members": [                                  +
         {                                                +
             "group": "surrealist-group",                 +
             "activated": true,                           +
             "constraints": {                             +
                 "end_date": null,                        +
                 "weekdays": null,                        +
                 "start_date": null                       +
             },                                           +
             "expiry_date": null,                         +
             "group_member": "dali-group",                +
             "primary_member": "dali"                     +
         },                                               +
         {                                                +
             "group": "surrealist-group",                 +
             "activated": true,                           +
             "constraints": {                             +
                 "end_date": null,                        +
                 "weekdays": null,                        +
                 "start_date": null                       +
             },                                           +
             "expiry_date": null,                         +
             "group_member": "art-group",                 +
             "primary_member": null                       +
         }                                                +
     ],                                                   +
     "ultimate_members": [                                +
         "abtn",                                          +
         "dali",                                          +
         "jm"                                             +
     ],                                                   +
     "transitive_members": [                              +
         {                                                +
             "group": "art-group",                        +
             "activated": true,                           +
             "constraints": {                             +
                 "end_date": "2030-10-01T00:00:00+02:00", +
                 "weekdays": {                            +
                     "mon": {                             +
                         "end": "17:00",                  +
                         "start": "08:00"                 +
                     }                                    +
                 },                                       +
                 "start_date": "2020-01-11T00:00:00+01:00"+
             },                                           +
             "expiry_date": null,                         +
             "group_member": "abtn-group",                +
             "primary_member": "abtn"                     +
         },                                               +
         {                                                +
             "group": "admin-group",                      +
             "activated": true,                           +
             "constraints": {                             +
                 "end_date": null,                        +
                 "weekdays": null,                        +
                 "start_date": null                       +
             },                                           +
             "expiry_date": null,                         +
             "group_member": "jm-group",                  +
             "primary_member": "jm"                       +
         },                                               +
         {                                                +
             "group": "art-group",                        +
             "activated": true,                           +
             "constraints": {                             +
                 "end_date": "2030-10-01T00:00:00+02:00", +
                 "weekdays": null,                        +
                 "start_date": "2020-01-11T00:00:00+01:00"+
             },                                           +
             "expiry_date": null,                         +
             "group_member": "admin-group",               +
             "primary_member": null                       +
         }                                                +
     ]                                                    +
 }
```

If one is only interested in who the members are, regardless of the graph, then one can read the entries of the `ultimate_members` array. Otherwise one can refer to both `direct_members` and `transitive_members` for the full graph information, including temporal constraints. Via this one can also see whether any group in the graoh has been deactivcated or expired, and take action accordingly. It is also possible to apply filtering based on the membership constraints when calling the `group_members` function. See `2-db-structure.md` for details of the function signature.

We can also see the group moderators:

```txt
select group_moderators('surrealist-group');
                group_moderators
-----------------------------------------
 {                                      +
     "group_name": "surrealist-group",  +
     "group_moderators": [              +
         {                              +
             "activated": true,         +
             "moderator": "admin-group",+
             "expiry_date": null        +
         }                              +
     ]                                  +
 }

select group_moderators('art-group');
                group_moderators
-----------------------------------------
 {                                      +
     "group_name": "art-group",         +
     "group_moderators": [              +
         {                              +
             "activated": true,         +
             "moderator": "admin-group",+
             "expiry_date": null        +
         }                              +
     ]                                  +
 }
```

Which means that Juan Miro can administer all access, in addition to having those accesses himself. Next we can use these groups to set up our desired access control.

### Specify HTTP capabilities

Suppose we have an HTTP API serving data from an art collection, containing surrealist works. We want to restrict what Dali can see to this part, and let Andre and Juan see everything. At the same time anyone can create art works in the collection. To do that we will create three capabilities, each requiring membership of different groups (or none at all):

```sql
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
```

To get an overview:

```txt
select capability_name, capability_required_groups, capability_lifetime, capability_expiry_date from capabilities_http;
 capability_name |        capability_required_groups        | capability_lifetime | capability_expiry_date
-----------------+------------------------------------------+---------------------+------------------------
 surrealism      | {surrealist-group,art-group,admin-group} |                  30 | 2020-10-01
 art             | {art-group,admin-group}                  |                  30 | 2030-10-01
 maker           |                                          |                  30 |
```

Lastly, we need to create grants tied to these new capabilities:

```sql
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
```

Here we are specifying that the `surrealism` capability can perform a HTTP `GET` on any URI that matches the regex: `/art/surrealism/(.*)` on `api.com`, and so forth.

To get an overview:

```txt
select capability_names_allowed, capability_grant_http_method, capability_grant_uri_pattern from capabilities_http_grants;
 capability_names_allowed | capability_grant_http_method | capability_grant_uri_pattern
--------------------------+------------------------------+------------------------------
 {surrealism}             | GET                          | /art/surrealism/(.*)
 {art}                    | GET                          | /art/(.*)
 {maker}                  | PUT                          | /art/works/.+
```

In the authentication and authorization server, tokens can be issued to the identities based on their group memberships. The `user_groups` function would be helpful in that case. E.g.:

```txt
tsd_idp=> select user_groups('jm');
--------------------------------------------------------------
 {                                                           +
     "user_name": "jm",                                      +
     "user_groups": [                                        +
         {                                                   +
             "constraints": {                                +
                 "end_date": null,                           +
                 "weekdays": null,                           +
                 "start_date": null                          +
             },                                              +
             "member_name": "art-group",                     +
             "member_group": "surrealist-group",             +
             "group_activated": true,                        +
             "group_expiry_date": null                       +
         },                                                  +
         {                                                   +
             "constraints": {                                +
                 "end_date": "2030-10-01T00:00:00+02:00",    +
                 "weekdays": null,                           +
                 "start_date": "2020-01-11T00:00:00+01:00"   +
             },                                              +
             "member_name": "admin-group",                   +
             "member_group": "art-group",                    +
             "group_activated": true,                        +
             "group_expiry_date": null                       +
         },                                                  +
         {                                                   +
             "constraints": {                                +
                 "end_date": null,                           +
                 "weekdays": null,                           +
                 "start_date": null                          +
             },                                              +
             "member_name": "jm-group",                      +
             "member_group": "admin-group",                  +
             "group_activated": true,                        +
             "group_expiry_date": null                       +
         },                                                  +
         {                                                   +
             "constraints": {                                +
                 "end_date": null,                           +
                 "weekdays": null,                           +
                 "start_date": null                          +
             },                                              +
             "member_name": "jm",                            +
             "member_group": "jm-group",                     +
             "group_activated": true,                        +
             "group_expiry_date": "2050-01-01T00:00:00+01:00"+
         }                                                   +
     ]                                                       +
 }
```

It is also possible to apply filtering based on the membership constraints when calling the `user_groups` function. See `2-db-structure.md` for details of the function signature.

When these tokens are used in subsequent requests for resource access, then the capabilities can be inspected to see if they allow the request to go ahead. It is also possible to get an overview of which URIs a person has access to, via their group memberships (mediated via their access to capabilities):

```
select person_access((select person_id::text from users where user_name = 'dali'));

----------------------------------------------------------------
 {                                                                                  +
     "person_id": "ca079e2b-5916-45da-904a-601dcb147957",                           +
     "groupless_access": {                                                          +
         "group_name": null,                                                        +
         "constraints": {                                                           +
             "end_date": null,                                                      +
             "weekdays": null,                                                      +
             "start_date": null                                                     +
         },                                                                         +
         "group_activated": null,                                                   +
         "capabilities_http": [                                                     +
             "maker"                                                                +
         ],                                                                         +
         "group_expiry_date": null,                                                 +
         "capabilities_http_grants": [                                              +
             {                                                                      +
                 "capability_grant_name": "make_art",                               +
                 "capability_names_allowed": [                                      +
                     "maker"                                                        +
                 ],                                                                 +
                 "capability_grant_hostnames": [                                    +
                     "api.com"                                                      +
                 ],                                                                 +
                 "capability_grant_http_method": "PUT",                             +
                 "capability_grant_uri_pattern": "/art/works/.+",                   +
                 "capability_grant_required_groups": null                           +
             }                                                                      +
         ]                                                                          +
     },                                                                             +
     "person_group_access": {                                                       +
         "person_id": "ca079e2b-5916-45da-904a-601dcb147957",                       +
         "person_capabilities": null                                                +
     },                                                                             +
     "users_groups_access": [                                                       +
         {                                                                          +
             "user_name": "dali",                                                   +
             "user_capabilities": [                                                 +
                 {                                                                  +
                     "group_name": "surrealist-group",                              +
                     "constraints": {                                               +
                         "end_date": null,                                          +
                         "weekdays": null,                                          +
                         "start_date": null                                         +
                     },                                                             +
                     "group_activated": true,                                       +
                     "capabilities_http": [                                         +
                         "surrealism"                                               +
                     ],                                                             +
                     "group_expiry_date": null,                                     +
                     "capabilities_http_grants": [                                  +
                         {                                                          +
                             "capability_grant_name": "get_surreal_things",         +
                             "capability_names_allowed": [                          +
                                 "surrealism"                                       +
                             ],                                                     +
                             "capability_grant_hostnames": [                        +
                                 "api.com"                                          +
                             ],                                                     +
                             "capability_grant_http_method": "GET",                 +
                             "capability_grant_uri_pattern": "/art/surrealism/(.*)",+
                             "capability_grant_required_groups": null               +
                         }                                                          +
                     ]                                                              +
                 }                                                                  +
             ]                                                                      +
         }                                                                          +
     ]                                                                              +
 }
```

Looking at `users_groups_access`, we see that `dali`'s membership to the `surrealist-group` gives him access to the `surrealism` capability, which allows `GET` on `/art/surrealism/(.*)` at `api.com`. Looking at `group_less_access`, we see that he (and potentially anyone) has access to the `maker` capability, which allows `PUT` on `/art/works/.+` at `api.com`. He has no access via `person_group_access` - that is, his person group is not a member of any group. For any group, the membership contraints are also displayed, along with the group activation status.

In this way, group memberships can be used along with capabilities and grants to specify access control rules for HTTP APIs. The `person_access` function also accepts optional parameters for filtering group memberships based on temporal constraints. See `2-db-structure.md` for details of the function signature.

# Use case 2: external user rights management

What if another person needs access to our collection, but they do not have an user account with us? We can simply create a person object for them and then add their person group to the appropriate group. If we have integrated with the external IdP, we can request ID information from them, and grant capabilities as access tokens.

# Use case 3: Audit

Identity, Authentication and Authorization information is sensitive, and having an audit trail for all changes is essential. What if, for example someone changed the scope of access associated with a narrow capability to a broad one?

```sql
update capabilities_http_grants set capability_grant_uri_pattern = '/art/(.*)' where capability_grant_name = 'get_surreal_things';
```

Then using the audit log table, one can identify who made the change, and when:

```txt
select * from audit_log_objects where row_id = (select row_id from capabilities_http_grants where capability_grant_name = 'get_surreal_things') and operation = 'UPDATE';
 identity | operation |          event_time           |        table_name        |                row_id                |         column_name          |       old_data       | new_data
----------+-----------+-------------------------------+--------------------------+--------------------------------------+------------------------------+----------------------+-----------
 tester   | UPDATE    | 2023-03-20 21:26:29.283853+01 | capabilities_http_grants | 83af4588-702b-417e-bd46-7c16770d5639 | capability_grant_uri_pattern | /art/surrealism/(.*) | /art/(.*)
 ```

The `audit_log_relations` table shows all changes made to group members and moderators, e.g.:

```txt
select * from audit_log_relations;
 identity | operation |          event_time           |    table_name     |      parent      |    child    |       start_date       |        end_date        |                  weekdays
----------+-----------+-------------------------------+-------------------+------------------+-------------+------------------------+------------------------+---------------------------------------------
 tester   | DELETE    | 2023-03-20 21:29:23.554206+01 | group_memberships | art-group        | admin-group | 2020-01-11 00:00:00+01 | 2030-10-01 00:00:00+02 |
 tester   | INSERT    | 2023-03-20 21:29:30.534212+01 | group_memberships | art-group        | admin-group |                        |                        |
```
