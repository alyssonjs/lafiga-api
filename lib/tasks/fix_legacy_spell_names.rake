# frozen_string_literal: true

# FASE 3 das magias — alinha o NOME da magia na prosa dos legados de Tiefling
# com o nome que o catálogo realmente tem.
#
#   DRY_RUN=1 bundle exec rake dnd:fix_legacy_spell_names
#   bundle exec rake dnd:fix_legacy_spell_names
#
# ⚠️ O problema: a prosa prometia magias por nomes que o catálogo não usa.
#
#   · "Cativar" — o catálogo TEM uma magia chamada Cativar, e é `enthrall`
#     (nível 2). A que o legado concede é `charm-person`, que se chama
#     "Enfeitiçar Pessoa". Um mestre a ler a ficha procuraria a magia errada.
#   · "Vitalidade Falsa" — não existe. A magia é `false-life`, "Vida Falsa".
#
# O `_VARREDURA-racas.md` confirma a intenção ao parear "Cativar / charm-person"
# e "Vitalidade Falsa / false-life": o DADO está certo, a prosa é que usava
# nomes de outro vocabulário.
#
# ⚠️ POR QUE NÃO USAR `dnd:refresh_race_trait_descriptions`, que já existe e faz
# exactamente esta sincronização: medido, ele mexeria em 12 fichas / 15 traits e
# a maioria das mudanças PIORA o texto — troca "18 metros" por "até o alcance
# indicado" na Visão no Escuro, e escreve marcadores por resolver
# ("Resistência a dano de <dano>") no lugar de texto concreto. Corrigir dois
# nomes não justifica degradar doze descrições.
namespace :dnd do
  desc 'FASE 3 — corrige o nome das magias de legado no race_summary das fichas (DRY_RUN=1 relata)'
  task fix_legacy_spell_names: :environment do
    seco = %w[1 true yes].include?(ENV['DRY_RUN'].to_s.strip.downcase)

    # Só nome por nome, sem reescrever a frase — o resto do texto é do mestre.
    trocas = {
      'Vitalidade Falsa' => 'Vida Falsa',
      'Cativar' => 'Enfeitiçar Pessoa'
    }

    # ⚠️ Só dentro dos traços de LEGADO. "Cativar" é palavra comum e podia
    # aparecer noutro traço querendo dizer outra coisa.
    tracos_alvo = %w[abyssal_legacy chthonic_legacy infernal_legacy infernal_legacy_variant]
    nome_de_legado = /Legado/i

    tocadas = 0
    linhas = 0
    Sheet.find_each do |ficha|
      rs = ficha.race_summary
      next unless rs.is_a?(Hash) && rs['traits'].is_a?(Array)

      mudou = false
      novos = rs['traits'].map do |t|
        next t unless t.is_a?(Hash)

        chave = t['key'].to_s
        eh_legado = tracos_alvo.include?(chave) || t['name'].to_s.match?(nome_de_legado)
        next t unless eh_legado

        desc = t['description'].to_s
        nova = desc.dup
        trocas.each { |de, para| nova = nova.gsub(de, para) }
        next t if nova == desc

        mudou = true
        linhas += 1
        puts "  ficha #{ficha.id} · #{t['name']}: #{desc.gsub(/\s+/, ' ')[0, 60]}…" if seco
        t.merge('description' => nova)
      end

      next unless mudou

      tocadas += 1
      ficha.update_column(:race_summary, rs.merge('traits' => novos)) unless seco
    end

    puts "dnd:fix_legacy_spell_names: #{tocadas} ficha(s), #{linhas} traço(s)#{seco ? ' [DRY_RUN]' : ''}."
    puts '⚠️ A tabela `traits` e o `race_rules.yml` já vêm corrigidos — este rake só alcança o que ficou materializado nas fichas.' if tocadas.positive?
  end
end
