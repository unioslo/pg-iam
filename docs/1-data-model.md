
# Data Model and Rules

```txt
Persons -----> Users ----> Groups (class:primary,   type:user)
  -----------------------> Groups (class:primary,   type:person)
                        -> Groups (class:secondary, type:generic)
                            -> Groups (class:primary or secondary, relations: members, moderators)

Capabilities -> Required Groups
             -> Grants (HTTP)

Grants -> HTTP method
       -> URI pattern
```

- `Persons`: root objects
- `Users`: owned by `Persons`
- `Groups`:
    - `person` groups, class: `primary`, type: `person` and
    - `user` groups, class: `primary`, type: `user` , automatically created, updated, deleted
    - `generic` groups, class: `secondary`, type: `generic`
- Group-to-group relations:
    - member
        - groups can be members of other groups
        - persons and/or user are members of other groups via their person or user groups, not directly
        - this can form Directed Acyclic Graphs
    - moderator
        - groups can moderate other groups, but not transitively or cyclically
- Activation
    - `persons`
        - a person's activation status determines their person group's status
        - if a person is deactivated, then its person group, all its users and their groups, will aslo be deactivated
    - `users`
        - a user's activation status determines their user group's status
        - a user can be inactive while the person it belongs to remains active
    - `groups`
        - secondary groups' activation status can be changed directly
- Expiry dates
    - `persons`
        - a person group's expiry date is the same as the person's expiry date
    - `users`
        - a user group's expiry date is the same as the user's expiry date
        - a user's expiry date cannot be later than the expiry date of the person it belongs to
    - `groups`
        - secondary groups' expiry date can be changed directly
- Capabilities
    - a capability can be obtained by a person or user who is a member of a set of specified requried groups
    - capabilities are linked to grants on resources
    - access control is therefore managed through group membership
- Grants
    - HTTP grants associate an HTTP method and URI pattern with a named capability

# Group membership graphs

Group memberships are Directed Acyclic Graphs, with the additional restriction that any given node can only have one parent.

The following is therefore allowed:

```txt
a -> b -> c
  -> d
```

While this is not:

```txt
a -> b -> c
  -> d -> c
```

Such membership graphs allow implementing granular access on resources organised into tree hierarchies as such:

```txt
folder1
    /folder2
        /folder4
        /folder5
    /folder3
```

One can then have the following membership graph to control access to these folders:

```txt
g1 -> g2 -> g4
         -> g5
   -> g3
```

Where `g1` would have access to `folder1`, `g2` to `folder1`, and `folder2`, `g4` to `folder1`, `folder2`, and `folder4`, and so on.
