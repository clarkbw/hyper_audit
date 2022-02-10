begin;

    create table public.dummy(
        id int primary key
    );


    insert into public.dummy(id)
    values (1);


    select audit.enable_tracking('public.dummy');


    insert into public.dummy(id)
    values (2);


    select audit.disable_tracking('public.dummy');


    insert into public.dummy(id)
    values (3);


    -- Only record with id = 2 should be present
    with remap as (
        select distinct on (u.id)
            u.id,
            row_number() over () stable_id
        from
            audit.record_version arv,
            unnest(array[arv.record_id, arv.old_record_id]) u(id)
        order by
            u.id asc
    )
    select
        arv.id,
        r.stable_id as remapped_record_id,
        ro.stable_id as remapped_old_record_id,
        op,
        table_schema,
        table_name,
        record
    from
        audit.record_version arv
        left join remap r
            on arv.record_id = r.id
        left join remap ro
            on arv.old_record_id = ro.id;
rollback;
