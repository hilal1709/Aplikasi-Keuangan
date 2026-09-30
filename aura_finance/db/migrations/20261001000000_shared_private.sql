-- Aura Finance — target & budget pribadi, setor dari dompet, dan perbaikan privasi.
--
-- 1. goals.is_shared & budgets.is_shared: data pribadi hanya terlihat oleh pembuatnya.
-- 2. goal_contributions.wallet_id: setoran bisa mengurangi saldo dompet sumbernya.
-- 3. Transaksi berulang & tagihan yang memakai dompet pribadi kini ikut tersembunyi
--    (sebelumnya terlihat oleh semua anggota walau dompetnya pribadi).

alter table public.goals add column if not exists is_shared boolean not null default true;
alter table public.budgets add column if not exists is_shared boolean not null default true;
alter table public.goal_contributions add column if not exists wallet_id uuid;

create or replace function public.goal_visible(gid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from goals g
    where g.id = gid and is_member(g.household_id) and (g.is_shared or g.created_by = auth.user_id())
  );
$$;

-- Target -----------------------------------------------------------------------
drop policy if exists "anggota" on public.goals;
create policy "anggota: target" on public.goals for select
  using (is_member(household_id) and (is_shared or created_by = auth.user_id()));
create policy "anggota: tambah target" on public.goals for insert
  with check (is_member(household_id));
create policy "anggota: ubah target" on public.goals for update
  using (is_member(household_id) and (is_shared or created_by = auth.user_id()))
  with check (is_member(household_id));

-- Setoran target: mengikuti visibilitas targetnya ------------------------------
drop policy if exists "anggota" on public.goal_contributions;
create policy "anggota: setoran" on public.goal_contributions for select
  using (is_member(household_id) and (created_by = auth.user_id() or goal_visible(goal_id)));
create policy "anggota: tambah setoran" on public.goal_contributions for insert
  with check (is_member(household_id));
create policy "anggota: ubah setoran" on public.goal_contributions for update
  using (is_member(household_id) and (created_by = auth.user_id() or goal_visible(goal_id)))
  with check (is_member(household_id));

-- Budget -----------------------------------------------------------------------
drop policy if exists "anggota" on public.budgets;
create policy "anggota: budget" on public.budgets for select
  using (is_member(household_id) and (is_shared or created_by = auth.user_id()));
create policy "anggota: tambah budget" on public.budgets for insert
  with check (is_member(household_id));
create policy "anggota: ubah budget" on public.budgets for update
  using (is_member(household_id) and (is_shared or created_by = auth.user_id()))
  with check (is_member(household_id));

-- Transaksi berulang: ikut visibilitas dompetnya --------------------------------
drop policy if exists "anggota" on public.recurring_rules;
create policy "anggota: berulang" on public.recurring_rules for select
  using (is_member(household_id) and (created_by = auth.user_id() or wallet_visible(wallet_id)));
create policy "anggota: tambah berulang" on public.recurring_rules for insert
  with check (is_member(household_id));
create policy "anggota: ubah berulang" on public.recurring_rules for update
  using (is_member(household_id) and (created_by = auth.user_id() or wallet_visible(wallet_id)))
  with check (is_member(household_id));

-- Tagihan: tanpa dompet = bersama; dengan dompet = ikut visibilitas dompetnya ---
drop policy if exists "anggota" on public.bills;
create policy "anggota: tagihan" on public.bills for select
  using (is_member(household_id) and (created_by = auth.user_id() or wallet_id is null or wallet_visible(wallet_id)));
create policy "anggota: tambah tagihan" on public.bills for insert
  with check (is_member(household_id));
create policy "anggota: ubah tagihan" on public.bills for update
  using (is_member(household_id) and (created_by = auth.user_id() or wallet_id is null or wallet_visible(wallet_id)))
  with check (is_member(household_id));

grant execute on function public.goal_visible(uuid) to authenticated;
