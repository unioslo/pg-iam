
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

```sql

```

### Use functions for authorization decisions

```sql

```

# Use case 2: external user rights management

#### Create persons, users, groups

```sql

```

### Set up group membershpips, and moderators

```sql

```

### Specify HTTP capabilities

```sql

```

# Use case 3: Audit

### Inspect the audit log

```sql

```
