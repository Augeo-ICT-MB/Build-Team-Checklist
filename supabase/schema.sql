-- Cvent QC Checklist: Supabase schema
-- Run this once in your Supabase project: Dashboard > SQL Editor > New query > paste > Run.
-- Safe to re-run.

-- 1. Tables ---------------------------------------------------------------

-- One row per event checklist. Project Cover, sign-off, reg types,
-- activities and custom rows live here.
create table if not exists public.checklists (
  id             uuid primary key default gen_random_uuid(),
  project_number text,                                   -- copied from cover for the list view
  event_name     text,                                   -- copied from cover for the list view
  cover          jsonb   not null default '{}'::jsonb,   -- Project Cover fields
  signoff        jsonb   not null default '{}'::jsonb,   -- Final Sign-Off table
  reg_types      jsonb   not null default '[]'::jsonb,   -- [{id, name}]
  activities     jsonb   not null default '[]'::jsonb,   -- [{id, name}]
  custom_rows    jsonb   not null default '{}'::jsonb,   -- rows reviewers added
  attest         boolean not null default false,
  created_by     uuid default auth.uid() references auth.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_by     uuid default auth.uid() references auth.users (id) on delete set null,
  updated_at     timestamptz not null default now()
);

-- One row per check that someone has touched. Untouched checks are
-- simply "Not Started" and have no row.
create table if not exists public.check_results (
  checklist_id uuid not null references public.checklists (id) on delete cascade,
  key          text not null,            -- e.g. "s3|-|0.4" or "s6|rt1|2.3"
  status       text not null default 'Not Started'
               check (status in ('Not Started','In Progress','Pass','Fail','Blocked','N/A')),
  prev_status  text,                     -- status to restore when N/A is switched off
  see          text,                     -- What I See in the Build
  notes        text,
  reviewer     text,
  checked_on   date,
  severity     text check (severity is null or severity in ('Critical','High','Medium','Low')),
  expected     text,                     -- reviewer's override of the Expected text
  updated_by   uuid default auth.uid() references auth.users (id) on delete set null,
  updated_at   timestamptz not null default now(),
  primary key (checklist_id, key)
);

create index if not exists checklists_updated_at_idx on public.checklists (updated_at desc);

-- 2. Housekeeping triggers ----------------------------------------------

create or replace function public.qc_checklists_touch()
returns trigger language plpgsql as $$
begin
  new.project_number := nullif(trim(new.cover->>'Project Number (26XXX)'), '');
  new.event_name     := nullif(trim(new.cover->>'Event Name'), '');
  new.updated_at     := now();
  new.updated_by     := coalesce(auth.uid(), new.updated_by);
  return new;
end $$;

drop trigger if exists qc_checklists_touch on public.checklists;
create trigger qc_checklists_touch
  before insert or update on public.checklists
  for each row execute function public.qc_checklists_touch();

create or replace function public.qc_results_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  -- Bump the parent's "last updated" at most every 30 seconds.
  update public.checklists
     set updated_at = now()
   where id = new.checklist_id
     and updated_at < now() - interval '30 seconds';
  return new;
end $$;

drop trigger if exists qc_results_touch on public.check_results;
create trigger qc_results_touch
  before insert or update on public.check_results
  for each row execute function public.qc_results_touch();

-- 3. Field-level merge for Project Cover and Sign-Off --------------------
-- Two reviewers editing different cover fields at once won't overwrite
-- each other. Runs with the caller's permissions, so access rules apply.

create or replace function public.merge_checklist_json(p_id uuid, p_cover jsonb, p_signoff jsonb)
returns void language sql security invoker as $$
  update public.checklists
     set cover   = cover   || coalesce(p_cover,   '{}'::jsonb),
         signoff = signoff || coalesce(p_signoff, '{}'::jsonb)
   where id = p_id;
$$;

-- 4. Access rules (Row Level Security) -----------------------------------
-- Only signed-in users can read or write. Who can sign in is controlled in
-- Authentication settings: turn OFF "Allow new users to sign up" and invite
-- your team. Only the person who created a checklist can delete it.

alter table public.checklists    enable row level security;
alter table public.check_results enable row level security;

revoke all on public.checklists, public.check_results from anon;
grant select, insert, update, delete on public.checklists, public.check_results to authenticated;
revoke execute on function public.merge_checklist_json(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.merge_checklist_json(uuid, jsonb, jsonb) to authenticated;

drop policy if exists "team reads checklists"   on public.checklists;
drop policy if exists "team creates checklists" on public.checklists;
drop policy if exists "team edits checklists"   on public.checklists;
drop policy if exists "creator deletes checklist" on public.checklists;
create policy "team reads checklists"   on public.checklists for select to authenticated using (true);
create policy "team creates checklists" on public.checklists for insert to authenticated with check (true);
create policy "team edits checklists"   on public.checklists for update to authenticated using (true) with check (true);
create policy "creator deletes checklist" on public.checklists for delete to authenticated using (created_by = auth.uid());

drop policy if exists "team works on results" on public.check_results;
create policy "team works on results" on public.check_results for all to authenticated using (true) with check (true);

-- Optional: limit access to one email domain as a second safety net.
-- Replace both policies above with versions that add:
--   and (auth.jwt() ->> 'email') ilike '%@yourcompany.com'

-- 5. Live updates ----------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'checklists') then
    alter publication supabase_realtime add table public.checklists;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'check_results') then
    alter publication supabase_realtime add table public.check_results;
  end if;
end $$;
