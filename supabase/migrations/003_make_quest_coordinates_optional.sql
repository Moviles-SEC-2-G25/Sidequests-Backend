alter table public.quests
drop constraint quests_location_coordinates_check;

alter table public.quests
add constraint quests_location_coordinates_check
check (
  (
    latitude is null
    and longitude is null
  )
  or
  (
    latitude is not null
    and longitude is not null
  )
);
