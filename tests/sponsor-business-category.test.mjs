import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { PGlite } from '@electric-sql/pglite';

test('sponsor industry is separate from quest activity and old rows remain compatible', async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create schema public;
      create table public.quests (
        id text primary key,
        category text not null,
        sponsor_name text,
        is_sponsored boolean not null default false
      );
      insert into public.quests (id, category, sponsor_name, is_sponsored)
      values
        ('regular-quest', 'Movement', null, false),
        ('sponsored-climbing', 'Movement', 'Boulder Box', true);
    `);
    const sql = await readFile(
      new URL('../supabase/migrations/010_sponsor_business_category.sql', import.meta.url),
      'utf8',
    );
    await db.exec(sql);
    const rows = (await db.query(`
      select id, category, sponsor_business_category from public.quests order by id
    `)).rows;
    assert.deepEqual(rows, [
      { id: 'regular-quest', category: 'Movement', sponsor_business_category: null },
      { id: 'sponsored-climbing', category: 'Movement', sponsor_business_category: 'fitness_and_recreation' },
    ]);

    await assert.rejects(db.exec(`
      update public.quests
      set sponsor_business_category = 'cafe'
      where id = 'regular-quest'
    `));
    await db.exec(sql.replace(
      /alter table public\.quests\s+add constraint[\s\S]*?;\n\ncomment on column/,
      'comment on column',
    ).replace(
      /comment on column public\.quests\.sponsor_business_category[\s\S]*?;\n\n/,
      '',
    ));
  } finally {
    await db.close();
  }
});
