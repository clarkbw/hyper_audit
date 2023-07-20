# `hyper_audit`

<p>
<a href=""><img src="https://img.shields.io/badge/postgresql-11+-blue.svg" alt="PostgreSQL version" height="18"></a>
<a href="https://github.com/clarkbw/hyper_audit/actions"><img src="https://github.com/clarkbw/hyper_audit/actions/workflows/test.yaml/badge.svg" alt="Tests" height="18"></a>

</p>

---

**Source Code**: <a href="https://github.com/clarkbw/hyper_audit" target="_blank">https://github.com/clarkbw/hyper_audit</a>

---

The `supa_audit` PostgreSQL extension is a generic solution for tracking changes to tables' data over time.

The audit table, `audit.record_version`, leverages each records primary key values to produce a stable `record_id::uuid`, enabling efficient (linear time) history queries.


## Usage


### OAuth

With OAuth the optimal pattern is to only have 1 row per access token / user such that you aren't scanning through thousands of old rows but presenting a view that only has the valid information. While the scanning of old rows can be completed quickly with an index the table source balloons with data that is no longer useful or valid and this is done simply for having some audit record or simplifying the application developers usage.

Given the following pattern which is recommended by the [strava developer authentication guide](https://developers.strava.com/docs/authentication/) of having an `access_token` and `refresh_token` table. We enable tracking on those tables such that we can `upsert` data as needed yet we're keeping old access and refresh tokens in case of error.

```sql
create table access_token ( id serial primary key, customer_id int unique not null, token varchar not null, expires_at timestamp not null default now() );

create table refresh_token ( id serial primary key, access_token_id int unique not null, token varchar not null, expires_at timestamp not null default now() );


select audit.enable_tracking('public.access_token'::regclass);
select audit.enable_tracking('public.refresh_token'::regclass);

-- upsert avoids conflicting customer ids and provides UPDATE audit

begin;

with ac as (
insert into access_token ( customer_id, token, expires_at ) values ( floor(random() * 10 + 1)::int, gen_random_uuid(), now() + interval '1 day' )
on conflict (customer_id)
do update set token = gen_random_uuid(), expires_at = now() + interval '1 day' returning id, expires_at
)

insert into refresh_token ( access_token_id, token, expires_at ) values ( (select id from ac), gen_random_uuid(), (select expires_at from ac) )
on conflict (access_token_id)
do update set token = gen_random_uuid(), expires_at = (select expires_at from ac);

commit;

```

A customer could use the following Prisma JS to do an `upsert` whenever they receive a new or updated access token. This simplifies the application developer code tremedously and keeps our data storage to a minimal; only one row of valid data. 

```javascript
    await this.client.stravaAccessToken.upsert({
      where: {
        strava: {
          athlete_id: installation.athlete_id,
        },
      },
      update: {
        access_token: installation.access_token,
        expires_at: installation.expires_at,
      },
      create: {
        athlete_id: installation.athlete_id,
        access_token: installation.access_token,
        expires_at: installation.expires_at,
        scopes: installation.scopes,
      },
    });

    await this.client.stravaRefreshToken.upsert({
      where: {
        strava: {
          athlete_id: installation.athlete_id,
        },
      },
      update: {
        refresh_token: installation.refresh_token,
        expires_at: installation.expires_at,
      },
      create: {
        athlete_id: installation.athlete_id,
        refresh_token: installation.refresh_token,
        expires_at: installation.expires_at,
      },
    });
    
```
### Services

```sql
create table service ( 
    id serial primary key, 
    created timestamp with time zone not null default now(),
    name text,
    service_id text,
    project_id text
);


-- Enable auditing
select audit.enable_tracking('public.service'::regclass);

-- Insert a record
insert into public.service(name, service_id, project_id)
values ('Foo Barsworth', 'lskdf098', 'lksjasf09'), ('company prod', 'lskdss98', 'lkhjdf09'), ('company dev', 'lskwert098', 'lksdfgdf09'), ('company staging', 'lskdadsf98', 'lkgjdf09'), ('owl [dev]', 'ldasddf098', 'lksjdf09'), ('owl [prod]', 'lggdf098', 'lksjghf09');

-- See records
select * from service;

-- Update a record
update public.service
set name = 'default'; -- whoops

-- Review the history
select * from audit.record_version;

select old_record, record from audit.record_version where op = 'UPDATE';
```


### Account

```sql
create extension supa_audit cascade;

create table public.account(
    id int primary key,
    name text not null
);

-- Enable auditing
select audit.enable_tracking('public.account'::regclass);

-- Insert a record
insert into public.account(id, name)
values (1, 'Foo Barsworth');

-- Update a record
update public.account
set name = 'Foo Barsworht III'
where id = 1;

-- Delete a record
delete from public.account
where id = 1;

-- Truncate the table
truncate table public.account;

-- Review the history
select
    *
from
    audit.record_version;

/*
 id |              record_id               |            old_record_id             |    op    |               ts                | table_oid | table_schema | table_name |                 record                 |             old_record
----+--------------------------------------+--------------------------------------+----------+---------------------------------+-----------+--------------+------------+----------------------------------------+------------------------------------
  1 | 57ca384e-f24c-5af5-b361-a057aeac506c |                                      | INSERT   | Thu Feb 10 17:02:25.621095 2022 |     16439 | public       | account    | {"id": 1, "name": "Foo Barsworth"}     |
  2 | 57ca384e-f24c-5af5-b361-a057aeac506c | 57ca384e-f24c-5af5-b361-a057aeac506c | UPDATE   | Thu Feb 10 17:02:25.622151 2022 |     16439 | public       | account    | {"id": 1, "name": "Foo Barsworht III"} | {"id": 1, "name": "Foo Barsworth"}
  3 |                                      | 57ca384e-f24c-5af5-b361-a057aeac506c | DELETE   | Thu Feb 10 17:02:25.622495 2022 |     16439 | public       | account    |                                        | {"id": 1, "name": "Foo Barsworth III"}
  4 |                                      |                                      | TRUNCATE | Thu Feb 10 17:02:25.622779 2022 |     16439 | public       | account    |                                        |
(4 rows)
*/

-- Disable auditing
select audit.disable_tracking('public.account'::regclass);
```

## Test

### Run the Tests

```sh
nix-shell --run "pg_13_supa_audit make installcheck"
```

### Adding Tests

Tests are located in `test/sql/` and the expected output is in `test/expected/`

The output of the most recent test run is stored in `results/`.

When the output for a test in `results/` is correct, copy it to `test/expected/` and the test will pass.

## Interactive Prompt

```sh
nix-shell --run "pg_13_supa_audit psql"
```

## Performance


### Write Throughput
Auditing tables reduces throughput of inserts, updates, and deletes.

It is not recommended to enable tracking on tables with a peak write throughput over 3k ops/second.


### Querying

When querying a table's history, filter on the indexed `table_oid` rather than the `table_name` and `schema_name` columns.

```sql
select
    *
from
    audit.record_version
where
    table_oid = 'public.account'::regclass::oid;
```
