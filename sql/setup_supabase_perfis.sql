-- ==============================================================================
-- RADAR DA INOVAÇÃO - SENAI CIMATEC
-- Script de Configuração de Perfis e Permissões 
-- ==============================================================================
-- Este script realiza 4 ações automáticas no seu banco de dados Supabase:
-- 1. Cria a tabela 'public.perfis' para controle de acesso (RBAC).
-- 2. Configura a segurança de acesso (Row Level Security - RLS).
-- 3. Cria um gatilho automático: qualquer novo usuário criado no Supabase Auth
--    será inserido automaticamente como 'leitor' na tabela perfis.
-- 4. Sincroniza retroativamente todos os usuários que você JÁ CRIOU, inserindo-os
--    na tabela perfis para você poder editar o cargo imediatamente.
-- ==============================================================================

-- 1. Cria a tabela pública de perfis vinculada à tabela nativa de autenticação
create table if not exists public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  cargo text not null default 'leitor',
  criado_em timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Comentários descritivos para identificação no Supabase Studio
comment on table public.perfis is 'Tabela de controle de acesso (RBAC) do Radar da Inovação';
comment on column public.perfis.cargo is 'Permissão de acesso: "leitor" (padrão) ou "diretoria" (acesso irrestrito)';

-- 2. Habilita Row Level Security (RLS)
alter table public.perfis enable row level security;

-- Política de leitura: usuários autenticados podem consultar os perfis
drop policy if exists "Permitir leitura de perfis para autenticados" on public.perfis;
create policy "Permitir leitura de perfis para autenticados"
  on public.perfis
  for select
  to authenticated
  using (true);

-- 3. Função e Gatilho (Trigger) para criar perfil automaticamente para novos usuários
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.perfis (id, email, cargo)
  values (new.id, new.email, 'leitor')
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$ language plpgsql security definer;

-- Remove versão anterior do gatilho se existir e recria
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 4. Sincronização dos usuários existentes:
-- Insere todos os usuários já criados anteriormente no Supabase Auth na tabela 'perfis'
insert into public.perfis (id, email, cargo)
select id, email, 'leitor'
from auth.users
on conflict (id) do nothing;

-- 5. Confirmação do resultado: exibe os perfis cadastrados
select id, email, cargo, criado_em from public.perfis order by criado_em desc;
