# Cursor Rules – Guia Geral

Este diretório consolida regras para o agente/IDE aplicar conforme o tipo de arquivo. Use estas regras em conjunto com `.codex/rules.md` (backend Rails) e os arquivos específicos de tecnologia abaixo.

## Como Usar
- Arquivos Admin Vue (Vue 2): aplicar `cursor_rules_admin_vue2.md`.
- Arquivos Ruby/Rails: aplicar `cursor_rules_ruby_rails.md` (e consultar `.codex/rules.md`).
- Arquivos Nuxt/Vue (Nuxt 2): aplicar `cursor_rules_nuxt2.md`.
- Outras tecnologias: procurar `cursor_rules_<tech>.md` ou `*_<technology>.md` no repo.

## Compatibilidade e Prioridade
- Preferir regras específicas do projeto/camada (ex.: `.codex/rules.md` para backend) sobre regras genéricas.
- Quando houver conflito, seguir o contrato público existente (API/JSON) e padrões já usados nos arquivos do projeto.

## Padrões Gerais do Agente (sempre aplicar)
- Responder em PT‑BR; conciso, direto, amigável; foque em próximos passos.
- Preambles curtos antes de comandos; agrupe ações relacionadas.
- Buscas: amplo → específico; mapear dependências/impacto com `rg` antes de alterar.
- Ler trechos de até ~200–250 linhas; evitar reaberturas redundantes.
- `apply_patch` para edições; diffs pequenos e cirúrgicos.
- `update_plan` quando houver 3+ passos; manter um `in_progress` por vez.
- Evitar novas dependências/padrões sem justificativa; manter estilo/nomenclatura existentes.
- Red flags: mudanças arquiteturais, contratos públicos, auth/segurança, ações destrutivas.

## Referências
- Backend Rails: ver `.codex/rules.md` (autoridade para contratos e padrões BE).
- Admin Vue 2: ver `cursor_rules_admin_vue2.md`.
- Nuxt 2: ver `cursor_rules_nuxt2.md`.

