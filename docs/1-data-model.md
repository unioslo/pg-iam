
# Data Model and Rules

```txt
Persons -----> Users ----> Groups (class:primary,   type:user)
  -----------------------> Groups (class:primary,   type:person)
                        -> Groups (class:secondary type:generic,web)
                            -> Groups (class:primary, secondary
                                       relations: members, moderators, affiliates)

Capabilities
  -> Name
  -> Required Groups
  -> linked to
    -> Instances (HTTP)
    -> Grants (HTTP)

Capability Instances
  -> a parameterised Capability

Capability Grants
 -> Host Name
 -> Namespace identifier
 -> HTTP method
 -> URI pattern

Institutions -> Group (class:secondary type:institution)
    -> Groups (class:primary, secondary
               relations: members, affiliates)
Projects     -> Group (class:primay type:project)
    - Groups (class:primary, secondary
              relation: affiliates)

Clients

Client IPs
```

- `Persons`: root objects
- `Users`: owned by `Persons`
- `Groups`:
    - class: `primary`, owned by other objects
        - type: `person`, automatically created, updated, deleted
        - type: `user`, automatically created, updated, deleted
        - type: `project`, automatically created, updated, deleted
    - class: `secondary`
        - type: `institution`, automatically created, updated, deleted
        - type: `generic`, assigned POSIX ID
        - type: `web`, no posix ids
- Group-to-group relations:
    - member
        - groups can be members of other groups
        - persons and/or user are members of other groups via their person or user groups, not directly
        - this can form Directed Acyclic Graphs
        - memberships can have temporal constraints:
            - start date: when the membership becomes active
            - end date: after which the membership becomes inactive
            - can be limited to being active between specific hours on a specific day of the week
    - moderator
        - groups can moderate other groups, but not transitively or cyclically
    - affiliates
        - any group can be affiliated with another group
        - not transitive
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
- `Capabilities`
    - a capability can be obtained by a person or user who is a member of a set of specified requried groups
    - capabilities are linked to grants on resources
    - access control is therefore managed through group membership
- `Capability Instances`
    - parameterised Capabilities, for use in generation of capability URLs
- `Capability Grants`
    - grant are grouped into sets
    - grant sets are defined by:
        - api hostname
        - api namespace
        - http method
    - grants are uniquely ranked within sets
    - rankings are monotonically incresing natural numbers
    - grants enable requests on URI patterns, given a specific capability
    - grants have optional parameters
        - required groups
        - start date
        - end date
        - maximum number of usages
- `Institutions`
    - generates an automatically managed secondary institution group
    - can have other groups as members
    - can be have other groups as affiliates
- `Projects`
    - generates an automatically managed primary project group
    - can be have other groups as affiliates
- `Clients`
    - API clients, and their attributes
- `Client IPs`
    - IP access lists for managing API access, not necessarily tied to specific clients

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
