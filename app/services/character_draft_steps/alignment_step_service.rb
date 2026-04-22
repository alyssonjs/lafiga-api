module CharacterDraftSteps
  class AlignmentStepService < BaseStepService
    def step_key = 'alignment'

    protected

    def apply!(merged)
      # Bug B9.1 do relatorio de auditoria de steps: este service so aceitava
      # `alignmentId` (id mock do catalogo do front, ex.: 'al-1'). Em modo edit
      # ja aceitavamos `alignmentIndex` (slug canonico, ex.: 'lawful-good') —
      # mas em criacao o front mandava `alignmentIndex` se houvesse e o backend
      # o ignorava silenciosamente, deixando o passo "incompleto" no draft.
      if data.key?('alignmentId') || data.key?('alignmentIndex')
        # `alignmentIndex` (slug) tem precedencia se ambos vierem — e o
        # identificador estavel entre seeds. Mantemos `alignmentId` como
        # fallback para nao quebrar clientes legados que so mandam o id mock.
        ref = data['alignmentIndex'].presence || data['alignmentId']
        merged['_alignId'] = ref
        merged['selectedAlignment'] = ref ? { 'id' => ref } : nil
      end
    end
  end
end
