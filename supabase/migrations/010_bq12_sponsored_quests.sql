-- BQ12 (Type 4): sponsored quest performance.
--
-- A sponsored quest already has `is_sponsored` and `sponsor_name` (migration 001).
-- This adds the sponsor's business category, which Kotlin has read as an optional
-- field since Sprint 3 (`QuestDto.sponsorBusinessCategory`), so both clients and
-- the analytics engine share one column name and one vocabulary.
--
-- It is a property of the sponsor, not of the activity: `category` says what the
-- quest is (Food, Movement...), `sponsor_business_category` says who pays for it
-- (food_and_beverage, fitness_and_recreation...). Non-sponsored quests keep it null;
-- BQ12 reports them under the explicit business category `none`.
--
-- No new policy is needed: `quests_select_active` already lets authenticated users
-- read every column of active quests, and anon still has no access.

alter table public.quests
  add column sponsor_business_category text;

alter table public.quests
  add constraint quests_sponsor_business_category_check check (
    sponsor_business_category is null
    or (
      is_sponsored
      and sponsor_business_category in (
        'fitness_and_recreation',
        'food_and_beverage',
        'arts_and_culture',
        'education_and_books',
        'health_and_wellness',
        'retail',
        'events_and_entertainment',
        'community_and_nonprofit'
      )
    )
  );

comment on column public.quests.sponsor_business_category is
  'BQ12: business category of the sponsor (null when not sponsored or not yet classified). Shared vocabulary in Sidequests-Analytics docs/EVENT_SCHEMA.md.';

-- Explore's "sponsored" filter and BQ12 segment by sponsor; the catalogue is
-- small today, the index keeps that read cheap as sponsors are added.
create index quests_sponsored_business_category_idx
on public.quests (sponsor_business_category)
where is_sponsored;

-- BQ7, BQ9 and BQ12 all read the last 30 days of attempts by accepted_at.
create index if not exists user_quests_accepted_at_idx
on public.user_quests (accepted_at desc);

-- Sponsored quests across several business categories, so BQ12 can be validated
-- from both apps. Sponsors are fictional. Every one is shown as sponsored in the
-- apps (`is_sponsored = true`) and goes through the same recommend_quests ranking
-- as any other quest: no score boost for being sponsored.
update public.quests
set sponsor_business_category = 'fitness_and_recreation'
where id = 'sponsored-climbing';

insert into public.quests (
  id, title, description, category, emoji, duration_minutes, estimated_cost,
  difficulty, location_mode, social_level, location_name, latitude, longitude,
  tags, is_new, is_sponsored, sponsor_name, sponsor_business_category, is_group, is_active
) values
('sponsored-latte-lab','Latte Art Session at Tinto Lab','Tinto Lab invites SIDEQUEST users to pour their first latte art. One drink included, no barista experience needed.','Food','☕',30,6,'easy','gps','solo','Tinto Lab, Chapinero',4.6490,-74.0628,array['food','coffee','urban','sponsored'],true,true,'Tinto Lab','food_and_beverage',false,true),
('sponsored-bookshop-hunt','Bookshop Treasure Hunt at Página 7','Página 7 hid five clues between its shelves. Find them and leave with a book recommendation picked just for you.','Learning','📖',30,0,'easy','gps','solo','Página 7, La Candelaria',4.5975,-74.0730,array['learning','books','calm','free','sponsored'],true,true,'Página 7','retail',false,true),
('sponsored-gallery-night','Open Studio Night at Galería Lumen','Galería Lumen opens its studios to SIDEQUEST users: meet a resident artist and vote for the piece of the month.','Art','🖼️',45,0,'easy','gps','social','Galería Lumen, San Felipe',4.6640,-74.0700,array['art','social','free','sponsored'],true,true,'Galería Lumen','arts_and_culture',false,true),
('sponsored-breathwork','Guided Breathwork with Calma Studio','A free 20-minute guided breathing session from Calma Studio that you can do from wherever you are.','Mindfulness','🧘',20,0,'easy','anywhere','solo','Anywhere',null,null,array['mindfulness','calm','anywhere','free','sponsored'],true,true,'Calma Studio','health_and_wellness',false,true),
('sponsored-park-cleanup','Park Clean-up with Raíces Verdes','Join Raíces Verdes for an hour of picking up litter in the park. Gloves and bags provided; leave the place better than you found it.','Outdoors','🌱',60,0,'easy','gps','social','Parque El Virrey',4.6735,-74.0530,array['outdoors','nature','social','free','volunteering','sponsored'],true,true,'Raíces Verdes','community_and_nonprofit',false,true)
on conflict (id) do update set
  title=excluded.title, description=excluded.description, category=excluded.category,
  emoji=excluded.emoji, duration_minutes=excluded.duration_minutes,
  estimated_cost=excluded.estimated_cost, difficulty=excluded.difficulty,
  location_mode=excluded.location_mode, social_level=excluded.social_level,
  location_name=excluded.location_name, latitude=excluded.latitude,
  longitude=excluded.longitude, tags=excluded.tags, is_new=excluded.is_new,
  is_sponsored=excluded.is_sponsored, sponsor_name=excluded.sponsor_name,
  sponsor_business_category=excluded.sponsor_business_category,
  is_group=excluded.is_group, is_active=excluded.is_active;

insert into public.quest_steps (quest_id, step_order, title, description, verification_type) values
('sponsored-latte-lab',0,'Check in at the bar','Say you''re here for the SIDEQUEST latte art session.','none'),
('sponsored-latte-lab',1,'Learn the basic pour','Watch the barista pour a heart and copy the wrist movement.','none'),
('sponsored-latte-lab',2,'Pour your own','Try at least twice; the second one is always better.','none'),
('sponsored-latte-lab',3,'Capture your best cup','Take a photo of your best attempt before drinking it.','photo'),
('sponsored-bookshop-hunt',0,'Get the first clue','Ask at the counter for the SIDEQUEST clue card.','none'),
('sponsored-bookshop-hunt',1,'Find the five clues','Follow the clues across the shelves; each one names the next section.','none'),
('sponsored-bookshop-hunt',2,'Collect your recommendation','Hand in the card and get a book picked for you.','none'),
('sponsored-gallery-night',0,'Arrive for the studio tour','Join the group at the gallery entrance at the start time.','none'),
('sponsored-gallery-night',1,'Meet the resident artist','Ask one question about how a piece was made.','none'),
('sponsored-gallery-night',2,'Vote for the piece of the month','Pick your favourite and tell the person next to you why.','none'),
('sponsored-gallery-night',3,'Save your favourite','Photograph the piece you voted for.','photo'),
('sponsored-breathwork',0,'Find a quiet spot','Sit somewhere you won''t be interrupted for 20 minutes.','none'),
('sponsored-breathwork',1,'Follow the guided session','Play Calma Studio''s session and follow the breathing rhythm.','none'),
('sponsored-breathwork',2,'Notice the difference','Write one word for how you feel now compared with before.','none'),
('sponsored-park-cleanup',0,'Meet the Raíces Verdes team','Pick up gloves and a bag at the meeting point.','none'),
('sponsored-park-cleanup',1,'Clean your assigned area','Spend at least 40 minutes on your section of the park.','none'),
('sponsored-park-cleanup',2,'Sort what you collected','Separate recyclables at the collection point.','none'),
('sponsored-park-cleanup',3,'Before and after','Photograph your area once it''s clean.','photo')
on conflict (quest_id, step_order) do update set
  title=excluded.title,
  description=excluded.description,
  verification_type=excluded.verification_type;
