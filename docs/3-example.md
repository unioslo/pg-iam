
# pg-idp in action

This example will demonstrate all the features mentioned in the `README`:

- create persons, users, and groups with optional expiry dates
- add users and/or groups to groups
- add persons without users to groups, for external account access control management
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
-- persons, users
insert into persons (given_names, surname, person_expiry_date)
    values ('Salvador', 'Dali', '2050-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where surname = 'Dali'), 'dali', '2040-12-01');
insert into persons (given_names, surname, person_expiry_date)
    values ('Andre', 'Breton', '2050-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where surname = 'Breton'), 'abtn', '2050-01-01');
insert into persons (given_names, surname, person_expiry_date)
    values ('Juan', 'Miro', '2060-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where surname = 'Miro'), 'jm', '2050-01-01');
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
tsd_idp=> select person_id, person_activated, person_expiry_date, person_group, surname from persons;
              person_id               | person_activated | person_expiry_date |                person_group                | surname
--------------------------------------+------------------+--------------------+--------------------------------------------+---------
 b020efd0-3a98-4d2c-8d3f-7f94a3e3ec31 | t                | 2050-10-01         | b020efd0-3a98-4d2c-8d3f-7f94a3e3ec31-group | Dali
 a38732da-4eff-476e-9fbb-363fd053704b | t                | 2050-10-01         | a38732da-4eff-476e-9fbb-363fd053704b-group | Breton
 a749c99d-ea2c-4d04-8263-5542945bfb80 | t                | 2060-10-01         | a749c99d-ea2c-4d04-8263-5542945bfb80-group | Miro
```

Users also have automatically created groups, activation statuses, and expiry dates have been set.

```txt
tsd_idp=> select person_id, user_name, user_group, user_activated, user_expiry_date from users;
              person_id               | user_name | user_group | user_activated | user_expiry_date
--------------------------------------+-----------+------------+----------------+------------------
 b020efd0-3a98-4d2c-8d3f-7f94a3e3ec31 | dali      | dali-group | t              | 2040-12-01
 a38732da-4eff-476e-9fbb-363fd053704b | abtn      | abtn-group | t              | 2050-01-01
 a749c99d-ea2c-4d04-8263-5542945bfb80 | jm        | jm-group   | t              | 2050-01-01
```

The automatically created groups are present in the `groups` table, while the group we created is also there. The person and user groups are `primary`, and have `group_primary_member`s, while the created groups are `secondary` and have no `group_primary_member`. In this case, neither have expiry dates set.

```txt
tsd_idp=> select group_name, group_class, group_type, group_activated, group_expiry_date, group_primary_member from groups;
                 group_name                 | group_class | group_type | group_activated | group_expiry_date |         group_primary_member
--------------------------------------------+-------------+------------+-----------------+-------------------+--------------------------------------
 b020efd0-3a98-4d2c-8d3f-7f94a3e3ec31-group | primary     | person     | t               | 2050-10-01        | b020efd0-3a98-4d2c-8d3f-7f94a3e3ec31
 dali-group                                 | primary     | user       | t               | 2040-12-01        | dali
 a38732da-4eff-476e-9fbb-363fd053704b-group | primary     | person     | t               | 2050-10-01        | a38732da-4eff-476e-9fbb-363fd053704b
 abtn-group                                 | primary     | user       | t               | 2050-01-01        | abtn
 a749c99d-ea2c-4d04-8263-5542945bfb80-group | primary     | person     | t               | 2060-10-01        | a749c99d-ea2c-4d04-8263-5542945bfb80
 jm-group                                   | primary     | user       | t               | 2050-01-01        | jm
 surrealist-group                           | secondary   | generic    | t               |                   |
 art-group                                  | secondary   | generic    | t               |                   |
 admin-group                                | secondary   | generic    | t               |                   |            |                   |
```

### Set up group memberships, and moderators

We want `Dali` to be in the `surrealist` group directly, but `Breton` will be included only via his membership to the `art` group. Using the helper function `group_member_add` has the advantage of allowing us to use user names to specify who we want to include in the group. In the implementation, only groups are members of other groups, so one could also simple insert the values into the `group_memberships` table if the application so pleased. Be that as it may, we proceed as follows:

```sql
select group_member_add('surrealist-group', 'dali');
select group_member_add('art-group', 'abtn');
select group_member_add('admin-group', 'jm');
select group_member_add('surrealist-group', 'art-group');
select group_member_add('art-group', 'admin-group');
insert into group_moderators (group_name, group_moderator_name) values ('art-group', 'admin-group');
insert into group_moderators (group_name, group_moderator_name) values ('surrealist-group', 'admin-group');
```

We have now created a graph of members. If we want to get the information about this graph, and all the members of the root node of `p11-surrealist-group`, then we can use the helper function `group_members`:

```txt
select group_members('surrealist-group');
--------------------------------------------
 {                                         +
     "direct_members": [                   +
         {                                 +
             "group": "surrealist-group",  +
             "activated": true,            +
             "expiry_date": null,          +
             "group_member": "dali-group", +
             "primary_member": "dali"      +
         },                                +
         {                                 +
             "group": "surrealist-group",  +
             "activated": true,            +
             "expiry_date": null,          +
             "group_member": "art-group",  +
             "primary_member": null        +
         }                                 +
     ],                                    +
     "ultimate_members": [                 +
         "abtn",                           +
         "dali",                           +
         "jm"                              +
     ],                                    +
     "transitive_members": [               +
         {                                 +
             "group": "art-group",         +
             "activated": true,            +
             "expiry_date": null,          +
             "group_member": "abtn-group", +
             "primary_member": "abtn"      +
         },                                +
         {                                 +
             "group": "admin-group",       +
             "activated": true,            +
             "expiry_date": null,          +
             "group_member": "jm-group",   +
             "primary_member": "jm"        +
         },                                +
         {                                 +
             "group": "art-group",         +
             "activated": true,            +
             "expiry_date": null,          +
             "group_member": "admin-group",+
             "primary_member": null        +
         }                                 +
     ]                                     +
 }
```

If one is only interested in who the members are, regardless of the graph, then one can read the entries of the `ultimate_members` array. Otherwise one can refer to both `direct_members` and `transitive_members` for the full graph information. Via this one can also see whether any group in the graoh has been deactivcated or expired, and take action accordingly. We can also see the group moderators:

```txt
tsd_idp=> select group_moderators('surrealist-group');
         group_moderators
----------------------------------
 {"moderators" : ["admin-group"]}

tsd_idp=> select group_moderators('art-group');
         group_moderators
----------------------------------
 {"moderators" : ["admin-group"]}
```

Which means that Juan Miro can administer all access, in addition to having those accesses himself. Next we can use these groups to set up our desired access control.

### Specify HTTP capabilities

Suppose we have an HTTP API serving data from an art collection, containing surrealist works. We want to restrict what Dali can see to this part, and let Andre and Juan see everything. To do that we will create two capabilities, each requiring membership of different groups:

```sql
insert into capabilities_http (
    capability_name, capability_default_claims,
    capability_required_groups, capability_group_match_method,
    capability_lifetime, capability_description, capability_expiry_date)
    values ('surrealism', '{"role": "surrealist_user"}',
            '{"surrealist-group", "art-group", "admin-group"}', 'exact',
            '30', 'surrealist art collection access', '2020-10-01');
insert into capabilities_http (
    capability_name, capability_default_claims,
    capability_required_groups, capability_group_match_method,
    capability_lifetime, capability_description, capability_expiry_date)
    values ('art', '{"role": "art_user"}',
            '{"art-group", "admin-group"}', 'exact',
            '30', 'art collection access', '2030-10-01');
```

To get an overview:

```txt
tsd_idp=> select capability_name, capability_required_groups, capability_lifetime, capability_expiry_date from capabilities_http;
 capability_name |        capability_required_groups        | capability_lifetime | capability_expiry_date
-----------------+------------------------------------------+---------------------+------------------------
 surrealism      | {surrealist-group,art-group,admin-group} |                  30 | 2020-10-01
 art             | {art-group,admin-group}                  |                  30 | 2030-10-01
```

Lastly, we need to connect access grant to these new capabilities:

```sql
insert into capabilities_http_grants (
    capability_id, capability_name,
    capability_http_method, capability_uri_pattern)
    values ((select capability_id from capabilities_http where capability_name = 'surrealism'), 'surrealism', 'GET', '/art/surrealism/(.*)');
insert into capabilities_http_grants (
    capability_id, capability_name,
    capability_http_method, capability_uri_pattern)
    values ((select capability_id from capabilities_http where capability_name = 'art'), 'art', 'GET', '/art/(.*)');
```

To get an overview:

```txt
tsd_idp=> select capability_name, capability_http_method, capability_uri_pattern from capabilities_http_grants;
 capability_name | capability_http_method | capability_uri_pattern
-----------------+------------------------+------------------------
 surrealism      | GET                    | /art/surrealism/(.*)
 art             | GET                    | /art/(.*)
```

In the authentication and authorization server, tokens can be issued to the identities based on their group memberships. The `user_groups` function would be helpful in that case. E.g.:

```txt
tsd_idp=> select user_groups('jm');
-------------------------------------------------
 {                                              +
     "groups": [                                +
         {                                      +
             "member_name": "jm-group",         +
             "member_group": "admin-group",     +
             "group_activated": true,           +
             "group_expiry_date": null          +
         },                                     +
         {                                      +
             "member_name": "admin-group",      +
             "member_group": "art-group",       +
             "group_activated": true,           +
             "group_expiry_date": null          +
         },                                     +
         {                                      +
             "member_name": "art-group",        +
             "member_group": "surrealist-group",+
             "group_activated": true,           +
             "group_expiry_date": null          +
         }                                      +
     ],                                         +
     "user_group": "jm-group"                   +
 }
```

When these tokens are used in subsequent requests for resource access, then the capabilities can be inspected to see if they allow the request to go ahead. In the the latter case, the `capability_grants` function would be useful. E.g.:

```txt
tsd_idp=> select capability_grants('art');
------------------------------------
 [                                 +
     {                             +
         "http_method": "GET",     +
         "uri_pattern": "/art/(.*)"+
     }                             +
 ]
```

# Use case 2: external user rights management

What if another person needs access to our collection, but they do not have an account with us?

# Use case 3: Audit

### Inspect the audit log

```sql

```
