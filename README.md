
# pg-iam

A generic database backend for use in IAM APIs.

# Features

- create persons, users, and groups with optional expiry dates, and activation states
- add users and/or groups to groups, specify temporal constraints on memberships
- add persons without users to groups, for external account access control management
- allow groups to moderate memberships of other groups
- affiliate groups with one another
- create capabilities, criteria for obtaining them, use them in access tokens
- specify the scope of the capabilities
- create organisational units and hierarchies with institutions, and projects
- affiliate groups with institutions and projects
- data integrity and consistency, immutable columns wherever possible
- audit log on all inserts, updates, and deletes
- SQL functions for simplified application development

# Usage

Read the guide on how to install and run tests.

```bash
git clone git@github.com:unioslo/pg-iam.git
cd pg-iam
./install.sh --guide
```

# Learn more

Read the [docs](https://github.com/unioslo/pg-iam/tree/master/docs).

# LICENSE

BSD.
