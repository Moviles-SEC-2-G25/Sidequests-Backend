-- Private photo evidence for quest steps. Apply before enabling remote proof upload
-- in either mobile client.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('quest-proofs', 'quest-proofs', false, 26214400, array['image/jpeg'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table public.quest_photo_proofs (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.user_quests(id) on delete cascade,
  step_order integer not null check (step_order >= 0),
  storage_path text not null unique,
  uploaded_at timestamptz not null default now()
);

create index quest_photo_proofs_attempt_step_idx
on public.quest_photo_proofs (attempt_id, step_order, uploaded_at desc);

alter table public.quest_photo_proofs enable row level security;
revoke all on public.quest_photo_proofs from anon;
grant select, insert on public.quest_photo_proofs to authenticated;

create policy "quest_photo_proofs_select_own"
on public.quest_photo_proofs for select to authenticated
using (
  exists (
    select 1 from public.user_quests uq
    where uq.id = attempt_id and uq.user_id = (select auth.uid())
  )
);

create policy "quest_photo_proofs_insert_own_photo_step"
on public.quest_photo_proofs for insert to authenticated
with check (
  exists (
    select 1
    from public.user_quests uq
    join public.quest_steps qs
      on qs.quest_id = uq.quest_id and qs.step_order = quest_photo_proofs.step_order
    where uq.id = attempt_id
      and uq.user_id = (select auth.uid())
      and qs.verification_type in ('photo', 'photo_and_location')
      and split_part(storage_path, '/', 1) = uq.user_id::text
      and split_part(storage_path, '/', 2) = uq.id::text
      and split_part(storage_path, '/', 3) = uq.quest_id
      and split_part(storage_path, '/', 4) like 'step-' || (step_order + 1)::text || '-%.jpg'
      and split_part(storage_path, '/', 5) = ''
      and exists (
        select 1 from storage.objects so
        where so.bucket_id = 'quest-proofs' and so.name = storage_path
      )
  )
);

-- Storage paths: <user-id>/<attempt-id>/<quest-id>/step-<1-based-number>-<uuid>.jpg
-- The attempt check prevents writing into another user's quest folder.
create policy "quest_proofs_insert_own_attempt"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'quest-proofs'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and exists (
    select 1
    from public.user_quests uq
    join public.quest_steps qs on qs.quest_id = uq.quest_id
    where uq.user_id = (select auth.uid())
      and uq.id::text = (storage.foldername(name))[2]
      and uq.quest_id = (storage.foldername(name))[3]
      and qs.verification_type in ('photo', 'photo_and_location')
      and split_part(name, '/', 4) like 'step-' || (qs.step_order + 1)::text || '-%.jpg'
      and split_part(name, '/', 5) = ''
  )
);

create policy "quest_proofs_select_own_attempt"
on storage.objects for select to authenticated
using (
  bucket_id = 'quest-proofs'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and exists (
    select 1 from public.user_quests uq
    where uq.user_id = (select auth.uid())
      and uq.id::text = (storage.foldername(name))[2]
      and uq.quest_id = (storage.foldername(name))[3]
  )
);

-- Used only to remove an upload if inserting its database record fails.
create policy "quest_proofs_delete_own_attempt"
on storage.objects for delete to authenticated
using (
  bucket_id = 'quest-proofs'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
  and exists (
    select 1 from public.user_quests uq
    where uq.user_id = (select auth.uid())
      and uq.id::text = (storage.foldername(name))[2]
      and uq.quest_id = (storage.foldername(name))[3]
  )
);
