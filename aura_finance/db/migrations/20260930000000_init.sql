-- Aura Finance — skema awal untuk Neon
-- Prasyarat: Neon Auth (Managed Better Auth) & Data API sudah diaktifkan untuk database ini
-- (fungsi auth.user_id() dan role `authenticated` disediakan oleh Neon).
-- Jalankan di Neon Console: SQL Editor -> tempel file ini -> Run.
-- ID pengguna dari Better Auth berupa teks, jadi kolom pengguna bertipe text.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Profil & rumah tangga

create table public.profiles (
  id text primary key,
  display_name text not null default '',
  avatar text,
  created_at timestamptz not null default now()
);

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text not null unique,
  created_by text,
  created_at timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households on delete cascade,
  user_id text not null,
  role text not null default 'member' check (role in ('owner', 'member')),
  color bigint,
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create or replace function public.is_member(hid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from household_members where household_id = hid and user_id = auth.user_id());
$$;

create or replace function public.new_invite_code()
returns text language sql volatile as $$
  -- Tanpa huruf/angka yang mirip (0/O, 1/I) supaya mudah dibacakan.
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random() * 32) + 1)::int, 1), '')
  from generate_series(1, 6);
$$;

create or replace function public.create_household(p_name text)
returns public.households language plpgsql security definer set search_path = public as $$
declare h households;
begin
  if auth.user_id() is null then raise exception 'not authenticated'; end if;
  insert into households (name, invite_code, created_by) values (p_name, new_invite_code(), auth.user_id()) returning * into h;
  insert into household_members (household_id, user_id, role, color) values (h.id, auth.user_id(), 'owner', 4294861987);
  return h;
end $$;

create or replace function public.join_household(p_code text)
returns public.households language plpgsql security definer set search_path = public as $$
declare h households;
begin
  if auth.user_id() is null then raise exception 'not authenticated'; end if;
  select * into h from households where invite_code = upper(trim(p_code));
  if h.id is null then raise exception 'Kode undangan tidak ditemukan'; end if;
  insert into household_members (household_id, user_id, role, color)
  values (h.id, auth.user_id(), 'member', 4288126846)
  on conflict do nothing;
  return h;
end $$;

create or replace function public.regenerate_invite_code(p_household uuid)
returns text language plpgsql security definer set search_path = public as $$
declare code text;
begin
  if not exists (select 1 from household_members where household_id = p_household and user_id = auth.user_id() and role = 'owner') then
    raise exception 'Hanya pemilik yang bisa membuat kode baru';
  end if;
  code := new_invite_code();
  update households set invite_code = code where id = p_household;
  return code;
end $$;

create or replace view public.household_member_profiles with (security_invoker = true) as
  select m.household_id, m.user_id, m.role, m.color, coalesce(p.display_name, '') as display_name, p.avatar
  from household_members m left join profiles p on p.id = m.user_id;

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;

create policy "profil sendiri & sesama anggota" on public.profiles for select using (
  id = auth.user_id() or exists (
    select 1 from household_members a join household_members b on a.household_id = b.household_id
    where a.user_id = auth.user_id() and b.user_id = profiles.id
  )
);
create policy "ubah profil sendiri" on public.profiles for insert with check (id = auth.user_id());
create policy "update profil sendiri" on public.profiles for update using (id = auth.user_id());

create policy "lihat rumah tangga sendiri" on public.households for select using (is_member(id));
create policy "lihat sesama anggota" on public.household_members for select using (is_member(household_id));
create policy "keluar dari rumah tangga" on public.household_members for delete using (user_id = auth.user_id());

-- ---------------------------------------------------------------------------
-- Tabel yang disinkronkan
-- Setiap tabel: id dari perangkat, household_id, created_by, updated_at dari perangkat
-- (dipakai last-write-wins), dan server_updated_at dari server (dipakai untuk pull bertahap).

create or replace function public.touch_server_updated_at()
returns trigger language plpgsql as $$
begin
  new.server_updated_at := now();
  return new;
end $$;

create table public.wallets (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  name text not null,
  kind text not null,
  initial_balance bigint not null default 0,
  color bigint not null,
  is_shared boolean not null default true,
  sort_order int not null default 0,
  archived boolean not null default false
);

create table public.categories (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  name text not null,
  kind text not null,
  icon text not null,
  color bigint not null,
  sort_order int not null default 0,
  archived boolean not null default false,
  seed_key text
);

create table public.transactions (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  kind text not null check (kind in ('income', 'expense', 'transfer')),
  amount bigint not null check (amount >= 0),
  wallet_id uuid not null,
  to_wallet_id uuid,
  category_id uuid,
  note text not null default '',
  occurred_at timestamptz not null,
  recurring_rule_id uuid,
  bill_id uuid
);

create table public.budgets (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  category_id uuid not null,
  month timestamptz not null,
  limit_amount bigint not null
);

create table public.goals (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  name text not null,
  target bigint not null,
  deadline timestamptz,
  illustration text not null,
  color bigint not null,
  achieved_at timestamptz,
  archived boolean not null default false
);

create table public.goal_contributions (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  goal_id uuid not null,
  amount bigint not null,
  note text not null default '',
  occurred_at timestamptz not null
);

create table public.recurring_rules (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  kind text not null,
  amount bigint not null,
  wallet_id uuid not null,
  category_id uuid,
  note text not null default '',
  frequency text not null,
  next_run timestamptz not null,
  active boolean not null default true
);

create table public.bills (
  id uuid primary key,
  household_id uuid not null references public.households on delete cascade,
  created_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  server_updated_at timestamptz not null default now(),
  name text not null,
  amount bigint not null,
  due_date timestamptz not null,
  remind_days_before int not null default 3,
  repeat_monthly boolean not null default true,
  wallet_id uuid,
  category_id uuid,
  paid_at timestamptz
);

do $$
declare t text;
begin
  foreach t in array array['wallets','categories','transactions','budgets','goals','goal_contributions','recurring_rules','bills'] loop
    execute format('create index on public.%I (household_id, server_updated_at)', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.touch_server_updated_at()', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
  -- Tabel umum: semua anggota rumah tangga boleh baca/tulis.
  foreach t in array array['categories','budgets','goals','goal_contributions','recurring_rules','bills'] loop
    execute format('create policy "anggota" on public.%I for all using (is_member(household_id)) with check (is_member(household_id))', t);
  end loop;
end $$;

-- Dompet pribadi hanya terlihat oleh pembuatnya, begitu juga transaksinya.
create or replace function public.wallet_visible(wid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from wallets w
    where w.id = wid and is_member(w.household_id) and (w.is_shared or w.created_by = auth.user_id())
  );
$$;

create policy "anggota: dompet" on public.wallets for select
  using (is_member(household_id) and (is_shared or created_by = auth.user_id()));
create policy "anggota: tambah dompet" on public.wallets for insert
  with check (is_member(household_id));
create policy "anggota: ubah dompet" on public.wallets for update
  using (is_member(household_id) and (is_shared or created_by = auth.user_id()))
  with check (is_member(household_id));

create policy "anggota: transaksi" on public.transactions for select
  using (is_member(household_id) and (created_by = auth.user_id() or wallet_visible(wallet_id)));
create policy "anggota: tambah transaksi" on public.transactions for insert
  with check (is_member(household_id));
create policy "anggota: ubah transaksi" on public.transactions for update
  using (is_member(household_id) and (created_by = auth.user_id() or wallet_visible(wallet_id)))
  with check (is_member(household_id));

-- ---------------------------------------------------------------------------
-- Hak akses untuk role `authenticated` (pengguna dengan JWT valid dari Neon Auth).
-- Aman diberikan luas karena setiap tabel dilindungi RLS di atas.

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
