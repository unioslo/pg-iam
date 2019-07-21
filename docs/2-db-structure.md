
# DB Structure

## Table overview

Applications can interact with the following tables to build their core IdP, Authentication and Authorization functionality.

```sql
persons
users
groups
group_memberships
group_moderators
capabilities
capabilities_grants
audit_log
```

## Function overview

To ease routine tasks for getting information, `pg-idp` provides a set of helper functions which combine information from various tables.

```sql
person_groups(person_id text)
person_capabilities(person_id text, grants boolean)
person_access(person_id text)
user_groups(user_name text)
user_capabilities(user_name text, grants boolean)
group_members(group_name text)
group_moderators(group_name text)
group_member_add(group_name text, person_id text, user_name text)
group_member_remove(group_name text, person_id text, user_name text)
group_capabilities(group_name text)
capability_grants(capabilities_type text)
```
