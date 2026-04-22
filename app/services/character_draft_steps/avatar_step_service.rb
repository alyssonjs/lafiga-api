module CharacterDraftSteps
  class AvatarStepService < BaseStepService
    # Bug B8 do relatorio de auditoria de steps (paridade creation/edit):
    # mesma justificativa do `AvatarEditService` — agora persistimos
    # `avatarUserEdited` no draft tambem em modo criacao, para que o
    # CharacterProvisioningService nao perca a flag ao virar `Sheet`.
    def step_key = 'avatar'

    def read
      data = CharacterDraftSchema.migrate(character.draft_data || {})
      ac = data['avatarCustomization'] || {}
      {
        'avatarCustomization' => ac,
        'avatarUserEdited' => !!data['avatarUserEdited']
      }
    end

    protected

    def apply!(merged)
      cust = data['avatarCustomization']
      flag = extract_user_edited_flag
      return if cust.nil? && flag.nil?

      base = (merged['avatarCustomization'] || {})
      # Gap G10.1 do relatorio de auditoria de steps: era `merge` raso, entao
      # PATCH com `{ outfitColors: { primary: 'X' } }` apagava `secondary`/
      # `accent` salvos previamente. Deep_merge preserva sub-hashes e so
      # sobrescreve as chaves explicitamente enviadas. Front pode editar
      # incrementalmente sem precisar reenviar o objeto inteiro.
      base = base.deep_merge(cust) if cust.is_a?(Hash)
      merged['avatarCustomization'] = base
      merged['avatarUserEdited'] = flag unless flag.nil?
    end

    private

    # ZX4 do segundo audit (parte 1/3): antes era `data.key?('avatarUserEdited')`,
    # entao um payload com `{ avatarUserEdited: null }` (vinha do
    # stepDefs.fromDraft com `d.avatarUserEdited ?? null`) caia no primeiro
    # branch e devolvia nil — pulando o fallback nested em `_userEdited`. Na
    # pratica chars antigos (com o flag so aninhado, sem flag raiz) perdiam o
    # sinal toda vez que o front ressalvava sem ter setado a flag de novo.
    # Agora exigimos chave PRESENTE E nao-nil para considerar o sinal
    # explicito da raiz; null/ausente cai pro fallback aninhado.
    def extract_user_edited_flag
      raw =
        if data.key?('avatarUserEdited') && !data['avatarUserEdited'].nil?
          data['avatarUserEdited']
        elsif data['avatarCustomization'].is_a?(Hash) && data['avatarCustomization'].key?('_userEdited')
          data['avatarCustomization']['_userEdited']
        elsif data['avatarCustomization'].is_a?(Hash) && data['avatarCustomization'].key?('userEdited')
          data['avatarCustomization']['userEdited']
        end
      return nil if raw.nil?
      ActiveModel::Type::Boolean.new.cast(raw)
    end
  end
end
