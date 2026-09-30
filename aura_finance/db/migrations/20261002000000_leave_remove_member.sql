-- Aura Finance — keluar dari rumah tangga & mengeluarkan anggota.
--
-- 1. leave_household: anggota keluar sendiri. Bila yang keluar adalah pemilik, kepemilikan
--    pindah ke anggota yang paling lama bergabung. Bila dia anggota terakhir, rumah tangga
--    beserta seluruh datanya dihapus (tabel data memakai on delete cascade) — aplikasi
--    menampilkan peringatan jelas sebelum memanggil ini.
-- 2. remove_member: pemilik mengeluarkan anggota lain. Data yang sudah dicatat anggota itu
--    tetap milik rumah tangga; ia hanya kehilangan akses.
--
-- Jalankan di Neon SQL Editor setelah 20261001000000_shared_private.sql.

create or replace function public.leave_household(p_household uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  me text := auth.user_id();
  my_role text;
  successor text;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select role into my_role from household_members where household_id = p_household and user_id = me;
  if my_role is null then raise exception 'Kamu bukan anggota rumah tangga ini'; end if;

  select user_id into successor from household_members
  where household_id = p_household and user_id <> me
  order by joined_at
  limit 1;

  if successor is null then
    delete from households where id = p_household;
    return 'deleted';
  end if;

  if my_role = 'owner' then
    update household_members set role = 'owner' where household_id = p_household and user_id = successor;
  end if;
  delete from household_members where household_id = p_household and user_id = me;
  return 'left';
end $$;

create or replace function public.remove_member(p_household uuid, p_user text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.user_id() is null then raise exception 'not authenticated'; end if;
  if not exists (
    select 1 from household_members where household_id = p_household and user_id = auth.user_id() and role = 'owner'
  ) then
    raise exception 'Hanya pemilik yang bisa mengeluarkan anggota';
  end if;
  if p_user = auth.user_id() then
    raise exception 'Gunakan "Keluar dari rumah tangga" untuk dirimu sendiri';
  end if;
  delete from household_members where household_id = p_household and user_id = p_user;
  if not found then raise exception 'Anggota tidak ditemukan'; end if;
end $$;
