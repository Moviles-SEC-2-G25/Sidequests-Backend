begin;
create schema sidequests_group_private;
revoke all on schema sidequests_group_private from public, anon, authenticated;
grant usage on schema sidequests_group_private to authenticated;

create table sidequests_group_private.challenges (
 id uuid primary key default gen_random_uuid(),
 quest_id text not null references public.quests(id) on delete restrict,
 owner_id uuid not null references auth.users(id) on delete cascade,
 total_steps integer not null check(total_steps > 0),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default (now() + interval '7 days')
);
create table sidequests_group_private.members (
 challenge_id uuid not null references sidequests_group_private.challenges(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 joined_at timestamptz not null default now(),
 progress integer not null default 0 check(progress >= 0),
 primary key(challenge_id,user_id)
);
create index group_members_user_idx on sidequests_group_private.members(user_id);
create table sidequests_group_private.operations (
 user_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null,
 operation text not null check(operation in ('create','join','progress')),
 challenge_id uuid references sidequests_group_private.challenges(id) on delete set null,
 succeeded boolean not null,
 response jsonb not null,
 occurred_at timestamptz not null default now(),
 primary key(user_id,request_id)
);
create index group_operations_time_idx on sidequests_group_private.operations(occurred_at,operation);
alter table sidequests_group_private.challenges enable row level security;
alter table sidequests_group_private.members enable row level security;
alter table sidequests_group_private.operations enable row level security;
revoke all on all tables in schema sidequests_group_private from public,anon,authenticated;

-- Only authenticated callers can invoke this internal function. No participant identities
-- are returned, and all writes and telemetry use auth.uid(), never a client-supplied identity.
create function sidequests_group_private.act(
 p_action text, p_request_id uuid, p_challenge_id uuid default null,
 p_quest_id text default null, p_progress integer default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 actor uuid := auth.uid();
 cid uuid := p_challenge_id;
 step_count integer;
 member_progress integer;
 outcome jsonb;
 failure text;
begin
 if actor is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_request_id is null or p_action is null or p_action not in ('create','join','progress') then
   raise exception 'Invalid request' using errcode='22023';
 end if;
 -- Serialize retries of the same operation; never create a second membership or log row.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text || ':' || p_request_id::text,0));
 select response into outcome from sidequests_group_private.operations
 where user_id=actor and request_id=p_request_id;
 if found then return outcome; end if;
 begin
   if p_action='create' then
     cid := null;
     select count(s.id)::integer into step_count
     from public.quests q join public.quest_steps s on s.quest_id=q.id
     where q.id=p_quest_id and q.is_group and q.is_active;
     if step_count=0 then failure := 'Choose an active group quest with steps.';
     else
       insert into sidequests_group_private.challenges(quest_id,owner_id,total_steps)
       values(p_quest_id,actor,step_count) returning id into cid;
       insert into sidequests_group_private.members(challenge_id,user_id) values(cid,actor);
     end if;
   else
     select total_steps into step_count from sidequests_group_private.challenges
     where id=cid and expires_at>now() for update;
     if not found then failure := 'Challenge not found or expired.'; cid := null;
     elsif p_action='join' then
       insert into sidequests_group_private.members(challenge_id,user_id)
       values(cid,actor) on conflict do nothing;
     else
       select progress into member_progress from sidequests_group_private.members
       where challenge_id=cid and user_id=actor for update;
       if not found then failure := 'Join this challenge first.';
       elsif p_progress is null or p_progress<member_progress or p_progress>step_count then
         failure := 'Progress must be between your current step and the challenge total.';
       else
         update sidequests_group_private.members set progress=p_progress
         where challenge_id=cid and user_id=actor;
       end if;
     end if;
   end if;
 exception when others then
   -- The nested block rolls back failed writes; the outer transaction records the failure.
   cid := null;
   failure := 'The server could not complete the operation.';
 end;
 outcome := jsonb_build_object('ok',failure is null,'message',coalesce(failure,'Saved'),'challenge_id',cid);
 insert into sidequests_group_private.operations(user_id,request_id,operation,challenge_id,succeeded,response)
 values(actor,p_request_id,p_action,cid,failure is null,outcome);
 return outcome;
end;
$$;

create function sidequests_group_private.list_challenges(p_mine boolean)
returns table(challenge_id uuid,quest_id text,title text,participants integer,
 my_progress integer,total_steps integer,completed_participants integer)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 return query
 select c.id,c.quest_id,q.title,count(m.user_id)::integer,
 max(m.progress) filter(where m.user_id=auth.uid()),c.total_steps,
 count(m.user_id) filter(where m.progress=c.total_steps)::integer
 from sidequests_group_private.challenges c
 join public.quests q on q.id=c.quest_id
 join sidequests_group_private.members m on m.challenge_id=c.id
 where c.expires_at>now()
 group by c.id,q.title
 having (bool_or(m.user_id=auth.uid()) = p_mine)
 order by c.created_at desc,c.id
 limit 50;
end;
$$;

revoke all on function sidequests_group_private.act(text,uuid,uuid,text,integer) from public,anon,authenticated;
revoke all on function sidequests_group_private.list_challenges(boolean) from public,anon,authenticated;
grant execute on function sidequests_group_private.act(text,uuid,uuid,text,integer) to authenticated;
grant execute on function sidequests_group_private.list_challenges(boolean) to authenticated;

create function public.group_challenge_act(
 p_action text,p_request_id uuid,p_challenge_id uuid default null,
 p_quest_id text default null,p_progress integer default null
) returns jsonb language sql security invoker set search_path='' as $$
 select sidequests_group_private.act(p_action,p_request_id,p_challenge_id,p_quest_id,p_progress);
$$;
create function public.group_challenge_list(p_mine boolean)
returns table(challenge_id uuid,quest_id text,title text,participants integer,
 my_progress integer,total_steps integer,completed_participants integer)
language sql stable security invoker set search_path='' as $$
 select * from sidequests_group_private.list_challenges(p_mine);
$$;
revoke all on function public.group_challenge_act(text,uuid,uuid,text,integer) from public,anon,authenticated;
revoke all on function public.group_challenge_list(boolean) from public,anon,authenticated;
grant execute on function public.group_challenge_act(text,uuid,uuid,text,integer) to authenticated;
grant execute on function public.group_challenge_list(boolean) to authenticated;
commit;
