# frozen_string_literal: true

# As REGRAS DA CASA viram artigos da wiki (24/10/2026, o documento de ajuste da
# mesa: criar, editar e remover regras; descrição curta no card e a completa
# num modal).
#
# Até aqui as 23 regras viviam escritas no front (`const RULES` em
# `HouseRules.tsx`) e o lápis só reescrevia o texto (chaves `regra_<id>_titulo`
# e `regra_<id>_descricao` no artigo `info/house-rules`). Criar ou apagar regra
# não tinha onde gravar.
#
# Cada regra é um artigo na seção reservada `regras-da-casa` — a MESMA tabela,
# rota e portão (`authorize_content_editor`: DM, Admin e Editor) das páginas
# institucionais. Nada de tabela nova: seria um segundo caminho de autorização
# (ver `useTextosDoSite.ts`). O `data` de cada regra:
#   title, summary (a descrição curta / o motivo, que o card mostra),
#   description (a completa, no modal; pode faltar), category, importance.
#
# ⚠️ Semeia por MIGRATION, e não pela rake `wiki:semear_artigos`: a rake roda a
# cada deploy e recria o que foi apagado — e apagar regra é justamente o que a
# mesa pediu. A migration roda uma vez por ambiente, e só se a seção estiver
# vazia. O texto que o lápis já reescreveu entra no lugar do de fábrica.
class SemeiaRegrasDaCasa < ActiveRecord::Migration[6.0]
  SECAO = 'regras-da-casa'

  REGRAS = [
    { slug: 'r-01', title: 'Critico Descritivo', category: 'combate', importance: 'alta',
      summary: 'Num acerto critico (nat 20), o jogador descreve o golpe de forma cinematica. Se a descricao for boa, o DM pode conceder 1d6 de dano bonus do tipo da arma. Criticos de monstros tambem recebem descricoes.' },
    { slug: 'r-02', title: 'Iniciativa Rapida', category: 'combate', importance: 'media',
      summary: 'A iniciativa e rolada uma vez no inicio do combate e mantem-se para todos os rounds. Nao ha re-roll de iniciativa entre rounds. Em caso de empate, o jogador com maior modificador de DES age primeiro.' },
    { slug: 'r-03', title: 'Flanqueamento = Vantagem', category: 'combate', importance: 'alta',
      summary: 'Duas criaturas aliadas em lados opostos de um inimigo concedem vantagem nos ataques corpo a corpo contra esse inimigo (regra opcional do DMG que usamos).' },
    { slug: 'r-04', title: 'Poçoes como Accao Bonus', category: 'combate', importance: 'alta',
      summary: 'Beber uma pocao conta como accao bonus (nao accao completa). Administrar uma pocao a outra criatura continua a ser uma accao. Pocoes de cura usadas como accao bonus curam o valor minimo; como accao completa, curam o valor maximo.' },
    { slug: 'r-05', title: 'Dano Massivo', category: 'combate', importance: 'media',
      summary: 'Se uma criatura receber dano igual ou superior a metade dos seus PV maximos num unico golpe, faz TS de CON CD 15. Falha: efeito aleatorio na tabela de Ferimentos Graves (System Reference, p.272).' },
    { slug: 'r-06', title: 'Componentes Materiais Livres', category: 'magia', importance: 'media',
      summary: 'Componentes materiais sem custo listado sao ignorados se o lancador tiver foco arcano ou bolsa de componentes. So e necessario rastrear materiais com custo especifico (ex: diamante de 300 po para Revivify).' },
    { slug: 'r-07', title: 'Identificacao de Magias', category: 'magia', importance: 'media',
      summary: 'Usar a reaccao para identificar uma magia sendo lancada requer teste de Arcana CD 15 + nivel da magia. Magias conhecidas pelo personagem sao identificadas automaticamente. Falha: nao pode tentar novamente para a mesma magia ate descanso.' },
    { slug: 'r-08', title: 'Magia Selvagem Expandida', category: 'magia', importance: 'baixa',
      summary: 'Sorcerers de Magia Selvagem rolam na tabela de Wild Surge sempre que gastam pontos de feiticaria, nao apenas ao lancar magias de 1o nivel ou superior. A tabela foi expandida com 50 entradas extras.' },
    { slug: 'r-09', title: 'Concentracao em Dano', category: 'magia', importance: 'alta',
      summary: 'O TS de CON para manter concentracao ao receber dano tem CD minima de 10 ou metade do dano recebido, o que for maior (regra padrao reforçada). Nao ha excepcoes.' },
    { slug: 'r-10', title: 'Descanso Curto = 10 Minutos', category: 'descanso', importance: 'alta',
      summary: 'Descansos curtos duram 10 minutos em vez de 1 hora (para acelerar o ritmo do jogo). Os beneficios sao os mesmos: gastar Dados de Vida, recuperar features de descanso curto.' },
    { slug: 'r-11', title: 'Descanso Longo em Seguranca', category: 'descanso', importance: 'alta',
      summary: 'Descansos longos so concedem todos os beneficios se feitos em local seguro (estalagem, acampamento protegido). Em masmorras ou territorio hostil, descansos longos recuperam apenas metade dos Dados de Vida e metade dos espacos de magia.' },
    { slug: 'r-12', title: 'Refeicoes Importam', category: 'descanso', importance: 'media',
      summary: 'Se um personagem nao comer durante 24h, ganha 1 nivel de exaustao. Racoes de viagem contam como refeicao. Cozinheiros podem preparar refeicoes que concedem PV temporarios ou resistencias (ver classe Cozinheiro).' },
    { slug: 'r-13', title: 'Death Saves Secretas', category: 'morte', importance: 'alta',
      summary: 'Os testes de morte sao rolados em privado pelo DM. Os outros jogadores nao sabem se o aliado esta a estabilizar ou a morrer — apenas veem que esta inconsciente. Aumenta a tensao dramatica.' },
    { slug: 'r-14', title: 'Ressurreicao Ritual', category: 'morte', importance: 'alta',
      summary: 'Magias de ressurreicao (Revivify, Raise Dead, etc.) requerem um ritual narrativo: 3 jogadores fazem testes de pericias relevantes (Medicina, Religiao, Persuasao). Cada sucesso reduz a CD do TS final da alma. Falha total: a alma nao regressa.' },
    { slug: 'r-15', title: 'Lingering Injuries', category: 'morte', importance: 'media',
      summary: 'Ao cair a 0 PV, o personagem ganha uma ferida permanente (tabela aleatoria). Pode ser curada com Greater Restoration ou tempo narrativo. Exemplos: cicatriz, membro rigido, visao turva.' },
    { slug: 'r-16', title: 'Classe Cozinheiro', category: 'homebrew', importance: 'alta',
      summary: 'Classe homebrew exclusiva de Lafiga (cl-13). Usa INT como atributo de lancamento. Tem 5 subclasses: Mestre de Fogo, Pasteleiro Arcano, Mestre de Sushi, Alquimista Culinario e Cozinheiro de Campo. Nivel maximo: 20.' },
    { slug: 'r-17', title: 'Snacks do Cozinheiro', category: 'homebrew', importance: 'media',
      summary: 'Cozinheiros podem preparar snacks durante descansos curtos. Cada snack tem um efeito unico (cura, buff de atributo, resistencia). O numero de snacks escala com nivel e subclasse.' },
    { slug: 'r-18', title: 'Subclasses Homebrew', category: 'homebrew', importance: 'alta',
      summary: 'Alem das subclasses PHB, Lafiga inclui 52 subclasses homebrew distribuidas por todas as classes. Cada subclasse foi balanceada e aprovada pelo DM. Consulte o Compendio para detalhes completos.' },
    { slug: 'r-19', title: 'Talentos a cada 4 niveis', category: 'homebrew', importance: 'media',
      summary: 'Em Lafiga, jogadores recebem um talento gratuito nos niveis 1, 4, 8, 12, 16, 19 (alem do ASI normal). O talento de nivel 1 deve ser aprovado pelo DM e adequado ao background.' },
    { slug: 'r-20', title: 'Inspiracao Heroica', category: 'geral', importance: 'alta',
      summary: 'Inspiracao pode ser gasta para: (a) vantagem num teste, (b) re-rolar dano, ou (c) conceder vantagem a um aliado a ate 9 m. Inspiracao nao acumula — maximo 1 por jogador. O DM concede inspiracao por roleplay excepcional.' },
    { slug: 'r-21', title: 'Regra da Mesa', category: 'geral', importance: 'baixa',
      summary: 'Se uma accao nao esta coberta pelas regras, o DM pede um teste de atributo + pericia relevante com CD baseada na dificuldade (5 Facil, 10 Medio, 15 Dificil, 20 Muito Dificil, 25 Quase Impossivel, 30 Impossivel).' },
    { slug: 'r-22', title: 'Encumbrance Simplificado', category: 'geral', importance: 'media',
      summary: 'Nao rastreamos peso exacto. Se o inventario tiver mais de 20 itens (excluindo moedas e municao), o personagem sofre desvantagem em testes de DES e Furtividade. Armadura pesada nao conta.' },
    { slug: 'r-23', title: 'Multiclasse com Narrativa', category: 'geral', importance: 'alta',
      summary: 'Multiclasse requer justificacao narrativa aprovada pelo DM. Nao basta ter os atributos minimos — o personagem deve ter exposicao a classe pretendida (treino, evento, patrono). 1 sessao de transicao.' },
  ].freeze

  class Artigo < ActiveRecord::Base
    self.table_name = 'wiki_articles'
  end

  def up
    return if Artigo.where(section: SECAO).exists?

    reescrito = Artigo.find_by(section: 'info', slug: 'house-rules')&.data || {}
    agora = Time.current
    REGRAS.each_with_index do |regra, posicao|
      titulo = reescrito["regra_#{regra[:slug]}_titulo"].presence || regra[:title]
      resumo = reescrito["regra_#{regra[:slug]}_descricao"].presence || regra[:summary]
      Artigo.create!(
        section: SECAO, slug: regra[:slug], position: posicao, created_at: agora, updated_at: agora,
        data: { 'title' => titulo, 'summary' => resumo, 'description' => '',
                'category' => regra[:category], 'importance' => regra[:importance] }
      )
    end
  end

  def down
    Artigo.where(section: SECAO).delete_all
  end
end
