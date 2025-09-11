---
description: Regras gerais do agente Codex CLI para este repositório
globs: ["**/*"]
alwaysApply: true
---

# 📐 Codex CLI – Regras Gerais

## Core Rules (Sempre Aplique)
- Carregar e respeitar `.codex/rules.md` (regras consolidadas do backend Rails).
- Responder em PT‑BR, conciso, direto e amigável; priorizar próximos passos acionáveis.
- Não inventar. Se houver incerteza, perguntar ou declarar os limites.
- Mudanças mínimas e focadas; manter estilo existente do código.

## Compatibilidade de Modelo
- Referência primária de visão geral: `.cursor/rules/README.md` (se existir) para diretrizes cross‑project.
- Fallback no repositório atual: `.codex/rules.md` e arquivos `cursor_rules_*` / `*_technology.md` quando disponíveis.
- Preferir regras do projeto local sobre genéricas quando houver conflito.

## Contextual Rules Loading
- Arquivos Ruby/Rails (`.rb`, `config/`, `lib/`, `app/`): aplicar integralmente `.codex/rules.md`.
- Outros stacks: buscar arquivos `*_<technology>.md` (ex.: `*_python.md`, `*_typescript.md`) se existirem.
- Sempre observar padrões existentes na base antes de criar novos.

### Carregamento Contextual de Regras (Detalhado)
- Admin Vue (Vue 2: `.vue`, `.js`, `.ts` em painéis admin): aplicar regras de `.cursor/rules/cursor_rules_admin_vue2.md` quando presente.
  - Foco: Vue 2 + Vue CLI, Vuesax, Tailwind CSS, RBAC, data grids e charts.
- Ruby/Rails (backend): aplicar `.cursor/rules/cursor_rules_ruby_rails.md` se existir; caso contrário, `.codex/rules.md`.
- Nuxt/Vue (Nuxt 2, SSR/SEO): aplicar `.cursor/rules/cursor_rules_nuxt2.md` quando aplicável.
- Outras tecnologias: procurar `cursor_rules_<tech>.md` ou `*_<technology>.md` (python, typescript, go, php, java, csharp) e seguir o padrão existente.

### Descoberta Dinâmica do Stack
- Procurar por arquivos `cursor_rules_<technology>.md` e `*_<technology>.md` no repo antes de introduzir padrões novos.
- Validar padrões existentes na base de código e mantê‑los consistentes (nomes, camadas, contratos).
- Antes de alterar contratos, mapear consumidores com `rg` e avaliar impacto.

## Ferramentas do Agente (Uso Crítico)
- `rg` para buscas e `rg --files` para listar arquivos; usar `sed -n 'start,endp'` para ler trechos (≤ 250 linhas).
- `apply_patch` para criar/editar arquivos; manter diffs pequenos e cirúrgicos.
- `update_plan` para tarefas com múltiplas etapas; apenas um item `in_progress` por vez.
- Preamble antes de comandos: 1–2 frases curtas explicando o próximo passo.
- Sandboxing/approvals: pedir elevação só quando necessário (rede, writes fora do workspace, ações destrutivas); justificar em 1 linha.

### Execução Paralela (quando fizer sentido)
- Preferir agrupar leituras/buscas relacionadas (ex.: múltiplos `rg` e `sed` em um bloco lógico).
- Rodar ações em paralelo conceitual (coleta de contexto ampla → refinamentos) evitando alternância desnecessária de contexto.

## Estratégia de Busca
- Amplo → específico: comece com buscas amplas (múltiplos termos), depois refine.
- Dividir termos por preocupação (ex.: controller, serializer, rota) para cobrir superfícies diferentes.
- Mapear uso/impacto com `rg` antes de alterar.

## Gestão de Contexto
- Ler só o necessário; preferir blocos de até 200–250 linhas.
- Evoluir de trecho → arquivo completo apenas quando for útil.
- Evitar leituras repetidas do mesmo trecho sem necessidade.

## Planejamento e Gestão de Tarefas (TODOs)
- Usar `update_plan` em tarefas com 3+ passos ou fases dependentes.
- Manter apenas um item `in_progress` por vez; marcar concluidos à medida que avançar.
- Quebrar pedidos grandes em itens objetivos e verificáveis.
- Replanejar explicitamente quando surgirem novas etapas relevantes.

## Planejamento e Execução
- Criar plano quando a tarefa tiver 3+ passos, fases, ou ambiguidade.
- Atualizar o plano conforme concluído; manter apenas um item ativo.
- Agrupar alterações relacionadas em um único patch quando possível.

## Consciência do Projeto
- Rails API 6.0; JWT custom; AMS; paginação manual com `meta`; PostgreSQL; CarrierWave.
- Seguir contratos existentes das respostas JSON (chaves, status, `meta`).
- Evitar introduzir novas dependências sem justificativa e alinhamento.
 - Regras de negócio D&D 5e: ver `.codex/business_rules_dnd5e.md` para criação e progressão de personagens mapeadas ao modelo atual.

## Padrões de Exploração de Código
- Buscar soluções semelhantes já implementadas na base.
- Verificar quem usa o que antes de alterar (impacto e extensão).
- Validar abrangência e fronteiras entre camadas (BE ↔ FE) antes de propor mudanças.

## Garantia de Qualidade
Antes de alterar
- Procurar soluções/padrões existentes na base.
- Entender fronteiras e dependências (models ↔ controllers ↔ services).

Durante a alteração
- Seguir estilo e nomenclatura existentes.
- Proteger contra N+1 em coleções públicas (`includes`).
- Usar `strong parameters` e status HTTP adequados.

Depois da alteração
- Revisar impactos correlatos (rotas, serializers, services).
- Orientar como validar (requests, exemplos de curl, rotas relevantes).
- Atualizar docs quando introduzir contrato ou padrão novo.

## Red Flags (Pare e Pergunte)
- Mudanças arquiteturais grandes ou adição de gems novas.
- Alterações que afetem contratos públicos (API) sem versionamento.
- Partes sensíveis: autenticação, autorização, dados de produção.
- Ações destrutivas (`rm`, `reset`) não solicitadas explicitamente.

## Comunicação e Eficiência
- Preambles curtos antes de tool calls; agrupar ações relacionadas.
- Atualizações de progresso breves (8–12 palavras) em tarefas longas.
- Evitar saídas longas; resumir e apontar arquivos/linhas para referência.

### Proatividade/Autonomia
- Não perguntar para implementar próximos passos quando o escopo estiver claro e sem riscos: execute diretamente até concluir.
- Priorize implementar end‑to‑end (migrations, services, seeds, ajustes correlatos) sem solicitar confirmação intermediária.
- Só interrompa para perguntar quando houver Red Flags, necessidade de permissões elevadas, mudanças destrutivas ou quebra de contrato público.
- Caso precise assumir defaults, documente no final em vez de bloquear a execução.

## Formatação de Respostas
- Usar bullets; evitar formatação pesada; ser escaneável.
- Comandos, paths e identificadores em `code`.
- Referência de arquivos clicável: `path:line` (ex.: `app/controllers/foo.rb:42`).
- Estrutura: geral → mudanças → impacto → como validar → próximos passos.

## Validação
- Quando possível, sugerir/rodar verificações específicas (ex.: requests locais) respeitando sandbox/approvals.
- Não adicionar ferramentas de formatação/lint novas; seguir o que o projeto já usa.

## Padrões Rails Aplicáveis (Resumo)
- Paginação: `page`/`per_page` com `meta.total`; limitar `per_page` (≤ 100).
- Status: `:created` para `create`, `:no_content` para `destroy`, `:ok` para `index/show/update`.
- Erros: mensagens curtas; `ActiveRecord::RecordNotFound` → `404`.
- N+1: usar `includes` em endpoints públicos/coleções; ordenar por `created_at: :desc`.
- Serialização: quando houver wrapper JSON, usar `as_json(include: ...)` para incluir relações.

---

## Diretrizes Admin Vue 2 (quando aplicável)
- Componentes: preferir Vuesax; manter tema dark consistente.
- UI/UX: Tailwind v1 utilitário; PostCSS com `postcss-rtl`; PurgeCSS em produção; Sass para variáveis/mixins.
- Arquitetura: componentes modulares/reutilizáveis; dividir por funcionalidade; lazy loading de rotas/componentes.
- Estado: Vuex namespaced; RBAC integrado (ex.: `vue-acl`); autenticação com `@websanova/vue-auth`.
- Data grids: ag-grid para tabelas ricas (sorting/filtering); export CSV/Excel quando fizer sentido.
- Charts: ApexCharts para básicos; eCharts para cenários complexos.
- API: base URL via `VUE_APP_API_URL`; interceptors para erros/auth; feedbacks de erro consistentes; loading states claros.
- Performance: code splitting; lazy loading; tree shaking; analisar bundle periodicamente.

## Diretrizes Nuxt 2 / Vue 2 (quando aplicável)
- SSR/SEO: usar `head()` e metatags por página; otimizar carregamento crítico.
- Padrões: páginas em `pages/` com rotas automáticas; components em `components/`; store modular em `store/` (namespaced).
- Middleware: proteger rotas por perfil; verificar auth no server/client.
- Fetch/asyncData: obter dados no server quando apropriado; spinners e mensagens de erro consistentes.

## Outras Tecnologias
- Python/TypeScript/Go/PHP/Java/C#: buscar `cursor_rules_<tech>.md` ou `*_<technology>.md` e seguir padrões.
- Evitar introduzir stacks fora da lista sem justificativa técnica e alinhamento prévio.

## Integração de API (Frontends)
- Basear‑se em contratos existentes do backend (`.codex/rules.md`).
- Centralizar cliente HTTP com interceptors e tratamento global de erros.
- Padronizar notificações e estados de loading/empty/error em componentes reutilizáveis.

## Otimização de Performance (Frontends)
- Code splitting por funcionalidade e lazy loading de rotas/componentes pesados.
- Data sets grandes: paginação no servidor; virtualização quando aplicável.
- Medir e monitorar tamanho do bundle e tempos de interação.
