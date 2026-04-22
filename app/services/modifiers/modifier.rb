# frozen_string_literal: true

module Modifiers
  # Modifier — PORO que representa UMA contribuição atômica de um source
  # para um target da ficha. É o contrato que todos os producers devolvem
  # e que o ModifierResolver agrega.
  #
  # Filosofia:
  # - Producers NÃO sabem como o resultado será aplicado: só descrevem o
  #   "o quê" e o "por quê".
  # - O Resolver decide ordem, pilha (typed stacking) e desempate.
  # - O CharacterSheetSummaryService consome o resultado agregado.
  #
  # Targets canônicos (use sempre strings):
  #   "ability.<key>"            ex: "ability.str"
  #   "save.<key>"               ex: "save.con"  (proficiência ou bônus em save)
  #   "skill.<slug>"             ex: "skill.percepcao"
  #   "ac"                       (CA total — somado por tipo)
  #   "ac.armor_category"        (override de categoria, valor = 'light'|'medium'|'heavy'|'none')
  #   "speed"                    (deslocamento em ft)
  #   "hp.max_per_level"         (PV adicionais por nível, ex: Robusto)
  #   "hp.max_flat"              (PV adicionais fixos, ex: Tough at level X)
  #   "weapon.attack"            (bônus de ataque global; +slot? via predicate)
  #   "weapon.damage"            (bônus de dano global)
  #   "spell.attack"             (bônus de ataque de magia)
  #   "spell.dc"                 (DC de magia)
  #   "initiative"
  #   "passive.percepcao"
  #
  # Operações suportadas:
  #   :add     — soma o valor (numerico)
  #   :set     — define o valor (override; usar com cuidado)
  #   :grant   — concede algo (proficiencia/expertise; valor é o "que" granted)
  #   :advantage / :disadvantage — vantagem/desvantagem condicional
  #   :resistance / :immunity   — resistência/imunidade a tipo
  #
  # Stacking_type:
  #   "untyped"  — somam livremente (default)
  #   "magico"   — só pega o maior (5e: bônus mágicos não pilam)
  #   "escudo"   — só pega o maior (escudo mágico)
  #   "armor"    — só pega o maior (armadura mágica)
  #   "circunstancia" — apenas um por turno/cenário
  Modifier = Struct.new(
    :target,        # String — ver lista acima
    :op,            # Symbol — :add | :set | :grant | :advantage | :disadvantage | :resistance | :immunity
    :value,         # Object — Integer, String, Hash, etc., dependendo de op
    :source,        # String — id legível do produtor (ex: "feat:resiliente", "item:39")
    :source_kind,   # Symbol — :race | :klass | :subklass | :background | :feat | :item | :condition | :spell | :asi
    :stacking_type, # String — vide acima (default "untyped")
    :priority,      # Integer — quanto maior, aplica depois (resolve conflitos de :set)
    :predicate,     # Hash, opcional — condições para o mod ativar (ex: { "weapon.category" => "ranged" })
    :note,          # String, opcional — texto humano para tooltips/breakdown
    keyword_init: true,
  ) do
    def initialize(*args, **kwargs)
      super(*args, **kwargs)
      self.stacking_type ||= 'untyped'
      self.priority ||= 100
      self.predicate ||= {}
      validate!
    end

    def to_h_compact
      {
        target: target,
        op: op,
        value: value,
        source: source,
        source_kind: source_kind,
        stacking_type: stacking_type,
        priority: priority,
        predicate: (predicate.presence),
        note: note,
      }.compact
    end

    private

    def validate!
      raise ArgumentError, "Modifier#target é obrigatório" if target.to_s.strip.empty?
      raise ArgumentError, "Modifier#op é obrigatório" unless op.is_a?(Symbol)
      raise ArgumentError, "Modifier#source é obrigatório" if source.to_s.strip.empty?
      raise ArgumentError, "Modifier#source_kind é obrigatório" unless source_kind.is_a?(Symbol)
    end
  end
end
