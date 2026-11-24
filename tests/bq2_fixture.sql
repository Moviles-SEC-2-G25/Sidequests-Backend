-- Isolated CI fixture; never run against the shared project.
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
 select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;
create table public.quests(id text primary key,title text,is_group boolean,is_active boolean);
create table public.quest_steps(id bigint primary key,quest_id text references public.quests(id));
insert into auth.users values ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002');
insert into public.quests values ('group','Test group',true,true),('solo','Test solo',false,true);
insert into public.quest_steps values(1,'group'),(2,'group'),(3,'solo');
