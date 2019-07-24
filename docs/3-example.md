
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

### Create persons, users, groups

First we will create two persons, each with one account, and two groups which we will use to enforce access control policies.

```sql
-- the first person
insert into persons (given_names, surname, person_expiry_date)
    values ('Salvador', 'Dali', '2050-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where surname = 'Dali'), 'p11-dali', '2040-12-01');
-- the second person
insert into persons (given_names, surname, person_expiry_date)
    values ('Andre', 'Breton', '2050-10-01');
insert into users (person_id, user_name, user_expiry_date)
    values ((select person_id from persons where surname = 'Breton'), 'p11-abtn', '2050-01-01');
-- the groups
insert into groups (group_name, group_class, group_type)
    values ('p11-surrealist-group', 'secondary', 'generic');
insert into groups (group_name, group_class, group_type)
    values ('p11-art-group', 'secondary', 'generic');
```

Each person has an automatically created person group, and is activated by default.

```txt
tsd_idp=> select person_id, person_activated, person_expiry_date, person_group surname from persons;
              person_id               | person_activated | person_expiry_date |                  surname
--------------------------------------+------------------+--------------------+--------------------------------------------
 834e1830-1cc9-45b1-9e2d-cf5ba9a98d71 | t                | 2050-10-01         | 834e1830-1cc9-45b1-9e2d-cf5ba9a98d71-group
 1bdc3b7b-0687-4740-a699-8aea94cacc1e | t                | 2050-10-01         | 1bdc3b7b-0687-4740-a699-8aea94cacc1e-group
```

Users also have automatically created groups, activation statuses, and expiry dates have been set.

```txt
tsd_idp=> select person_id, user_name, user_group, user_activated, user_expiry_date from users;
              person_id               | user_name |   user_group   | user_activated | user_expiry_date
--------------------------------------+-----------+----------------+----------------+------------------
 834e1830-1cc9-45b1-9e2d-cf5ba9a98d71 | p11-dali  | p11-dali-group | t              | 2040-12-01
 1bdc3b7b-0687-4740-a699-8aea94cacc1e | p11-abtn  | p11-abtn-group | t              | 2050-01-01
```

The automatically created groups are present in the `groups` table, while the group we created is also there. The person and user groups are `primary`, and have `group_primary_member`s, while the created groups are `secondary` and have no `group_primary_member`. In this case, neither have expiry dates set.

```txt
tsd_idp=> select group_name, group_class, group_type, group_activated, group_expiry_date, group_primary_member from groups;
                 group_name                 | group_class | group_type | group_activated | group_expiry_date |         group_primary_member
--------------------------------------------+-------------+------------+-----------------+-------------------+--------------------------------------
 834e1830-1cc9-45b1-9e2d-cf5ba9a98d71-group | primary     | person     | t               | 2050-10-01        | 834e1830-1cc9-45b1-9e2d-cf5ba9a98d71
 p11-dali-group                             | primary     | user       | t               | 2040-12-01        | p11-dali
 p11-surrealist-group                       | secondary   | generic    | t               |                   |
 1bdc3b7b-0687-4740-a699-8aea94cacc1e-group | primary     | person     | t               | 2050-10-01        | 1bdc3b7b-0687-4740-a699-8aea94cacc1e
 p11-abtn-group                             | primary     | user       | t               | 2050-01-01        | p11-abtn
 p11-art-group                              | secondary   | generic    | t               |                   |
```

### Set up group memberships, and moderators

We want `Dali` to be in the `surrealist` group directly, but `Breton` will be included only via his membership to the `art` group. Using the helper function `group_member_add` has the advantage of allowing us to use user names to specify who we want to include in the group. In the implementation, only groups are members of other groups, so one could also simple insert the values into the `group_memberships` table if the application so pleased. Be that as it may, we proceed as follows:

```sql
select group_member_add('p11-surrealist-group', 'p11-dali');
select group_member_add('p11-art-group', 'p11-abtn');
select group_member_add('p11-surrealist-group', 'p11-art-group');
```

We have now created a graph of members. If we want to get the information about this graph, and all the members of the root node of `p11-surrealist-group`, then we can use the helper function `group_members`:

```txt
select group_members('p11-surrealist-group');
-----------------------------------------------
 {                                            +
     "direct_members": [                      +
         {                                    +
             "group": "p11-surrealist-group", +
             "activated": true,               +
             "expiry_date": null,             +
             "group_member": "p11-dali-group",+
             "primary_member": "p11-dali"     +
         },                                   +
         {                                    +
             "group": "p11-surrealist-group", +
             "activated": true,               +
             "expiry_date": null,             +
             "group_member": "p11-art-group", +
             "primary_member": null           +
         }                                    +
     ],                                       +
     "ultimate_members": [                    +
         "p11-abtn",                          +
         "p11-dali"                           +
     ],                                       +
     "transitive_members": [                  +
         {                                    +
             "group": "p11-art-group",        +
             "activated": true,               +
             "expiry_date": null,             +
             "group_member": "p11-abtn-group",+
             "primary_member": "p11-abtn"     +
         }                                    +
     ]                                        +
 }
```

If one is only interested in who the members are, regardless of the graph, then one can read the entries of the `ultimate_members` array. Otherwise one can refer to both `direct_members` and `transitive_members` for the full graph information. Via this one can also see whether any group in the graoh has been deactivcated or expired, and take action accordingly.

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
