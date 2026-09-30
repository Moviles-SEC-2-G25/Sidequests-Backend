import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { test } from 'node:test';
import { PGlite } from '@electric-sql/pglite';

// Supabase supplies auth/storage in production. These minimal fixtures let us run
// the real migrations and RLS in local PostgreSQL, without any deployed project.
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
  grant select, insert, update, delete on storage.objects to anon, authenticated;
  create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
  $$;
`;

const alice = '11111111-1111-4111-8111-111111111111';
const bob = '22222222-2222-4222-8222-222222222222';
const aliceAttempt = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const bobAttempt = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const path = (user, attempt, step = 4, suffix = 'proof') =>
  `${user}/${attempt}/botanical-garden/step-${step}-${suffix}.jpg`;

test('migration 009 protects quest photo objects and per-step records', async (t) => {
  const db = new PGlite();
  try {
    await db.exec(platformFixture);
    const migrations = new URL('../supabase/migrations/', import.meta.url);
    for (const migration of (await readdir(migrations)).filter(name => name.endsWith('.sql')).sort()) {
      await db.exec(await readFile(new URL(migration, migrations), 'utf8'));
    }
    await db.exec(await readFile(new URL('../supabase/seed.sql', import.meta.url), 'utf8'));
    await db.query('insert into auth.users (id) values ($1), ($2)', [alice, bob]);
    await db.query(`insert into public.user_quests (id, user_id, quest_id)
      values ($1, $2, 'botanical-garden'), ($3, $4, 'botanical-garden')`,
      [aliceAttempt, alice, bobAttempt, bob]);

    const asUser = async (user, role = 'authenticated') => {
      await db.exec('reset role');
      await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user ?? '']);
      await db.exec(`set role ${role}`);
    };
    const upload = (name, bucket = 'quest-proofs') => db.query(
      'insert into storage.objects (bucket_id, name) values ($1, $2) returning name',
      [bucket, name]);
    const register = (attempt, name, step = 3) => db.query(
      'insert into public.quest_photo_proofs (attempt_id, step_order, storage_path) values ($1, $2, $3)',
      [attempt, step, name]);
    const denied = operation => assert.rejects(operation, error => error.code === '42501');

    await t.test('bucket is private and limited to JPEG evidence', async () => {
      const { rows } = await db.query("select * from storage.buckets where id = 'quest-proofs'");
      assert.equal(rows[0].public, false);
      assert.equal(Number(rows[0].file_size_limit), 25 * 1024 * 1024);
      assert.deepEqual(rows[0].allowed_mime_types, ['image/jpeg']);
    });

    await t.test('owner can upload, register and read a photo-required step', async () => {
      await asUser(alice);
      await upload(path(alice, aliceAttempt));
      await register(aliceAttempt, path(alice, aliceAttempt));
      assert.equal((await db.query('select * from public.quest_photo_proofs')).rows.length, 1);
      assert.equal((await db.query('select * from storage.objects')).rows.length, 1);
    });

    await t.test('another user cannot read, upload to, register or delete owner evidence', async () => {
      await asUser(bob);
      assert.equal((await db.query('select * from storage.objects')).rows.length, 0);
      assert.equal((await db.query('select * from public.quest_photo_proofs')).rows.length, 0);
      await denied(() => upload(path(alice, aliceAttempt, 4, 'intrusion')));
      await denied(() => upload(path(bob, aliceAttempt, 4, 'wrong-attempt')));
      await denied(() => register(aliceAttempt, path(alice, aliceAttempt)));
      assert.equal((await db.query('delete from storage.objects where name = $1 returning id',
        [path(alice, aliceAttempt)])).rows.length, 0);
      await upload(path(bob, bobAttempt));
      await register(bobAttempt, path(bob, bobAttempt));
      assert.equal((await db.query('select * from public.quest_photo_proofs')).rows.length, 1);
    });

    await t.test('non-photo steps, wrong quests, nested paths and unuploaded proofs are rejected', async () => {
      await asUser(alice);
      await denied(() => upload(path(alice, aliceAttempt, 1, 'non-photo')));
      await denied(() => upload(path(alice, aliceAttempt).replace('/botanical-garden/', '/ramen-spot/')));
      await denied(() => upload(path(alice, aliceAttempt) + '/nested.jpg'));
      await denied(() => upload(path(alice, aliceAttempt) + '//nested.jpg'));
      await denied(() => upload(path(alice, aliceAttempt) + '/'));
      await denied(() => register(aliceAttempt, path(alice, aliceAttempt, 4, 'missing')));
      await denied(() => register(aliceAttempt, path(alice, aliceAttempt), 0));
    });

    await t.test('owner can clean up an unregistered upload; overwrites are disallowed', async () => {
      await asUser(alice);
      const cleanupPath = path(alice, aliceAttempt, 4, 'cleanup');
      await upload(cleanupPath);
      assert.equal((await db.query('delete from storage.objects where name = $1 returning id',
        [cleanupPath])).rows.length, 1);
      assert.equal((await db.query('update storage.objects set name = $1 returning id',
        [path(bob, bobAttempt)])).rows.length, 0);
      await denied(() => db.query('update public.quest_photo_proofs set step_order = 0'));
    });

    await t.test('anonymous clients cannot read or write evidence', async () => {
      await asUser(null, 'anon');
      assert.equal((await db.query('select * from storage.objects')).rows.length, 0);
      await denied(() => upload(path(alice, aliceAttempt, 4, 'anonymous')));
      await denied(() => db.query('select * from public.quest_photo_proofs'));
    });
  } finally {
    await db.close();
  }
});
