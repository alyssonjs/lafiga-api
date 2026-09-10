# frozen_string_literal: true

module Proficiencies
  # Leitura de SALVAGUARDA pelo catálogo.
  #
  # ⚠️ Este NÃO canonicaliza o valor emitido, e de propósito. O summary já
  # emite a chave de atributo (`str`, `dex`…), e é ela que o front usa para
  # montar a linha de teste de resistência — trocar por "Destreza" quebraria a
  # tela. Aqui o catálogo entra por outro motivo: aposentar o QUARTO mapa de
  # tradução do projeto (`abbrev_to_key`, cravado em
  # `character_sheet_summary_service.rb`), que existia só porque a ficha guarda
  # "DES" e `Klass.saving_throws` guarda "Destreza".
  #
  # A chave sai do `metadata['ability']` da própria linha do catálogo.
  class SavingThrowReader < CatalogReader
    CATEGORY = 'saving_throw'

    def self.categories = [CATEGORY]

    # ['DES', 'Carisma', 'STR'] → ['cha', 'dex', 'str'] (ordenado, sem repetir)
    #
    # ⚠️ TOLERANTE como os irmãos: o que o catálogo não conhece é DESCARTADO
    # aqui, e não passa intacto — porque o consumidor espera uma chave de
    # atributo, e devolver "Klingon" produziria uma linha de TR inexistente na
    # ficha. É a única categoria em que descartar é mais seguro que preservar.
    def self.ability_keys(raws)
      Array(raws).filter_map { |raw| lookup(raw.to_s)&.metadata&.dig('ability') }.uniq.sort
    end
  end
end
