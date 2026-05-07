class CanonicalizeDrowSpellNames < ActiveRecord::Migration[6.0]
  # Renomeia as magias raciais do Drow para o nome canonico PHB-PT,
  # alinhando com `config/spells.yml` apos o fix do bug "Magia Drow".
  #
  # Antes:
  #   - dancing-lights → "Globos De Luz"  (errado: D&D 5e PHB-PT usa "Luzes Dançantes")
  #   - faerie-fire    → "Fogo Das Fadas" (capitalizacao errada: "das" eh artigo, lowercase)
  #
  # Depois:
  #   - dancing-lights → "Luzes Dançantes"
  #   - faerie-fire    → "Fogo das Fadas"
  #
  # Idempotente: NAO mexe em magias com nome ja correto.
  RENAMES = {
    'dancing-lights' => { from: 'Globos De Luz', to: 'Luzes Dançantes' },
    'faerie-fire'    => { from: 'Fogo Das Fadas', to: 'Fogo das Fadas' }
  }.freeze

  def up
    if defined?(::Spell)
      RENAMES.each do |api_index, names|
        spell = ::Spell.find_by(api_index: api_index)
        next unless spell
        next if spell.name == names[:to]
        spell.update!(name: names[:to])
      end
    end
  end

  def down
    if defined?(::Spell)
      RENAMES.each do |api_index, names|
        spell = ::Spell.find_by(api_index: api_index)
        next unless spell
        next if spell.name == names[:from]
        spell.update!(name: names[:from])
      end
    end
  end
end
