import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { test } from 'node:test';
import { PGlite } from '@electric-sql/pglite';

// Same minimal Supabase stand-ins as quest-photo-proofs.test.mjs: migration 009
// needs the storage schema, and RLS needs auth.uid() and the two API roles.
const platformFixture = `
  create role anon;
  create role authenticated;
  create schema auth;
  create schema storage;
  grant usage on schema auth, storage to anon, authenticated;
  create table auth.users (id uuid primary key, email text, raw_user_meta_data jsonb);
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  create table storage.buckets (
    id text primary key, name text, public boolean,
    file_size_limit bigint, allowed_mime_types text[]
  );
  create table storage.objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text references storage.buckets(id), name text not null,
    unique (bucket_id, name)
  );
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
  $$;
`;

const alice = '11111111-1111-4111-8111-111111111111';

test('migration 010 adds the sponsor business category and sponsored demo quests', async (t) => {
  const db = new PGlite();
  try {
    await db.exec(platformFixture);
    const migrations = new URL('../supabase/migrations/', import.meta.url);
    for (const migration of (await readdir(migrations)).filter(name => name.endsWith('.sql')).sort()) {
      await db.exec(await readFile(new URL(migration, migrations), 'utf8'));
    }
    await db.exec(await readFile(new URL('../supabase/seed.sql', import.meta.url), 'utf8'));
    await db.query('insert into auth.users (id) values ($1)', [alice]);

    const asUser = async (user, role = 'authenticated') => {
      await db.exec('reset role');
      await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user ?? '']);
      await db.exec(`set role ${role}`);
    };
    const asOwner = () => db.exec('reset role');
    const rejected = (operation, code) => assert.rejects(operation, error => error.code === code);

    await t.test('every sponsored demo quest has a category, a sponsor and steps', async () => {
      await asOwner();
      const { rows } = await db.query(`
        select q.id, q.sponsor_name, q.sponsor_business_category, count(s.id)::int as steps
        from public.quests q
        left join public.quest_steps s on s.quest_id = q.id
        where q.is_sponsored
        group by q.id
        order by q.id`);
      assert.equal(rows.length, 6);
      for (const row of rows) {
        assert.ok(row.sponsor_name, `${row.id} has no sponsor_name`);
        assert.ok(row.sponsor_business_category, `${row.id} has no business category`);
        assert.ok(row.steps >= 3, `${row.id} has ${row.steps} steps`);
      }
      assert.equal(new Set(rows.map(row => row.sponsor_business_category)).size, 6);
      assert.equal(
        rows.find(row => row.id === 'sponsored-climbing').sponsor_business_category,
        'fitness_and_recreation',
      );
    });

    await t.test('non-sponsored quests keep a null business category', async () => {
      await asOwner();
      const { rows } = await db.query(`
        select count(*)::int as n from public.quests
        where not is_sponsored and sponsor_business_category is not null`);
      assert.equal(rows[0].n, 0);
    });

    await t.test('the shared vocabulary is enforced', async () => {
      await asOwner();
      // 23514 = check_violation
      await rejected(() => db.query(
        "update public.quests set sponsor_business_category = 'retail' where id = 'ramen-spot'"), '23514');
      await rejected(() => db.query(
        "update public.quests set sponsor_business_category = 'Fitness' where id = 'sponsored-climbing'"), '23514');
      // A sponsored quest may stay unclassified: BQ12 reports it as 'unspecified'.
      await db.query("update public.quests set sponsor_business_category = null where id = 'sponsored-latte-lab'");
      await db.query("update public.quests set sponsor_business_category = 'food_and_beverage' where id = 'sponsored-latte-lab'");
    });

    await t.test('authenticated users read the new column through the existing policy', async () => {
      await asUser(alice);
      const { rows } = await db.query(`
        select id, sponsor_business_category from public.quests
        where id = 'sponsored-breathwork'`);
      assert.equal(rows[0].sponsor_business_category, 'health_and_wellness');
      // 42501 = insufficient_privilege: the catalogue stays read-only for clients.
      await rejected(() => db.query(
        "update public.quests set sponsor_business_category = 'retail' where id = 'sponsored-breathwork'"), '42501');
    });

    await t.test('anonymous clients still cannot read the catalogue', async () => {
      await asUser(null, 'anon');
      await rejected(() => db.query('select sponsor_business_category from public.quests'), '42501');
    });
  } finally {
    await db.close();
  }
});
