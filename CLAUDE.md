# CLAUDE.md — Tlife (LifeOS)

Sistema pessoal de gestão de vida, descentralizado: uma **casca** pequena onde serviços se plugam. Este arquivo reúne só o que foi decidido e conversado sobre o projeto. O que ainda é proposta ou está em aberto fica marcado. O histórico de como se chegou a cada decisão de arquitetura fica na Biblioteca de Alexandria, não aqui (seção 12).

## 1. Visão

- Nome: **Tlife** (chamado de **LifeOS** nas conversas). Uso pessoal, de uma pessoa só.
- Origem: frustração com Notion e com o calendário. A ideia é centralizar tudo em um sistema só, simples e personalizado, com apenas os segmentos necessários.
- Deve ser **web e app, com notificações**.
- Decisão mais recente: **React Native, mobile primeiro, web depois**.
- Estado atual: existe uma versão web rudimentar com login, seções, tasks, metas, financeiro (raso), academia, conteúdo e configurações. A decisão foi **retroceder e construir só a casca** (sistema descentralizado, sem regra de negócio). Depois cada seção atual volta como um serviço plugado.

## 2. Ecossistema

| Peça | Papel |
|---|---|
| **Tlife/LifeOS** | Interface do dia a dia: casca + serviços plugáveis |
| **Hermes Agent** (Nous Research) | Agente "cérebro" |

**Produto vs. uso pessoal do dono:** para qualquer usuário do Tlife, o Hermes é só um agente assistente dentro do app — contexto do Tlife + o perfil que ele constrói sozinho (seção 7). O parágrafo abaixo descreve como o dono do projeto pretende usar o Hermes **para si mesmo**, fora do Tlife — não é requisito de arquitetura do produto, e Obsidian, Maestri e n8n não são assumidos pra quem só usa o app.

**O ecossistema funciona bem por si só, mas ao integrar o Hermes você pode fazer e usar ainda mais contexto, visto que todo o sistema é contextualizado, então o agente recebe o contexto das suas informações, sejam elas tasks, metas, financeiro, projetos e etc... ele é como seu agente pessoal.** Porém ao olhar por trás é possível alimentar o Hermes de forma mais inovadora, o ecossistema harpness não se limita apenas a uma plataforma visual, ele é uma gestão que compõe o cérebro, a memória, os olhos e as mãos. Hermes é o agente central que recebe de contexto o Vault do Obsidian (memória), usa ferramentas como whatsapp, telegram, n8n (ferramentas) e os agentes que seriam os funcionários trabalhando de forma organizada no maestri (olhos)

## 3. Arquitetura da casca

A casca só cuida do que é comum a todos os serviços:

- Login (Supabase Auth)
- Layout e menu, montados a partir dos serviços ativos
- **Registro de serviços**, com ligar e desligar em Configurações
- **Painel** com espaços para os widgets dos serviços
- **Inbox** unificada
- **Barramento de eventos**
- **Notificações** (despachante central)
- **Busca global** (⌘K)
- **Perfil** (parte da casca, não é widget)
- **Hermes** (assistente sempre presente — não é serviço nem widget, sem ligar/desligar em Configurações › Serviços; detalhe seção 7)
- **Áreas de vida** (`core.areas`), compartilhadas por todos os serviços

**O sistema é leve e funcional, ele começa apenas com o necessário. Você cria o resto**, ele também terá um Agente de IA integrado (Hermes) que melhora a cada ação. 

**Regra de ouro:** um serviço nunca importa nada de dentro do núcleo. Ele só fala com cada módulo do núcleo pela interface pública que esse módulo expõe — sem um SDK único (detalhe de como na seção 9 e no histórico, seção 12).

### Contrato do serviço (manifesto)

Cada serviço declara o que oferece. Exemplo conceitual:

```ts
interface ServicoTlife {
  id: string; nome: string; icone: string;
  telas: /* rotas/telas do serviço */;
  widgets?: Widget[];            // cards do painel
  configuracoes?: Componente;
  eventos?: string[];            // o que publica
  acoes?: Record<string, Acao>;  // ferramentas para o Hermes
  busca?: /* o que a busca global indexa */;
  notificacoes?: { evento: string; prioridade: string }[];
}
```

### Como um serviço fala com o núcleo (sem SDK único)

Cada capacidade do núcleo é seu próprio módulo (`eventos`, `inbox`, `notificacoes`, `busca`, `config`, `areas`, `auth`, `tema`, `i18n`, `perfil`, `registro`), e só expõe a própria interface. Um serviço importa direto o que usa, nunca um objeto único que reúna tudo:

```ts
import { useEventBus } from '@core/eventos/controller'
import { useInbox } from '@core/inbox/controller'

useEventBus().publicar('task.criada', dados)
useInbox().adicionar({ titulo, origem })
```

Um SDK único (`tlife.*`) era a ideia original, mas entregava a todo serviço capacidades que ele não usava. Arquitetura completa (MVC por módulo, SOLID, estado, fronteira de módulo) na seção 9.

### Banco (Supabase/PostgreSQL, RLS em tudo)

- Schema `core`: perfil, perfil_hermes + perfil_hermes_notas, chave_recuperacao, serviços ativos, eventos, inbox, notificações, áreas.
- Um schema `svc_<id>` por serviço.
- Para o schema próprio funcionar pela API, ele precisa estar nos *Exposed schemas* do Supabase (`api.schemas` no `supabase/config.jsonc` local, e nas configurações da API na nuvem). A alternativa é usar prefixo no `public` (`svc_tasks_cards`).
- **Onde roda:** local no desenvolvimento (`npx supabase start`, Supabase CLI sobre Docker), nuvem do Supabase em produção. O schema só muda por migração em `supabase/migrations/`, testada local (`supabase db reset`) e aplicada na nuvem com `supabase db push`.

### Critério de pronto da casca

1. Um serviço de exemplo ("hello") aparece no menu e no painel só por existir.
2. Desligá-lo em Configurações tira ele do menu e do painel.
3. Ele publica um evento e o evento aparece na inbox.

Depois disso, portar o Tasks vira "escrever um serviço".

## 4. Notificações

Fazem parte do núcleo, não de cada serviço.

1. Os serviços só publicam eventos (`task.atrasada`, `email.importante`, `conta.vencendo`).
2. Um **despachante** central (Edge Function do Supabase ou n8n) decide se, quando e por onde avisar.
3. Canais: push no app, Web Push no navegador (fase web) e Telegram via Hermes.

O despachante resolve: duplicidade entre canais, horário de silêncio e prioridade por serviço (email importante toca, notícia nunca toca) e agrupamento (dez emails viram um aviso só).

## 5. Serviço Tasks (primeiro serviço)

Um Trello simplificado e melhorado, porque o modelo de tarefas do Trello é o que o dono gosta.

**Estrutura:** `Área → Quadro → Coluna → Card`. Um quadro por área de vida (Pessoal, Freelas, FATEC, Garimpou). Projetos grandes ganham quadro próprio dentro da área e são arquivados quando terminam.

**Fica do Trello:** quadros, colunas, cards com arrastar e soltar, descrição, checklist, etiquetas, data de entrega.
**Sai:** membros, permissões, Power-Ups, comentários e o Butler (quem automatiza é o Hermes ou o n8n).
**Entra:**

- Visão **Hoje** (cards de hoje ou atrasados de todos os quadros, agrupados por área).
- Coluna **Entrada** em todo quadro, para onde cai o "virar tarefa" de qualquer serviço.
- Cards com vínculo de origem (`origem_servico`, `origem_id`), por exemplo email ou transação.
- Datas que viram lembrete.

**Modelos de colunas:** Padrão (Entrada → A fazer → Fazendo → Feito), Freela (Entrada → Orçamento → Fazendo → Revisão → Entregue), FATEC (Entrada → A fazer → Fazendo → Entregue).

**Esquema:**

```sql
svc_tasks.quadros   (id, area_id, nome, ordem, modelo, arquivado_em)
svc_tasks.colunas   (id, quadro_id, nome, ordem)
svc_tasks.cards     (id, coluna_id, titulo, descricao, prazo, ordem,
                     concluido_em, origem_servico, origem_id)
svc_tasks.checklist (id, card_id, texto, feito, ordem)
svc_tasks.etiquetas + svc_tasks.card_etiquetas
core.areas          (id, nome, cor, icone, ordem)   -- fica no núcleo
```

Ordem dos cards: valores numéricos espaçados (1000, 2000…), assim mover um card altera uma linha só.

**Ações para o Hermes:** `criar_card`, `mover_card`, `concluir_card`, `listar_hoje`.
**Eventos:** `task.criada`, `task.concluida`, `task.atrasada`.

## 6. Outros serviços (ideias discutidas)

- **Emails importantes:** o n8n lê o Gmail, a IA classifica a importância e só os importantes entram na inbox, com remetente, resumo e link para o Gmail, e ações como "virar tarefa" e "rascunhar resposta". Não guardar o conteúdo completo dos emails no Supabase, só metadados, resumo e link.
- **Financeiro:** versão pessoal do FinanSmart, com Pluggy.
- **Academia, Conteúdo, Metas:** voltam como serviços a partir da versão atual.
- **Portal de notícias:** sistema à parte, só se conecta.

## 7. Hermes

- O **Hermes** é a única porta de conversa (Telegram ou app), lê o Supabase e decide o que fazer; acessa via MCP.
- **Não é um widget nem um serviço plugável** — é parte da casca, sempre presente, sem ligar/desligar em Configurações › Serviços (como o Perfil).
- **O que o diferencia de um agente comum:** constrói um perfil do usuário e se especializa conforme recebe tarefas, em vez de pedir o mesmo contexto toda vez.
- **Entrada no sistema**, via módulo `core/hermes` (mesmo molde MVC dos demais módulos, seção 9):
  - **Contexto:** perfil + resumo de áreas/widgets, exposto como recurso MCP.
  - **Ações:** agrega as `acoes` que cada serviço ativo já declara no manifesto (seção 3) — novo serviço entra, a ação já aparece pro Hermes, sem tocar nesse módulo.
  - **Perfil:** lê e atualiza `core.perfil_hermes` (estruturado — `estilo_comunicacao`, `area_prioritaria`, `nivel_proatividade`...) e `core.perfil_hermes_notas` (observações livres: categoria, texto, origem do evento).
  - Quem decide o que aprender e quando agir é o próprio Hermes — o módulo só guarda e expõe; a casca continua sem regra de negócio.
- **Produto vs. uso pessoal:** o que está acima é o Hermes como parte do Tlife, válido pra qualquer usuário. Se o usuário quiser mais potencial, pode usar o Hermes fora da aplicação (Vault do Obsidian, Maestri, n8n — seção 2); aí ele já tem um contexto grande armazenado sobre quem você é, o que faz e o que está fazendo. Isso é uso pessoal do dono do projeto, não requisito do produto.

Decisão completa (opções consideradas, motivo) na Biblioteca de Alexandria — seção 12.

## 8. Design (wireframe aprovado: "a casca está boa")

Wireframe no Claude Design: https://claude.ai/artifact/Tt43QULoJNJmCGRFTxh4ww#page-dcb81aee8d83

Telas:

- **Web:** Painel, Busca global (⌘K), Configurações › Serviços, Perfil.
- **App:** Login, Painel, Inbox, Perfil.
- **Variantes:** claro e inglês do painel web, do login e do painel do app.

Decisões de design:

- **Visual técnico e simples:** escuro por padrão, bordas finas, cantos retos (raio 6–8px), detalhes em fonte monoespaçada (JetBrains Mono, texto em Inter), uma única cor de destaque (azul).
- **Tema:** escuro, claro e sistema. **Idioma:** pt e en. Ficam no Perfil.
- **Login:** sem Google por enquanto. Email e senha. Logo e título centralizados. Na criação da conta, gera um **código de recuperação único** (mostrado uma vez, pra guardar com segurança) — não é passo de login, é a forma de recuperar acesso sem depender de reset por email (como o Tutanota).
- **Painel:** widgets com gráficos dos serviços conectados. Financeiro em linha, Tasks em rosca e barra por área, Academia em barras da semana, Metas em progresso, Conteúdo em mapa de calor. Valores em branco nos wireframes de propósito.
- **Perfil (essencial, não é widget):** dados pessoais, preferências (tema, idioma, início da semana, moeda), segurança (código de recuperação, senha, sessões), áreas de vida, exportar dados e sair.
- **Busca global:** cada serviço declara o que indexa no manifesto. A casca junta os resultados por serviço.

Tokens de cor:

| Token | Escuro | Claro |
|---|---|---|
| bg | `#0B0D10` | `#F5F6F8` |
| superfície | `#12151A` | `#FFFFFF` |
| superfície 2 | `#181C22` | `#F0F2F5` |
| borda | `#262B33` | `#DCE0E5` |
| texto | `#E6E8EB` | `#0E1116` |
| texto suave | `#8E97A3` | `#5B6472` |
| destaque | `#5B9BFF` | `#2563EB` |
| destaque 2 | `#2F5597` | `#93B4F5` |
| destaque (fundo) | `#16243D` | `#E8EFFD` |
| placeholder | `#232830` | `#E3E7EC` |
| tracejado | `#3A414B` | `#B8BFC8` |
| ok | `#3FB950` | `#1A7F37` |
| perigo | `#F47067` | `#C4302B` |

## 9. Plataforma (React Native) — proposta, a confirmar

Só foi dito: React Native, mobile primeiro e web depois. O resto abaixo é recomendação ainda não confirmada.

- **Expo + Expo Router + TypeScript.** O mesmo código roda em Android, iOS e web (React Native Web). A web sai do mesmo repositório, ajustando o layout (menu lateral em tela larga, menu inferior no celular).
- **Registro de serviços:** o `import.meta.glob` do Vite não existe no Metro. Usar `src/services/index.ts` com uma linha por serviço. Ligar e desligar continua em runtime.
- **Rotas dos serviços:** rota dinâmica `app/s/[servico]/[...rota].tsx` que delega para as telas do manifesto.
- **Tema:** `ThemeProvider` com `StyleSheet` e os tokens acima. Claro, escuro e sistema via `useColorScheme`.
- **i18n:** `i18next` + `expo-localization`.
- **Gráficos:** `react-native-svg`.
- **Notificações:** `expo-notifications` (FCM no Android, APNs no iOS). Web Push na fase web.
- **Sessão do Supabase:** `expo-secure-store`.
- **Camadas (MVC por módulo) — decidido:** cada módulo do core e cada serviço tem `model.ts` (tipos Zod + hooks TanStack Query sobre o Supabase), `controller.ts` ou pasta `controller/` com vários hooks (lógica e estado local) e `view/` (telas/componentes, só quando o módulo tem UI própria). De fora, só `controller.ts`/`controller/` e o `manifest.ts` de serviço são importáveis — `model.ts` e os componentes internos de `view/`, não. Caso misto (ex.: `eventos`): o log persistido é Model/TanStack Query, o pub/sub em memória é Controller/Zustand, que grava no log como efeito colateral.
- **Fronteira de módulo — decidido:** travada por regra de ESLint (`no-restricted-imports` ou equivalente), não só por convenção.
- **Estado — decidido:** TanStack Query para estado de servidor (parte do Model); Zustand para estado local/efêmero (parte do Controller).
- **Validação — decidido:** Zod define o schema de cada entidade (linha do Supabase); o mesmo schema gera o tipo TypeScript do Model.
- **Testes — decidido:** Jest + React Native Testing Library para Controller e View; Model mocka o client do Supabase.
- **Código de recuperação — decidido:** gerado na criação da conta, mostrado uma única vez; só o hash fica no Supabase (`core.chave_recuperacao`). Recupera acesso (troca de senha) sem depender de reset por email — não é WebAuthn/passkey nativo, então sem biblioteca nativa, sem development build só por causa disso, sem domínio/relying party.
- **Supabase no desenvolvimento — decidido:** stack local via Supabase CLI (dependência de dev, `npx supabase`) sobre Docker. URL e chave vêm de variável de ambiente (`EXPO_PUBLIC_SUPABASE_URL`); o emulador Android alcança o host em `10.0.2.2`, e o celular físico pelo IP da máquina na rede local.
- **Ambiente:** Fedora Linux. O Android compila local. iOS só via EAS Build (nuvem) ou Mac, e distribuir exige conta Apple Developer. Começar pelo Android.

Estrutura sugerida:

```
app/                 rotas (Expo Router): login, (tabs), s/[servico]
src/core/
  eventos/         model.ts, controller.ts
  inbox/            model.ts, controller.ts, view/
  notificacoes/     model.ts, controller.ts, view/
  busca/            model.ts, controller.ts
  config/           model.ts, controller.ts
  areas/            model.ts, controller.ts
  auth/             model.ts, controller.ts, view/
  tema/             controller.ts
  i18n/             controller.ts
  perfil/           model.ts, controller.ts, view/
  registro/         controller.ts        # registro de serviços
  hermes/           model.ts, controller.ts   # porta de entrada MCP (contexto, ações, perfil)
src/services/
  tasks/            manifest.ts, model.ts, controller/, view/
  financeiro/       ...
supabase/migrations/
```

Decisão completa (opções consideradas, motivo, mapeamento SOLID) na Biblioteca de Alexandria — seção 12.

## 10. Ordem de construção

1. Casca: login, layout, registro de serviços, painel, inbox, módulos do núcleo (com o serviço de exemplo "hello").
2. Notificações e app (despachante).
3. Serviço Tasks.
4. Hermes (conversa e ações).
5. Finance (a partir do FinanSmart), Email e demais serviços.
6. Ponte com o Obsidian, mais adiante.

## 11. Em aberto

- Confirmar Expo e Expo Router.
- Criptografia ponta a ponta dos dados (como o Tutanota de verdade) foi adiada, não descartada — revisitar se/quando migrar do Supabase pra outro backend (detalhe na Biblioteca de Alexandria, seção 12).

## 12. Documentação de decisões

Decisão de arquitetura e o histórico de como se chegou a ela (opções consideradas, motivo, o que ficou de fora) **não ficam neste arquivo** — ficam na Biblioteca de Alexandria, usando a skill `biblioteca-de-alexandria`:

- Pasta do projeto no vault: `Projetos/Ecossistema Harpness/`.
- Visão geral, stack, componentes e pendências: `Ecossistema Harpness - Hub.md`.
- Uma nota por decisão de arquitetura: `Decisoes/`.

Antes de propor uma mudança de arquitetura, consultar o Hub e as notas de `Decisoes/` lá (via skill `biblioteca-de-alexandria`). Depois de decidir com o usuário, registrar a decisão lá primeiro; este `CLAUDE.md` só recebe o resultado já estável — o que vira produto/spec — não o caminho até ele.
