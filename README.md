
# pg-idp

A generic database backend for use in IdPs.

# Features

- create persons, users, and groups with optional expiry dates
- add users and/or groups to groups
- add persons without users to groups, for external account access control management
- allow groups to moderate memberships of other groups
- create capabilities, specify criteria for obtaining them
- specify the scope of the capabilities
- data integrity and consistency, immutable columns wherever possible
- audit log on all updates
- use SQL functions to get authorization related information for application development

# Usage

Read the guide on how to install and run tests.

```bash
git clone git@github.com:leondutoit/pg-idp.git
cd pg-idp
./install.sh --guide
```

# Learn more

Read the [docs](https://github.com/leondutoit/pg-idp/tree/master/docs).

# LICENSE

BSD.
