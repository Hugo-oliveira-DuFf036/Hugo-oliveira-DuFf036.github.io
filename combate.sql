-- Combate da Sala da Masmorra: rode UMA vez no Supabase (SQL Editor).
-- Só o Mestre da sala grava; jogadores só leem a versão pública (sem PV de NPC se o mestre não liberar).
create table if not exists public.room_combat (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  pub jsonb not null default '{}'::jsonb,
  rev bigint not null default 0,
  updated_at timestamptz not null default now());
create table if not exists public.room_combat_master (
  room_id uuid primary key references public.rooms(id) on delete cascade,
  state jsonb not null default '{}'::jsonb);
alter table public.room_combat enable row level security;
alter table public.room_combat_master enable row level security;
drop policy if exists combat_read on public.room_combat;
create policy combat_read on public.room_combat for select to authenticated using (
  exists (select 1 from public.room_members m where m.room_id = room_combat.room_id and m.user_id = auth.uid() and m.status = 'active'));
drop policy if exists combat_master_read on public.room_combat_master;
create policy combat_master_read on public.room_combat_master for select to authenticated using (
  exists (select 1 from public.rooms r where r.id = room_combat_master.room_id and r.master_id = auth.uid()));
-- sem policies de insert/update/delete: a escrita só acontece pela função abaixo.
create or replace function public.set_combat(p_room uuid, p_pub jsonb, p_full jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'not_authenticated'); end if;
  if not exists (select 1 from public.rooms r where r.id = p_room and r.master_id = auth.uid() and r.status = 'open') then
    return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if pg_column_size(p_pub) > 200000 or pg_column_size(p_full) > 400000 then
    return jsonb_build_object('ok', false, 'error', 'too_large'); end if;
  insert into public.room_combat(room_id, pub, rev) values (p_room, p_pub, coalesce((p_pub->>'rev')::bigint, 0))
    on conflict (room_id) do update set pub = excluded.pub, rev = excluded.rev, updated_at = now();
  insert into public.room_combat_master(room_id, state) values (p_room, p_full)
    on conflict (room_id) do update set state = excluded.state;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.set_combat(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.set_combat(uuid, jsonb, jsonb) to authenticated;
do $$ begin alter publication supabase_realtime add table public.room_combat; exception when others then null; end $$;
