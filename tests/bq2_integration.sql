begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$
declare r jsonb; cid uuid; n integer;
begin
 r:=public.group_challenge_act('create','10000000-0000-0000-0000-000000000001',null,'group');
 if not (r->>'ok')::boolean then raise exception 'create failed: %',r; end if;
 cid:=(r->>'challenge_id')::uuid;
 if public.group_challenge_act('create','10000000-0000-0000-0000-000000000001',null,'group')<>r then raise exception 'retry not idempotent'; end if;
 select participants into n from public.group_challenge_list(true) where challenge_id=cid;
 if n<>1 then raise exception 'creator membership missing'; end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
 if not exists(select 1 from public.group_challenge_list(false) where challenge_id=cid and participants=1 and my_progress is null) then raise exception 'available challenge missing'; end if;
 r:=public.group_challenge_act('progress','20000000-0000-0000-0000-000000000001',cid,null,1);
 if (r->>'ok')::boolean then raise exception 'nonmember updated progress'; end if;
 r:=public.group_challenge_act('join','20000000-0000-0000-0000-000000000002',cid);
 if not (r->>'ok')::boolean then raise exception 'join failed'; end if;
 r:=public.group_challenge_act('join','20000000-0000-0000-0000-000000000003',cid);
 if not (r->>'ok')::boolean then raise exception 'repeat join failed'; end if;
 r:=public.group_challenge_act('progress','20000000-0000-0000-0000-000000000004',cid,null,3);
 if (r->>'ok')::boolean then raise exception 'invalid progress accepted'; end if;
 r:=public.group_challenge_act('progress','20000000-0000-0000-0000-000000000005',cid,null,2);
 if not (r->>'ok')::boolean then raise exception 'valid progress rejected'; end if;
 if not exists(select 1 from public.group_challenge_list(true) where challenge_id=cid and participants=2 and my_progress=2 and completed_participants=1) then raise exception 'progress/participants mismatch'; end if;
 if has_table_privilege('authenticated','sidequests_group_private.members','select') then raise exception 'private member data exposed'; end if;
 if has_function_privilege('anon','public.group_challenge_list(boolean)','execute') then raise exception 'anon access'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from sidequests_group_private.members)<>2 then raise exception 'membership duplicated'; end if;
 if (select count(*) from sidequests_group_private.operations)<>6 then raise exception 'operation telemetry incorrect'; end if;
 if (select count(*) from sidequests_group_private.operations where not succeeded)<>2 then raise exception 'failure telemetry incorrect'; end if;
end $$;
rollback;
