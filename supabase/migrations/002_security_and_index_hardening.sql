revoke execute
on function public.handle_new_user()
from public, anon, authenticated;

create index user_quests_quest_idx
on public.user_quests (quest_id);
