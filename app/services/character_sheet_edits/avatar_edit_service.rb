module CharacterSheetEdits
  # Bug B8 do relatorio de auditoria de steps: o backend gravava
  # `avatar_customization` com merge raso, mas NUNCA persistia o flag
  # `avatarUserEdited`. Isso forcava o front a re-derivar a flag por heuristica
  # (em editHydration.ts: "se o chibi atual difere do default, presumir
  # editado") — frágil, falha quando o usuario coincidentemente customiza algo
  # que bate com o default. Sem a flag, o `StepAvatar` regenerava o chibi
  # automaticamente em mudancas de classe/raca, sobrescrevendo a customizacao.
  #
  # Solucao: persistir a flag em `sheet.avatar_customization['_userEdited']`
  # (prefixo `_` indica metadado interno do sistema, fora do espaco de keys de
  # customizacao chibi). Aceita-a tanto no nivel raiz do payload quanto
  # aninhada em `avatarCustomization`. O `read` devolve a flag explicitamente.
  class AvatarEditService < BaseSheetEditService
    USER_EDITED_KEY = '_userEdited'

    def step_key = 'avatar'

    def read
      ac = (sheet.avatar_customization || {}).deep_stringify_keys
      {
        'avatarCustomization' => ac,
        'avatarUserEdited' => !!ac[USER_EDITED_KEY]
      }
    end

    protected

    def apply!
      cust = data['avatarCustomization']
      flag_explicit = extract_user_edited_flag

      return if cust.nil? && flag_explicit.nil?

      ac = (sheet.avatar_customization || {}).deep_stringify_keys
      if cust.is_a?(Hash)
        incoming = cust.deep_stringify_keys
        # Se o flag veio aninhado, removemos do payload de customizacao para
        # nao colidir com o flag explicito raiz quando ambos estao presentes.
        incoming.delete(USER_EDITED_KEY)
        # Gap G10.1 do relatorio de auditoria de steps: era `merge` raso.
        # PATCH com `{ outfitColors: { primary: 'X' } }` apagava
        # `secondary`/`accent` salvos. Deep_merge preserva sub-hashes (cor
        # secundaria, acessorios encadeados, etc.). Para zerar uma sub-key
        # explicitamente o caller envia `nil` na chave correspondente.
        ac = ac.deep_merge(incoming)
      end

      ac[USER_EDITED_KEY] = flag_explicit unless flag_explicit.nil?

      sheet.avatar_customization = ac
      sheet.save!
    end

    private

    # ZX4 do segundo audit (parte 1/3): antes era `data.key?('avatarUserEdited')`,
    # entao payload com `{ avatarUserEdited: null }` (vinha do
    # stepDefs.fromDraft com `d.avatarUserEdited ?? null`) caia no primeiro
    # branch e devolvia nil — pulando o fallback nested. Chars antigos (sem
    # flag raiz mas com `avatarCustomization._userEdited` salvo) perdiam o
    # sinal a cada salvamento. Agora exigimos chave presente E nao-nil.
    def extract_user_edited_flag
      raw =
        if data.key?('avatarUserEdited') && !data['avatarUserEdited'].nil?
          data['avatarUserEdited']
        elsif data['avatarCustomization'].is_a?(Hash) && data['avatarCustomization'].key?(USER_EDITED_KEY)
          data['avatarCustomization'][USER_EDITED_KEY]
        elsif data['avatarCustomization'].is_a?(Hash) && data['avatarCustomization'].key?('userEdited')
          data['avatarCustomization']['userEdited']
        end
      return nil if raw.nil?
      ActiveModel::Type::Boolean.new.cast(raw)
    end
  end
end
