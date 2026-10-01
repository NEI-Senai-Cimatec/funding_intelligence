# Guia Oficial: Autenticação Supabase & Controle de Acesso (RBAC)
## Radar da Inovação – SENAI CIMATEC

Este documento é o guia definitivo para configurar o **Supabase** e gerenciar permissões no **Radar da Inovação** através da **Opção 3: Supabase Table Editor** (interface tipo Excel / planilha diretamente no painel do Supabase).

---

## 1. Níveis de Acesso e Regras de Negócio

| Recurso / Funcionalidade | Usuário Não Autenticado | Usuário Padrão (`leitor`) | Desenvolvedor / Diretoria (`diretoria`) |
| :--- | :---: | :---: | :---: |
| **Tela de Acesso** | **Bloqueio Total (Tela de Login)** | Acesso liberado | Acesso liberado |
| **Aba "Resultados"** | ❌ Não visualiza | ✅ **Visível** | ✅ **Visível** |
| **Aba "Por financiador"** | ❌ Não visualiza | ✅ **Visível** | ✅ **Visível** |
| **Botão "Atualizar base"** | ❌ Ocultado | ❌ **Ocultado** | ✅ **Visível e Executável** |
| **Aba "Buscas salvas"** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |
| **Aba "Editais rastreados"** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |
| **Aba "Logs" (Coletores & Scraping)** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |
| **Aba "Logs" (Auditoria de Acessos)** | ❌ Ocultada | ❌ **Ocultada** | ✅ **Visível** |

> **Sigilo e Segurança:** Nenhum edital, oportunidade ou dado é enviado pelo servidor Shiny enquanto o usuário não realizar o login com sucesso (`req(rv$user)`).

---

## 2. Configuração no Supabase (Opção 3: Table Editor)

Com a **Opção 3**, você não precisa digitar e-mails em arquivos de configuração e nem mexer em JSONs complexos. O gerenciamento é feito em uma tabela visual (tipo planilha) dentro do Supabase.

### Passo 1: Executar o Script SQL no Supabase
1. Acesse o painel do seu projeto no [Supabase](https://supabase.com).
2. No menu lateral esquerdo, clique no ícone **SQL Editor** (ou pressione a tecla de atalho correspondente).
3. Clique em **"New query"**.
4. Copie e cole o código SQL abaixo (também disponível em `sql/setup_supabase_perfis.sql`):

```sql
-- 1. Cria a tabela pública de perfis vinculada à autenticação do Supabase
create table if not exists public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  cargo text not null default 'leitor',
  criado_em timestamp with time zone default timezone('utc'::text, now()) not null
);

comment on table public.perfis is 'Tabela de controle de acesso (RBAC) do Radar da Inovação';
comment on column public.perfis.cargo is 'Permissão: "leitor" (padrão) ou "diretoria" (acesso irrestrito)';

-- 2. Habilita Row Level Security (RLS)
alter table public.perfis enable row level security;

-- Política de leitura: usuários autenticados podem consultar os perfis
drop policy if exists "Permitir leitura de perfis para autenticados" on public.perfis;
create policy "Permitir leitura de perfis para autenticados"
  on public.perfis
  for select
  to authenticated
  using (true);

-- 3. Função e Gatilho (Trigger) para cadastrar automaticamente novos usuários como 'leitor'
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.perfis (id, email, cargo)
  values (new.id, new.email, 'leitor')
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 4. Sincroniza retroativamente os usuários que você JÁ CRIOU
insert into public.perfis (id, email, cargo)
select id, email, 'leitor'
from auth.users
on conflict (id) do nothing;

-- 5. Exibe os perfis cadastrados para conferência
select id, email, cargo, criado_em from public.perfis order by criado_em desc;
```

5. Clique no botão verde **"Run"** (ou aperte `Ctrl + Enter`).
6. A mensagem **"Success. No rows returned"** (ou a tabela com seus 2 usuários já cadastrados) será exibida.

---

### Passo 2: Gerenciar Permissões no Supabase (Table Editor)

Agora todo o controle de quem é **Diretoria** ou **Leitor** é feito com 2 cliques:

1. No menu lateral esquerdo do Supabase, clique no ícone **Table Editor** (ícone em formato de tabela/planilha).
2. Na lista de tabelas do esquema `public`, clique em **`perfis`**.
3. Você verá todos os seus usuários listados em linhas, com as colunas:
   - `id`
   - `email`
   - `cargo`
   - `criado_em`
4. Por padrão, todo novo usuário entra automaticamente como `leitor`.
5. **Para transformar um usuário em Desenvolvedor / Diretoria:**
   - Dê **dois cliques** sobre a palavra `leitor` na coluna `cargo` do usuário desejado.
   - Digite `diretoria` (ou `dev`).
   - Pressione **Enter** (ou clique fora da célula).
6. Pronto! Da próxima vez que esse usuário fizer login no Radar da Inovação, ele terá acesso completo imediatamente.
7. Se quiser voltar o usuário para leitor, basta dar dois cliques e trocar para `leitor`.

---

## 3. Configuração das Chaves no `.Renviron`

Para o Radar da Inovação conectar ao seu projeto Supabase:

1. No Supabase, vá em **Project Settings** (ícone de engrenagem) -> **API**.
2. Copie:
   - **Project URL** (ex.: `https://xyzcompany.supabase.co`)
   - **Project API keys** -> chave **`anon` / `public`** (chave longa que inicia com `eyJ...`)
3. No projeto do Radar (`funding_intelligence`), abra o arquivo `.Renviron` e preencha:

```env
# Supabase Auth
SUPABASE_URL=https://SEU_PROJETO.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

4. Reinicie a aplicação Shiny.

---

## 4. Auditoria de Acessos (`user_access_logs`)

Todas as ações realizadas pelos usuários logados são registradas no banco de dados local com data, hora, e-mail e perfil:
- `LOGIN` (com o cargo resolvido do Supabase)
- `LOGOUT`
- `BUSCA` (termos pesquisados)
- `VISUALIZAR_EDITAL` (edital consultado)
- `EXPORTAR` (planilhas baixadas)
- `ATUALIZAR_BASE` (coletas oficiais disparadas)

Desenvolvedores e membros da Diretoria podem acompanhar esses logs em tempo real na aba **Logs** -> sub-aba **Auditoria de Acessos**.
