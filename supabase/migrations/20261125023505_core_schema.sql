-- Schema core da casca (Tlife/LifeOS)
-- Ver CLAUDE.md seção 3 (Arquitetura da casca / Banco) e seção 7 (Hermes)

create schema if not exists core;

-- Expor o schema pra API (PostgREST troca pra o papel anon/authenticated;
-- sem isto, criar o schema só dá acesso ao dono). RLS continua restringindo
-- linha a linha por baixo destes grants — anon não ganha acesso porque
-- os dados do core são todos de usuário autenticado.
grant usage on schema core to authenticated, service_role;
alter default privileges in schema core
  grant select, insert, update, delete on tables to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Utilitário: mantém atualizado_em em dia em qualquer tabela que o tenha
-- ---------------------------------------------------------------------------
create function core.set_atualizado_em()
returns trigger
language plpgsql
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- core.perfil — dados pessoais e preferências (Perfil, seção 8)
-- Uma linha por usuário, id = auth.users.id (1:1 com a conta).
-- ---------------------------------------------------------------------------
create table core.perfil (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text,
  avatar_url text,
  tema text not null default 'sistema' check (tema in ('claro', 'escuro', 'sistema')),
  idioma text not null default 'pt' check (idioma in ('pt', 'en')),
  inicio_semana smallint not null default 1 check (inicio_semana between 0 and 6),
  moeda text not null default 'BRL',
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create trigger set_atualizado_em
  before update on core.perfil
  for each row
  execute function core.set_atualizado_em();

alter table core.perfil enable row level security;

create policy "perfil: dono lê e escreve"
  on core.perfil for all
  using (id = auth.uid())
  with check (id = auth.uid());

-- Cria a linha de perfil assim que a conta é criada no Supabase Auth.
create function core.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into core.perfil (id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function core.handle_new_user();

-- ---------------------------------------------------------------------------
-- core.chave_recuperacao — hash do código de recuperação único (seção 8/9)
-- Um por usuário; regenerar substitui o anterior.
-- ---------------------------------------------------------------------------
create table core.chave_recuperacao (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() unique references auth.users (id) on delete cascade,
  hash text not null,
  criado_em timestamptz not null default now(),
  usado_em timestamptz
);

alter table core.chave_recuperacao enable row level security;

create policy "chave_recuperacao: dono lê e escreve"
  on core.chave_recuperacao for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- core.areas — áreas de vida (seção 3/5), compartilhadas por todos os serviços
-- ---------------------------------------------------------------------------
create table core.areas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nome text not null,
  cor text not null,
  icone text not null,
  ordem int not null default 0,
  criado_em timestamptz not null default now()
);

alter table core.areas enable row level security;

create policy "areas: dono lê e escreve"
  on core.areas for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- core.servicos_ativos — registro de serviços (ligar/desligar em Configurações)
-- servico_id é o id do manifesto do serviço (ex.: "hello", "tasks").
-- ---------------------------------------------------------------------------
create table core.servicos_ativos (
  usuario_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  servico_id text not null,
  ativo boolean not null default true,
  ativado_em timestamptz not null default now(),
  primary key (usuario_id, servico_id)
);

alter table core.servicos_ativos enable row level security;

create policy "servicos_ativos: dono lê e escreve"
  on core.servicos_ativos for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- core.eventos — barramento de eventos, log persistido (seção 3/4)
-- O pub/sub em memória (Zustand) é Controller; isto é o Model por trás dele.
-- ---------------------------------------------------------------------------
create table core.eventos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  servico_origem text not null,
  tipo text not null,
  dados jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now()
);

create index eventos_usuario_criado_idx
  on core.eventos (usuario_id, criado_em desc);

alter table core.eventos enable row level security;

create policy "eventos: dono lê e escreve"
  on core.eventos for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- core.inbox — inbox unificada (seção 3)
-- ---------------------------------------------------------------------------
create table core.inbox (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  titulo text not null,
  origem_servico text,
  origem_id text,
  lida boolean not null default false,
  criado_em timestamptz not null default now(),
  lida_em timestamptz
);

create index inbox_usuario_lida_idx
  on core.inbox (usuario_id, lida, criado_em desc);

alter table core.inbox enable row level security;

create policy "inbox: dono lê e escreve"
  on core.inbox for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- core.notificacoes — despachante central (seção 4)
-- ---------------------------------------------------------------------------
create table core.notificacoes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  evento_id uuid references core.eventos (id) on delete set null,
  canal text not null,
  prioridade text not null default 'normal',
  titulo text not null,
  corpo text,
  enviada_em timestamptz,
  lida_em timestamptz,
  criado_em timestamptz not null default now()
);

create index notificacoes_usuario_criado_idx
  on core.notificacoes (usuario_id, criado_em desc);

alter table core.notificacoes enable row level security;

create policy "notificacoes: dono lê e escreve"
  on core.notificacoes for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- core.perfil_hermes / core.perfil_hermes_notas (seção 7)
-- ---------------------------------------------------------------------------
create table core.perfil_hermes (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() unique references auth.users (id) on delete cascade,
  estilo_comunicacao text,
  area_prioritaria text,
  nivel_proatividade text,
  atualizado_em timestamptz not null default now()
);

create trigger set_atualizado_em
  before update on core.perfil_hermes
  for each row
  execute function core.set_atualizado_em();

alter table core.perfil_hermes enable row level security;

create policy "perfil_hermes: dono lê e escreve"
  on core.perfil_hermes for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

create table core.perfil_hermes_notas (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  categoria text,
  texto text not null,
  origem_evento text,
  criado_em timestamptz not null default now()
);

create index perfil_hermes_notas_usuario_idx
  on core.perfil_hermes_notas (usuario_id, criado_em desc);

alter table core.perfil_hermes_notas enable row level security;

create policy "perfil_hermes_notas: dono lê e escreve"
  on core.perfil_hermes_notas for all
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());
