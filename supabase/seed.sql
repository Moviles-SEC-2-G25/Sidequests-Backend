-- Sidequests reproducible development seed.
-- Matches the currently validated Kotlin prototype catalogue.

insert into public.quests (
  id, title, description, category, emoji, duration_minutes, estimated_cost,
  difficulty, location_mode, social_level, location_name, latitude, longitude,
  tags, is_new, is_sponsored, sponsor_name, is_group, is_active
) values
('botanical-garden','Explore the Botanical Garden','A slow wander through the conservatory — spot unfamiliar plants, find the Japanese garden, and leave with one photo worth keeping.','Outdoors','🌿',30,0,'easy','gps','solo','Jardín Botánico José Celestino Mutis',4.6686,-74.0986,array['nature','chill','free','solo'],true,false,null,false,true),
('ramen-spot','Try the New Ramen Spot','Order something outside your comfort zone, eat slowly, and leave a one-sentence review for the next person.','Food','🍜',30,14,'easy','gps','solo','Zona G, Chapinero',4.6473,-74.0613,array['food','solo','urban'],true,false,null,false,true),
('campus-mural-hunt','Campus Mural Hunt','Hunt down two pieces of campus art most students walk past every day without noticing.','Art','🎨',15,0,'easy','gps','solo','Universidad Nacional de Colombia',4.6389,-74.0838,array['art','campus','free','quick'],false,false,null,false,true),
('library-deep-dive','Library Deep Dive','Explore a library floor you''ve never visited, pull a random book, and leave with one new piece of knowledge.','Learning','📚',30,0,'easy','gps','solo','Biblioteca Luis Ángel Arango',4.5972,-74.0721,array['learning','calm','campus','free'],false,false,null,false,true),
('coffee-crawl','Solo Coffee Crawl','Enter a café you''ve never been to, order something unfamiliar, and stay one full drink longer than you planned.','Food','☕',30,5,'easy','gps','solo','Chapinero',4.6520,-74.0610,array['coffee','solo','chill','urban'],false,false,null,false,true),
('camera-roll','Organise Your Camera Roll','Delete the duplicates, curate your favourites folder, and find one photo worth printing.','Mindfulness','📷',20,0,'easy','anywhere','solo','Anywhere',null,null,array['digital','solo','anywhere','free','quick'],false,false,null,false,true),
('group-photo-walk','Group Photo Walk Challenge','A photography challenge for 3–5 friends. Everyone shoots the same prompt list and compares results at the end.','Art','📸',45,0,'easy','gps','group','La Candelaria',4.5981,-74.0761,array['art','group','photo','social','free'],false,false,null,true,true),
('sponsored-climbing','First Climb at Boulder Box','Boulder Box is offering SIDEQUEST users a free first session. No gear needed — they provide everything.','Movement','🧗',45,0,'medium','gps','solo','Boulder Box',4.6486,-74.0625,array['movement','sport','sponsored','free'],true,true,'Boulder Box',false,true)
on conflict (id) do update set
  title=excluded.title, description=excluded.description, category=excluded.category,
  emoji=excluded.emoji, duration_minutes=excluded.duration_minutes,
  estimated_cost=excluded.estimated_cost, difficulty=excluded.difficulty,
  location_mode=excluded.location_mode, social_level=excluded.social_level,
  location_name=excluded.location_name, latitude=excluded.latitude,
  longitude=excluded.longitude, tags=excluded.tags, is_new=excluded.is_new,
  is_sponsored=excluded.is_sponsored, sponsor_name=excluded.sponsor_name,
  is_group=excluded.is_group, is_active=excluded.is_active;

insert into public.quest_steps (quest_id, step_order, title, description, verification_type) values
('botanical-garden',0,'Find the conservatory entrance','Head to the main conservatory and grab a free map from the welcome stand.','none'),
('botanical-garden',1,'Spot 3 plants you''ve never seen','Wander through the tropical wing and find three plants that are totally new to you.','none'),
('botanical-garden',2,'Sit in the Japanese garden','Find a bench near the koi pond and sit for 5 minutes — no phone.','none'),
('botanical-garden',3,'Capture your favourite detail','Photograph one thing that caught your eye before you leave.','photo'),
('ramen-spot',0,'Order something new','Skip your usual safe choice and try a broth or topping you haven''t had before.','none'),
('ramen-spot',1,'Notice the atmosphere','Look around: music, decor, people. What is the vibe?','none'),
('ramen-spot',2,'Eat slowly','Put your phone face-down for the first 5 minutes and notice two flavour layers.','none'),
('ramen-spot',3,'Leave a quick review','Post a one-sentence honest review or save a photo.','photo'),
('campus-mural-hunt',0,'Find the mural near the library','Start at the south-facing wall of the main library building.','none'),
('campus-mural-hunt',1,'Spot the hidden detail','Spend two minutes looking for something most people miss.','none'),
('campus-mural-hunt',2,'Find a second piece of campus art','Walk in any direction and look for a sculpture, mosaic, or mural.','none'),
('campus-mural-hunt',3,'Share your favourite','Take a photo of whichever piece you liked most.','photo'),
('library-deep-dive',0,'Pick a floor you''ve never visited','Go to one you have never actually explored.','none'),
('library-deep-dive',1,'Pull a random book','Close your eyes, walk to a shelf, and pull out whatever your hand lands on.','none'),
('library-deep-dive',2,'Find a cosy reading nook','Sit for 10 minutes with your random book.','none'),
('library-deep-dive',3,'Note one thing you learned','Write down one sentence about something you did not know before.','none'),
('coffee-crawl',0,'Order a drink you''ve never tried','Pick something unfamiliar from a café you normally pass by.','none'),
('coffee-crawl',1,'Pick a seat with an interesting view','Choose a window spot or a bar stool near the baristas.','none'),
('coffee-crawl',2,'Notice 3 design details','Find three intentional choices in the space.','none'),
('coffee-crawl',3,'Stay ten more minutes','Finish your drink and stay a little longer without rushing.','none'),
('camera-roll',0,'Delete duplicates and blurry shots','Go month by month for the last three months.','none'),
('camera-roll',1,'Create a Favourites album','Pick your 10 best photos from the past six months.','none'),
('camera-roll',2,'Find one photo worth printing','Choose one photo that genuinely moves you.','none'),
('camera-roll',3,'Make it real','Order the print or set the photo as your wallpaper.','none'),
('group-photo-walk',0,'Everyone picks a starting point','Meet at your agreed location and head in different directions.','none'),
('group-photo-walk',1,'Shoot ''Something Red''','Find and photograph something red in the next five minutes.','photo'),
('group-photo-walk',2,'Shoot ''A Person From Behind''','Create a respectful street-photo interpretation of the prompt.','photo'),
('group-photo-walk',3,'Group vote','Share your photos and vote with one emoji reaction.','none'),
('sponsored-climbing',0,'Check in at reception','Say you''re here for the SIDEQUEST offer.','none'),
('sponsored-climbing',1,'Complete the beginner orientation','Learn the route rating system and basic safety.','none'),
('sponsored-climbing',2,'Finish 3 routes at your level','Start easy and complete at least three routes.','none'),
('sponsored-climbing',3,'Log your hardest route','Record your best route in your Sidequests stats.','photo')
on conflict (quest_id, step_order) do update set
  title=excluded.title,
  description=excluded.description,
  verification_type=excluded.verification_type;
