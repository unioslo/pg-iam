
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

First we will create two persons, each with one account, and a group which we will use to enforce access control policies.

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
-- the group
insert into groups (group_name, group_class, group_type)
    values ('p11-surrealist-group', 'secondary', 'generic');
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

The automatically created groups are present in the `groups` table, while the group we created is also there. The person and user groups are `primary`, and have `group_primary_member`s, while the created group is `secondary` and has no `group_primary_member`. In this case, it also has no expiry date.

```txt
tsd_idp=> select group_name, group_class, group_type, group_activated, group_expiry_date, group_primary_member from groups;
                 group_name                 | group_class | group_type | group_activated | group_expiry_date |         group_primary_member
--------------------------------------------+-------------+------------+-----------------+-------------------+--------------------------------------
 834e1830-1cc9-45b1-9e2d-cf5ba9a98d71-group | primary     | person     | t               | 2050-10-01        | 834e1830-1cc9-45b1-9e2d-cf5ba9a98d71
 p11-dali-group                             | primary     | user       | t               | 2040-12-01        | p11-dali
 p11-surrealist-group                       | secondary   | generic    | t               |                   |
 1bdc3b7b-0687-4740-a699-8aea94cacc1e-group | primary     | person     | t               | 2050-10-01        | 1bdc3b7b-0687-4740-a699-8aea94cacc1e
 p11-abtn-group                             | primary     | user       | t               | 2050-01-01        | p11-abtn
```

### Set up group memberships, and moderators

```sql

```

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
