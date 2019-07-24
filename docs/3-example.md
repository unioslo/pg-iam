
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

# Use case 1: external user rights management

## Create persons, users, groups

```sql

```

## Set up group membershpips, and moderators

```sql

```

## Specify HTTP capabilities

```sql

```

# Use case 2: user access control

## Create persons, users, groups

```sql

```

## Set up group membershpips, and moderators

```sql

```

## Specify HTTP capabilities

```sql

```

## Use functions for authorization decisions

```sql

```

# Use case 3: Audit

## Inspect the audit log

```sql

```
