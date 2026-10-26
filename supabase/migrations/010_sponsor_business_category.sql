-- Sprint 3 BQ12: a sponsor's industry is not the same as a quest's activity category.
-- Keep this field optional so existing clients, seed data and unsponsored quests
-- continue to work. The column contains no personal user information.
alter table public.quests
  add column if not exists sponsor_business_category text;

-- Only sponsored quests can have a sponsor's business category.
alter table public.quests
  add constraint quests_sponsor_business_category_only_when_sponsored
  check (sponsor_business_category is null or is_sponsored = true);

comment on column public.quests.sponsor_business_category is
  'Sponsor industry, e.g. fitness_and_recreation; independent of quest activity category.';

-- The shipped Sidequests sponsor is a climbing gym. Existing rows get a
-- known classification; unclassified future sponsors remain NULL until reviewed.
update public.quests
set sponsor_business_category = 'fitness_and_recreation'
where id = 'sponsored-climbing'
  and sponsor_name = 'Boulder Box'
  and is_sponsored = true
  and sponsor_business_category is null;
