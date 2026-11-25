# Checklist do Tlife

## Fase 1: Casca

### Back
- [x] Supabase local + schema `core` (RLS testada)
- [ ] Commitar a base
- [ ] Seed local: usuário de dev, áreas padrão, serviço `hello` ativo
- [ ] Código de recuperação: gerar o hash e trocar a senha com o código (RPC ou Edge Function)
- [ ] Gerar os tipos TS do banco (`supabase gen types`)
- [ ] Projeto na nuvem: `supabase link` + `db push`

### Front
- [ ] Confirmar Expo + Expo Router (item em aberto) e criar o projeto em TS
- [ ] ESLint travando a fronteira de módulo, Jest + RNTL
- [ ] Client Supabase com `expo-secure-store` e `.env`
- [ ] `tema` (tokens claro/escuro/sistema) e `i18n` (pt/en)
- [ ] `auth`: login, cadastro, tela do código de recuperação, recuperar acesso
- [ ] `registro`: manifesto + `src/services/index.ts`
- [ ] Layout com menu montado a partir dos serviços ativos, mais a rota `s/[servico]`
- [ ] `eventos` (Zustand + log) e `inbox`
- [ ] Painel com os widgets
- [ ] Configurações › Serviços (ligar/desligar)
- [ ] Perfil
- [ ] Busca global ⌘K
- [ ] Serviço `hello` passando os 3 critérios de pronto

## Fase 2: Notificações
- [ ] Back: tabela de push tokens (falta no `core`, migração nova)
- [ ] Back: despachante em Edge Function (prioridade, silêncio, agrupamento, duplicidade)
- [ ] Front: `expo-notifications`, registro do token, tela de notificações

## Fase 3: Tasks
- [ ] Back: schema `svc_tasks` + RLS, ordem espaçada
- [ ] Front: quadros, colunas e cards com arrastar e soltar; visão Hoje; coluna Entrada; checklist e etiquetas
- [ ] Widget, eventos e ações para o Hermes

## Fase 4: Hermes
- [ ] Servidor MCP (contexto, ações, perfil)
- [ ] Conversa no app e no Telegram

## Fase 5: Demais serviços
- [ ] Financeiro (Pluggy), Email (n8n), Academia, Conteúdo, Metas

## Fase 6: Web e Obsidian
- [ ] Layout de tela larga + Web Push
- [ ] Ponte com o Obsidian
