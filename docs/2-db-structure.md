
# DB Structure

## Table overview

Applications can interact with the following tables to build their core IdP, Authentication and Authorization functionality.

```sql
persons
users
groups
group_memberships
group_moderators
capabilities_http
capabilities_http_grants
audit_log
```

To investigate the tables more, it is best to install `pg-iam` and inspect the DB descriptions via `\d`.

## Function overview

To ease routine tasks for getting information, `pg-iam` provides a set of helper functions which combine information from various tables.

```sql
person_groups(person_id text)
/*
    Returns:
    {person_id: '', person_groups: []}
*/

person_capabilities(person_id text, grants boolean)
/*
    Returns:
    {person_id: '', person_capabilities: []}
*/

person_access(person_id text)
/*
    Returns:
    {person_id: '', person_access: {person_group_access: [], users_groups_access: []}}
*/

user_groups(user_name text)
/*
    Returns:
    {user_name: '', user_groups: []}
*/

user_capabilities(user_name text, grants boolean)
/*
    Returns:
    {user_name: '', user_capabilities: []}
*/

group_members(group_name text)
/*
    Returns:
    {direct_members: [], transitive_members: [], ultimate_members: []}
*/

group_moderators(group_name text)
/*
    Returns:
    {group_name: '', group_moderators: []}
*/

group_member_add(group_name text, member text)
/*
    Returns:
    {message: ''}
*/

group_member_remove(group_name text, member text)
/*
    Returns:
    {message: ''}
*/

group_capabilities(group_name text)
/*
    Returns:
    {group_name: '', group_capabilities: []}
*/

capability_grants(capability_name text)
/*
    Returns:
    {capability_name: '', capability_grants: []}
*/
```
