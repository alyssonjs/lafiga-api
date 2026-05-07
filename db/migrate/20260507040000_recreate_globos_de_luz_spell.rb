class RecreateGlobosDeLuzSpell < ActiveRecord::Migration[6.0]
  # Restaura "Globos de Luz" como truque INDEPENDENTE de "Luzes Dançantes".
  #
  # Contexto: a migration `20260507030000_canonicalize_drow_spell_names.rb`
  # renomeou `dancing-lights` de "Globos De Luz" para "Luzes Dançantes" (PHB-PT
  # canonico, magia racial do Drow). Mas "Globos de Luz" precisa continuar
  # existindo como cantrip separado (sao dois truques distintos no sistema).
  #
  # Esta migration cria a entrada `globos-de-luz` se ainda nao existir.
  # Idempotente: nao falha se ja existir.
  GLOBOS_ATTRS = {
    api_index: 'globos-de-luz',
    name: 'Globos de Luz',
    level: 0,
    school: 'Evocation',
    range: '36 metros',
    components: %w[V S M].to_yaml,
    material: 'um pouco de fósforo ou wychwood ou um inseto luminoso',
    ritual: false,
    duration: 'Concentração, até 1 minuto',
    concentration: true,
    casting_time: '1 ação',
    desc: ['Você cria até quatro luzes do tamanho de tochas dentro do alcance, fazendo-as parecerem tochas, lanternas ou esferas luminosas que flutuam no ar pela duração. Você também pode combinar as quatro luzes em uma forma luminosa, vagamente humanoide, de tamanho Médio. Qualquer que seja a forma que você escolher, cada luz produz penumbra num raio de 3 metros. Com uma ação bônus, no seu turno, você pode mover as luzes, até 18 metros, para um novo local dentro do alcance. Uma luz deve estar a, pelo menos, 6 metros de outra luz criada por essa magia e uma luz some se exceder o alcance da magia.'].to_yaml,
    higher_level: [].to_yaml
  }.freeze

  def up
    return unless defined?(::Spell)
    return if ::Spell.exists?(api_index: 'globos-de-luz')

    ::Spell.create!(GLOBOS_ATTRS)
  end

  def down
    return unless defined?(::Spell)
    ::Spell.where(api_index: 'globos-de-luz').delete_all
  end
end
