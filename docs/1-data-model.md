
# Data Model

## Object hierarchy

```txt
Persons -----> Users ----> Groups (class:primary,   type:user)
  -----------------------> Groups (class:primary,   type:person)
                        -> Groups (class:secondary, type:generic)
                            -> Groups (class:secondary: relations: members, moderators)
```

Objects and relations:
- `Persons`: root objects
- `Users`: owned by `Persons`
- `Groups`: three types, `user`, `person` (belonging to the `primary` class), and `generic` (belonging to the `secondary` class)
- all three types of groups can have relations to other secondary groups
- these relations can be either member or moderator relations

## Object states

- active/inactive
    - person group state -> f(person state)
    - user group state -> f(user state) -> f(person state)
    - generic group state -> f(.)

- expiry dates
    - person group exp == person exp
    - user group exp == user exp
    - user exp <= person exp
