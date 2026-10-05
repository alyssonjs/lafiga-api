# frozen_string_literal: true

module Modifiers
  module Producers
    # MembrosProducer — os EFEITOS dos membros substituídos (05/10, a mesa: "a substituição de membros vai poder dar
    # atributos diferenciados ao personagem"). Cada substituto que vale (`Sheets::Membros.substituicoes`: o maior de
    # cada família, de cada lado) traz os efeitos dos itens mágicos que o Mestre escolheu — agregados pelas mesmas
    # regras (`MagicItemRules.agrega_efeitos`) e emitidos como os do `EquippedItemProducer`, com a origem `:membro`.
    #
    # Fora daqui: o ataque e o dano (vão na ARMA natural do membro, no front) e as PENALIDADES do membro perdido (o
    # deslocamento é do summary; o resto, das rolagens do front).
    class MembrosProducer < BaseProducer
      def produce
        membros = Sheets::Membros.da_ficha(sheet)
        return [] if membros.empty?

        Sheets::Membros.substituicoes(membros).flat_map do |chave, substituto|
          efeitos = Array(substituto['efeitos'])
          next [] if efeitos.empty?

          rotulo = Sheets::Membros.rotulo(chave, substituto)
          dos_efeitos(MagicItemRules.agrega_efeitos(efeitos, fonte: rotulo), chave, rotulo)
        end
      rescue => e
        Rails.logger.warn("MembrosProducer: erro ao computar mods para sheet ##{sheet.id}: #{e.class}: #{e.message}")
        []
      end

      protected

      def source_kind
        :membro
      end

      private

      def dos_efeitos(mi, chave, rotulo)
        fonte = "membro:#{chave}"
        out = []
        # a CA e o deslocamento do membro SOMAM (não disputam o "maior mágico" com os itens)
        out << mod(target: 'ac', op: :add, value: mi[:ac_bonus], source: "#{fonte}:ac", note: "#{rotulo}: +#{mi[:ac_bonus]} CA") if mi[:ac_bonus].to_i != 0
        if mi[:speed_bonus].to_i != 0
          out << mod(target: 'speed', op: :add, value: mi[:speed_bonus].to_i, source: "#{fonte}:speed", note: "#{rotulo}: #{format('%+d', mi[:speed_bonus].to_i)} ft")
        end
        (mi[:ability_bonuses] || {}).each do |ab, v|
          next if v.to_i == 0

          out << mod(target: "ability.#{ab}", op: :add, value: v.to_i, source: "#{fonte}:ability_bonus:#{ab}", note: "#{rotulo}: #{format('%+d', v.to_i)} #{ab.upcase}")
        end
        (mi[:ability_sets] || {}).each do |ab, v|
          next if v.to_i <= 0

          out << mod(target: "ability.#{ab}", op: :set, value: v.to_i, source: "#{fonte}:ability_set:#{ab}", note: "#{rotulo}: #{ab.upcase} #{v}")
        end
        {
          resistances: 'resistance', damage_immunities: 'damage_immunity', damage_vulnerabilities: 'damage_vulnerability',
          condition_immunities: 'condition_immunity', save_advantages: 'advantage.save', skill_advantages: 'advantage.skill',
        }.each do |campo, alvo|
          Array(mi[campo]).each do |v|
            out << mod(target: "#{alvo}.#{v}", op: :grant, value: v, source: "#{fonte}:#{alvo}:#{v}", note: rotulo)
          end
        end
        Array(mi[:passive_features]).each do |f|
          out << mod(
            target: 'passive_feature', op: :grant, value: { name: f[:name], desc: f[:desc], source: rotulo },
            source: "#{fonte}:passive:#{f[:name]}", note: f[:name],
          )
        end
        out
      end
    end
  end
end
