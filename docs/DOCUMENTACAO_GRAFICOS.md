# Documentação de Gráficos e Indicadores — SINAN Territórios: Recife-PE

> ⚠️ **Atenção**
>
> **Versão de demonstração com DADOS FICTÍCIOS.** A metodologia descrita aqui é a do painel de produção. Nesta vitrine, os casos do SINAN e os óbitos do SIM são gerados por simulação ([README, seção 2](../README.md#2-dados-fictícios)) e passam pelas mesmas transformações e cálculos descritos abaixo.

Este documento explica **por que cada visualização do painel existe, como ela é calculada e onde está implementada no código**. É destinado a epidemiologistas e gestores que precisam entender a metodologia por trás de cada número, sem necessariamente ler R.

Cada item segue o mesmo padrão:

1. **O que mostra** — descrição da visualização.
2. **Por que existe** — justificativa epidemiológica/de gestão.
3. **Como é calculado** — fórmula, filtros e fonte dos dados.
4. **Código** — arquivo e linha de referência, para quem for dar manutenção.

Todo o código-fonte fica em [`R/mod_municipio.R`](../R/mod_municipio.R), salvo indicação contrária.

---

## 1. Cards de indicadores (topo do painel)

Todos os 6 cards usam a mesma base de dados filtrada (`casos_filtered()`, `R/mod_municipio.R:498-527`), que aplica em conjunto: período (data de diagnóstico), sexo, idade, raça/cor, tipo de entrada, forma clínica, desfecho, comorbidades e população especial.

### 1.1 Total de casos no período

- **O que mostra**: contagem total de casos notificados que atendem aos filtros ativos.
- **Por que existe**: é o denominador de referência para leitura proporcional dos demais cards — sem ele, os outros números não têm contexto de escala.
- **Como é calculado**: `nrow(casos_filtered())` — contagem direta, sem filtro adicional de desfecho.
- **Código**: `R/mod_municipio.R:897-911`

### 1.2 Casos em aberto

- **O que mostra**: quantos casos ainda não têm desfecho registrado (`situacao == "Em aberto"`).
- **Por que existe**: acompanha o volume de casos ainda em acompanhamento/tratamento, sem desfecho definido no período filtrado.
- **Como é calculado**: `casos_filtered() |> filter(situacao == "Em aberto")`, contagem.
- **Interação**: clicar no rodapé "Ver todos em aberto" abre a caixa de filtros com o desfecho "Em aberto" pré-selecionado (atalho de drill-down).
- **Código**: `R/mod_municipio.R:915-928` (cálculo), `R/mod_municipio.R:649-654` (drill-down)

### 1.3 Curados

- **O que mostra**: casos com desfecho "Cura".
- **Por que existe**: é o principal indicador de sucesso terapêutico do programa.
- **Como é calculado**: `casos_filtered() |> filter(desfecho == "Cura")`, contagem.
- **Código**: `R/mod_municipio.R:932-944`

### 1.4 Casos em abandono/falência

- **O que mostra**: soma dos desfechos "Abandono", "Abandono primário" e "Falência".
- **Por que existe**: agrupa os principais desfechos de insucesso terapêutico ligados à interrupção do tratamento, indicando necessidade de busca ativa.
- **Como é calculado**: `desfecho %in% c("Abandono", "Falência", "Abandono primário")`, contagem.
- **Código**: `R/mod_municipio.R:948-960`

### 1.5 Óbitos por TB

- **O que mostra**: contagem de óbitos por TB confirmados, somando (a) casos notificados no SINAN com óbito confirmado e (b) óbitos por TB que aparecem só no SIM (sem notificação SINAN correspondente).
- **Por que existe**: monitora mortalidade diretamente atribuída à doença. O SINAN sozinho subnotifica óbitos por TB — casos que morrem podem ficar "em aberto" no sistema (encerramento nunca atualizado) ou nunca chegar a ser notificados. O linkage com o SIM (Sistema de Informação sobre Mortalidade) corrige os dois problemas.
- **Como é calculado**:
  - Para casos notificados: `obito_tb_confirmado` — quando o caso tem um óbito pareado no SIM (via linkage probabilístico feito no pipeline de enriquecimento, pasta `Linkage`), a causa básica do óbito (`CAUSABAS`, CID-10) decide se foi por TB (A15–A19), **mesmo que o SINAN tenha registrado outro desfecho**. Sem par no SIM, usa o desfecho do próprio SINAN (`SITUA_ENCE == 3`) como antes. Desde a correção do linkage (`Linkage/scripts/03_link_sinan_sim.R`), um caso pareado traz a causa de óbito real, **seja ela qual for** — antes dessa correção, o linkage só anexava o SIM quando a causa já era TB, o que tornava estruturalmente impossível detectar um caso em que o SINAN tivesse registrado "Óbito por TB" por engano (a causa real, segundo a declaração de óbito, era outra).
  - **O campo `desfecho` em si é reclassificado pelo SIM** quando os dois divergem (não é só um indicador à parte), usando dois campos: `obito_tb_confirmado` (óbito confirmado por TB) e `obito_confirmado_sim` (qualquer óbito confirmado no SIM, seja qual for a causa — verdadeiro sempre que há par, TB ou não). Se `obito_tb_confirmado` é verdadeiro, `desfecho` vira "Óbito por TB" mesmo que o SINAN tivesse registrado "Cura" ou deixado o caso "Em aberto" (e, nesse caso, `situacao` também vira "Encerrado", e `dt_encerramento` é preenchido com a data do óbito do SIM se o SINAN não tinha uma). Senão, se `obito_confirmado_sim` é verdadeiro (o SIM confirma um óbito de causa não-TB), `desfecho` vira "Óbito por outras causas" — **isso vale pra qualquer desfecho que o SINAN tivesse registrado antes** (inclusive "Óbito por TB" por engano, "Cura", "Abandono" ou "Em aberto"), não só quando o SINAN já dizia "Óbito por TB". Isso garante que popup do mapa, filtro de desfecho, "Tabela de casos" e o card usem a mesma informação — ver `R/fct_db_update.R`, CTE `base` seguida da reclassificação final em `tb_sinan_treated`.
  - Para óbitos só-SIM (sem notificação): contados à parte (`obitos_sim_orfaos_filtrados()`), filtrados pela data do óbito (`dt_obito_sim`) dentro do período selecionado. Não entram como "caso" nos cards de total/curados/abandono/TB-DR nem na "Tabela de casos" — mas **aparecem como pontos no mapa** e na tabela de distribuição de desfechos (seção 2.1 e 2.3), já que essas duas são a legenda/conteúdo do próprio mapa.
  - `DTOBITO` (data do óbito, vinda do SIM) às vezes perde o zero à esquerda no dia (ex.: `2082021` em vez de `02082021`) — o SQL de transformação faz `LPAD` antes do parse, mesmo cuidado já necessário para `DT_DIAG`/`DT_NOTIFIC`.
- **Código**: card `R/mod_municipio.R:1016-1030`; campos `obito_tb_confirmado`/`obito_confirmado_sim`/`dt_obito_sim` e reclassificação de `desfecho`/`situacao`/`dt_encerramento` em `R/fct_db_update.R` (transformação `tb_sinan_treated` e `tb_sim_orfaos_treated`); reactives dos órfãos `R/mod_municipio.R` (`obitos_sim_orfaos`/`obitos_sim_orfaos_filtrados`, logo após `casos_sf`/`casos_filtered`)
- **Fonte dos órfãos**: pipeline de enriquecimento SINAN×SIM — na produção, carregado manualmente numa tabela separada do banco de origem, já que não são "casos" e não devem contaminar a tabela principal do painel. Nesta vitrine, vêm de `inst/extdata/dados_ficticios/sim_obitos_orfaos_ficticio.csv`.
- **⚠️ Assimetria intencional entre pareados e órfãos**: casos notificados pareados entram no linkage com qualquer causa de óbito (ver acima), mas os órfãos continuam restritos a causa = TB (CID A15–A19) — um óbito de outra causa sem nenhuma notificação de TB associada não é subnotificação de TB, é só uma morte sem relação com o programa, e não deve virar "órfão" nem inflar `apenas_sim.csv` com mortes não relacionadas a tuberculose.

### 1.6 Casos de TB-DR

- **O que mostra**: contagem de casos com desfecho "TB-DR" (tuberculose drogarresistente).
- **Por que existe**: TB-DR é um desfecho de manejo clínico mais complexo e prioritário para vigilância, tratado como categoria própria em vez de agrupado com abandono/falência (seção 1.4).
- **Como é calculado**: `casos_filtered() |> filter(desfecho == "TB-DR")`, contagem.
- **Código**: `R/mod_municipio.R:980-992`

---

## 2. Mapa de casos

### 2.1 Pontos de casos (marcadores)

- **O que mostra**: cada caso notificado e georreferenciado, plotado em sua localização aproximada, colorido por desfecho.
- **Por que existe**: permite identificar visualmente concentrações espaciais de casos e seus desfechos, complementando a leitura agregada por bairro.
- **Como é calculado**: usa `casos_filtered()` **mais os óbitos por TB só-SIM** (`orfaos_pontos()`) restrito aos desfechos selecionados na tabela de distribuição (seção 2.3) e apenas casos com `georreferenciado == 1`. Essa classificação vem da pipeline de georreferenciamento (repositório `Sistema-de-georreferenciamento-Projeto-Cenarios-UnB`, função `classificar_georreferenciado()`). Vale 1 quando o endereço do caso casou numa fase de endereço (determinística, ou probabilística acima do limite de similaridade), e 0 quando o caso ficou no centroide do município, não tem coordenada ou tem endereço vazio. Linhas que a pipeline não classificou contam como 0. Sem clusterização — cada ponto é um caso individual. Clique no ponto abre popup com dados completos (datas, sexo, idade, raça/cor, endereço, comorbidades, população especial, forma, situação); passar o mouse mostra um rótulo curto (sexo, idade, raça/cor e desfecho).
- **⚠️ Ponto de atenção — pontos dos órfãos são aproximados**: um óbito só-SIM não tem endereço próprio, então seu ponto é posicionado no **centroide do bairro de residência** (não numa localização real), e a maioria dos campos do popup (sexo, idade, endereço etc.) aparece vazio, já que essa informação não existe fora da declaração de óbito. É uma solução "por enquanto" — o ideal seria georreferenciar esses registros como qualquer outro caso, se um endereço mais preciso estiver disponível no futuro.
- **Código**: filtro/união com órfãos `R/mod_municipio.R` (`casos_points()`, logo após `orfaos_pontos()`/`bairro_centroides()`, que ficam antes de `desfecho_sel`); marcadores, rótulo e legenda no bloco "Casos no mapa" de `output$main_map`. O popup é montado só quando o ponto é clicado (`popup_caso()`), não enviado junto com os pontos (ver README, seção 6).

### 2.2 Indicador por território: bairro ou Distrito Sanitário (camada opcional do mapa)

- **O que mostra**: coloração dos territórios de Recife (choropleth) segundo um de 5 indicadores selecionáveis. A camada é ativada por uma caixa de seleção e tem um menu de escolha do indicador. O **recorte** pode ser **Bairro** (94 bairros) ou **Distrito Sanitário** (os 8 DS da SESAU).
- **Por que existe**: a contagem bruta de casos não é comparável entre bairros de tamanhos populacionais diferentes — indicadores relativizados por população ou por total de casos permitem comparação territorial justa e priorização de áreas de risco. O recorte por DS acompanha a divisão operacional da Secretaria de Saúde, a unidade em que a rede de atenção é organizada e as ações são planejadas.
- **Como é calculado**: cada caso recebe, uma vez, o bairro e o DS onde o seu ponto cai, por interseção espacial (ponto dentro do polígono) na malha completa (`atribui_territorio()` em `R/fct_casos.R`, gravado no cache na atualização de dados). Para cada território, o indicador conta quantos casos filtrados têm aquele bairro ou DS. Quando aplicável, o denominador é a população do Censo 2022 do IBGE, agregada a partir de setores censitários. As fórmulas são as mesmas nos dois recortes (tabela abaixo).
- **Recorte por Distrito Sanitário**:
  - Cada DS é a união dos bairros do IBGE que a SESAU atribui a ele, conforme o shapefile oficial "Distrito_Sanitário 24-09-14" da Prefeitura (recebido da equipe da SESAU em set/2026, não versionado neste repositório; a mesma divisão está publicada no [portal de dados abertos da Prefeitura](https://dados.recife.pe.gov.br/dataset/distritos-sanitarios)). Por isso os limites dos DS coincidem exatamente com os dos bairros no mapa, e a população do DS é a soma da dos seus bairros.
  - O polígono de DS da própria SESAU não foi usado diretamente: seus limites não batem com os bairros do IBGE e incluem cerca de 9 km² de água (Bacia do Pina, faixa da praia).
  - Os casos são contados direto no polígono do DS. Um caso exatamente na divisa entre dois bairros do mesmo DS conta uma vez só. Um ponto exatamente na divisa entre dois territórios (bairros ou DS) fica no primeiro deles. Com os dados de set/2026, isso não muda nenhum número.
  - Os óbitos só-SIM entram somados pelos bairros de cada DS.
  - A malha é gerada por `dev/build_distritos_sanitarios.R`.
- **Casos que entram**: só casos com `georreferenciado = 1` **e** `indicador = 1`, duas colunas que vêm prontas da pipeline de georreferenciamento. Os demais continuam nos cards e na tabela de casos.
  - **`georreferenciado = 0`** (centroide do município, sem coordenada, endereço vazio; ver seção 2.1): o caso não tem localização de residência. Um caso no centroide de Recife seria contado no bairro onde fica o centro da cidade.
  - **`indicador = 0`** (pessoa privada de liberdade ou em situação de rua; função `classificar_indicador()` da pipeline): o endereço desses casos costuma ser o da unidade notificadora, do presídio ou do albergue. Contá-los atribuiria a taxa ao território da unidade, não ao de residência.
  - O `indicador` usa `POP_LIBER`/`POP_RUA` **e** o texto do endereço (presídio, penitenciária, "situação de rua", "morador de rua", albergue). Por isso pega mais casos do que os campos do SINAN sozinhos. Linhas sem classificação da pipeline caem só em `POP_LIBER`/`POP_RUA`.
  - Os cards "Situação de rua" e "Privado de liberdade" continuam usando `POP_RUA`/`POP_LIBER`, já que o `indicador` junta os dois grupos num só valor.

  | Indicador | Fórmula | Observação |
  |---|---|---|
  | **Incidência** (casos/população) | `100.000 × casos / população`, anualizada pelo número de anos do período filtrado | Taxa por 100 mil hab./ano |
  | **Mortalidade** (óbitos por TB/população) | `100.000 × óbitos por TB / população`, anualizada | Taxa por 100 mil hab./ano — inclui óbitos confirmados via SIM (casos pareados) **e** os órfãos só-SIM, somados por bairro |
  | **Letalidade** (óbitos por TB/casos encerrados) | `óbitos por TB / casos com situação "Encerrado" no bairro` | Inclui os órfãos só-SIM **tanto no numerador quanto no denominador** — um óbito confirmado via SIM conta como um caso encerrado por óbito, mesmo sem notificação SINAN (recomendação da equipe técnica do painel) |
  | **Proporção de cura** | `casos com desfecho "Cura" / casos com situação "Encerrado"` | Sobre casos encerrados |
  | **Proporção de abandono** | `casos com desfecho Abandono/Abandono primário/Falência / casos com situação "Encerrado"` | Sobre casos encerrados |

  Os intervalos (bins) da legenda são específicos de cada indicador. **Só a incidência usa quantis** (5 classes); os demais usam faixas fixas de valor.

  As cores do mapa de indicadores são uma **exceção ao guia de identidade visual**, a pedido da equipe: continuam as paletas ColorBrewer usadas antes da adequação ao guia, todas com 70% de opacidade.

  | Indicador | Paleta |
  |---|---|
  | Incidência | `YlOrRd` (amarelo → laranja → vermelho) |
  | Mortalidade | `YlOrRd` |
  | Letalidade | `BuPu` (azul → roxo) |
  | Proporção de cura | `RdYlGn` (vermelho = cura baixa → verde = cura alta) |
  | Proporção de abandono | `Oranges` |

  A legenda usa vírgula decimal e mostra as proporções em %. A última faixa aberta aparece como "≥ x".
- **Código**: seletores de indicador e de recorte no UI de `R/mod_municipio.R` (seção "Indicadores por território"); cálculo dos 5 indicadores em `calcular_indicador_territorio()` (topo de `R/mod_municipio.R`), chamado por `ind_bair()` e `ind_ds()`; soma dos órfãos por bairro (`orfaos_por_bairro()`) no numerador (mortalidade) e em numerador+denominador (letalidade), e por DS via `bairro_cod_ds()`; anualização de incidência/mortalidade `R/mod_municipio.R:1276-1278` e `:1295-1297`; paletas e polígonos `R/mod_municipio.R:1280-1394`; fonte da população por bairro `R/recife_malha_bairro.R`
- **Casamento de bairro dos órfãos**: o nome do bairro de residência do SIM (`BAIRES`, ex.: `"AGUA FRIA"`) é normalizado (maiúsculo, sem acento, via `stringi::stri_trans_general`) e comparado ao `name_neighborhood` do shapefile do painel (ex.: `"Água Fria"`), normalizado da mesma forma. Uma abreviação conhecida do DATASUS é tratada explicitamente (`"I.JOANA BEZERRA"` → `"ILHA JOANA BEZERRA"`, batendo com `"Ilha Joana Bezerra"` do shapefile) — se outras abreviações aparecerem no futuro (bairro cai fora do mapa de mortalidade sem motivo aparente), é aqui que se adiciona um novo caso.

### 2.3 Tabela de distribuição de desfechos (legenda/filtro do mapa)

- **O que mostra**: uma tabela lateral ao mapa com a contagem e proporção de casos por desfecho, cada linha com uma barra horizontal proporcional colorida.
- **Por que existe**: funciona simultaneamente como legenda de cores do mapa e como filtro rápido — o usuário pode selecionar quais desfechos aparecem nos pontos do mapa sem precisar abrir a caixa de filtros completa.
- **Como é calculado**: contagem de `casos_filtered()` **mais os óbitos por TB só-SIM** (`orfaos_pontos()`) agrupada por `desfecho`, com todas as 11 categorias sempre exibidas (mesmo com contagem zero). Todas vêm selecionadas por padrão. Incluir os órfãos aqui é o que faz essa contagem bater com o card "Óbitos por TB" (seção 1.5) — antes de incluí-los, os dois números divergiam.
- **Código**: `R/mod_municipio.R:996-1058`

### 2.4 Título e subtítulo dinâmico do mapa

- **O que mostra**: título com o período filtrado e subtítulo listando, em texto, quais filtros foram alterados em relação ao padrão do painel.
- **Por que existe**: transparência — qualquer pessoa vendo um print ou compartilhamento do mapa sabe exatamente quais filtros estavam ativos, sem precisar reabrir a caixa de filtros.
- **Código**: `R/mod_municipio.R:826-890`

### 2.5 Unidades de saúde (camadas "Rede SUS (S)" e "Outras notificadoras (✕)")

- **O que mostra**:
  - **"Rede SUS (S)"**: um "S" vermelho para cada unidade da rede pública assistencial: UBS/USF, UPA, policlínicas, SPA, UPAE e centros de especialidade, CAPS e hospitais públicos, municipais, estaduais ou federais. Aparecem **mesmo que não tenham notificado nenhum caso**.
  - **"Outras notificadoras (✕)"**: um "✕" para as demais unidades (privadas, filantrópicas, consultórios) que notificaram casos no painel. O código CNES da unidade notificadora vem do campo `ID_UNIDADE` do SINAN.
  - Cada unidade aparece uma vez só, como S ou como ✕. Ao passar o mouse, aparecem o nome da unidade, o tipo, a natureza (pública, privada, filantrópica, e se atende SUS) e quantos casos ela notificou dentro dos filtros/período atuais (pode ser 0).
- **Por que existe**: permite relacionar a distribuição dos casos com a rede de atenção. Isso inclui onde estão as portas de entrada do SUS e quais delas notificam (ou não) casos de TB.
- **Como é calculado**: a lista de unidades vem da [API pública do CNES/DATASUS](https://apidadosabertos.saude.gov.br/cnes/estabelecimentos) (endpoint `/cnes/estabelecimentos`, filtrado pelo município 261160): coordenada, tipo de unidade, natureza jurídica e situação cadastral. Ela fica num cache local (`local/unidades_cnes.rds`), gerado manualmente pelo script `dev/build_unidades_cnes.R`. Entram só unidades habilitadas (sem motivo de desabilitação no CNES).
  - **Pública** = natureza jurídica de administração pública (códigos 1xxx: órgãos, autarquias e fundações públicas) ou empresa pública / sociedade de economia mista (2011/2038, como o Hospital das Clínicas, gerido pela EBSERH).
  - A "esfera administrativa" do CNES **não** é usada, porque reflete a gestão e não a propriedade: consultórios particulares e a Unimed aparecem como "MUNICIPAL".
  - Filantrópicos (IMIP, Santa Casa, Hospital Português) atendem SUS mas não são públicos. Ficam com "✕", com "atende SUS" no hover.
  - Tipos da rede pública que entram mesmo sem notificação: posto de saúde, UBS/USF, policlínica, hospital geral e especializado, unidade mista, pronto-socorro, clínica/centro de especialidade, centro de parto normal, hospital-dia, CAPS e pronto atendimento (UPA). Ambulâncias, farmácias, laboratórios, vigilância, gestão, regulação e academias só aparecem se notificaram algum caso.
- **Coordenada oficial da SESAU**: para as unidades da rede municipal, a coordenada vem da camada ["Rede de Saúde de Recife"](https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/Rede_de_Sa%C3%BAde_de_Recife/FeatureServer/0) do ESIG (servidor de mapas da Prefeitura, mantida pela SESAU), e não do CNES.
  - O CNES erra bastante nessas unidades: numa amostra, a diferença mediana foi de 400 m, e mais de 100 unidades estavam a mais de 1 km do local correto. Por exemplo, a USF Ipiranga estava a 38 km e a USF Mais Bidu Krause, no mar.
  - Pontos "satélite" que compartilham o CNES da unidade principal (residências terapêuticas dos CAPS, Espaços Mãe Coruja, farmácias) são ignorados.
  - As UPAs e os hospitais estaduais e federais não estão na base municipal e usam a coordenada do CNES.
- **⚠️ Ajuste de localização**: parte das coordenadas do CNES cai fora de Recife: no mar, no estuário ou em outro município. Há coordenadas arredondadas que formam uma "grade" de pontos no oceano, e unidades a mais de 100 km. O script compara cada coordenada (já com a da SESAU, quando existe) com a união dos bairros de Recife (o mesmo contorno desenhado no mapa):
  - **dentro de Recife**: usa a coordenada (da SESAU ou do CNES);
  - **até 250 m fora**: puxa o ponto para a borda mais próxima (imprecisão da coordenada ou do polígono, como as USFs na divisa com Jaboatão);
  - **mais longe que isso**: posiciona a unidade no centroide do bairro informado no próprio cadastro do CNES. O hover avisa "Localização aproximada". É a mesma solução "por enquanto" dos óbitos só-SIM (seção 2.1). Se o bairro do cadastro não bate com nenhum bairro do mapa (erro de digitação), a unidade fica fora do mapa.
  
  O script lista no console as unidades aproximadas e as descartadas. A correção definitiva é ajustar a coordenada (ou o bairro) no próprio CNES.
- **Várias unidades no mesmo ponto** (várias no centroide do mesmo bairro, ou várias clínicas cadastradas com a mesma coordenada, como num mesmo prédio) viram um marcador só. O hover lista todas, das que têm mais casos para as que têm menos, e mostra no máximo 8 nomes.
- **Conferência da camada (set/2026)**: o cache tinha 388 unidades — 307 com "S" e 81 com "✕". Nenhuma delas tinha motivo de desabilitação no CNES na data da conferência (de 4.707 estabelecimentos de Recife no CNES, 1.596 estão desabilitados e já não entram), e 241 das 307 aparecem como ativas na camada da SESAU no ESIG. As outras 66 são estaduais/federais (Restauração, HC-UFPE, Agamenon, Otávio de Freitas, Getúlio Vargas, Barão de Lucena, Pelópidas, HEMOPE, PROCAPE, as 5 UPAs), unidades prisionais e socioeducativas e clínicas-escola — que não estão na base municipal por definição.
  - Das 307, **253 são de tipos assistenciais** e **54 entram só por terem notificado algum caso**: ambulâncias e motolâncias do SAMU, polos da Academia da Cidade, laboratórios (LACEN, Aggeu Magalhães, laboratório municipal), vigilância, gestão de DS, telessaúde, regulação e centrais de captação de órgãos. Como esse grupo é um subconjunto de conveniência (a rede municipal tem 43 polos e cerca de 31 ambulâncias/motolâncias, mas só aparecem os que notificaram), está em avaliação movê-lo para a camada "✕".
  - Nenhuma unidade assistencial ativa da rede municipal está faltando no painel. Em compensação, quatro pontos que o ESIG lista como ativos estão desabilitados no CNES e por isso não aparecem — US 105 CS Salomão Kelner, US 332 CEO Dr. Amauri de Barros Cavalcanti, eMulti DS 1 Equipe II e Farmácia da Família – Policlínica do Pina: vale conferir com a SESAU qual cadastro está desatualizado.
- **Código**: classificação e coordenada da SESAU em `dev/build_unidades_cnes.R` (seção 3), ajuste de localização (seção 4); camadas do mapa em `R/mod_municipio.R` (reactive `unidades_cnes()`, função `adicionar_camada_unidades()` e bloco "Unidades de saude (CNES)" dentro de `output$main_map`)

### 2.6 Contorno dos Distritos Sanitários (camada "Distritos Sanitários")

- **O que mostra**: o limite dos 8 Distritos Sanitários (linha azul-escura) com o nome de cada um (DS I a DS VIII).
- **Por que existe**: dá a referência da divisão operacional da SESAU em qualquer leitura do mapa. Por exemplo, permite ver a que DS pertence um bairro com incidência alta no recorte por bairro.
- **Como é calculado**: a mesma malha de DS do recorte por Distrito Sanitário (seção 2.2). A camada liga e desliga no controle de camadas, independente do indicador, e não intercepta o mouse, então o hover do indicador por baixo continua funcionando.
- **Composição dos DS** (SESAU, 2014):

  | DS | Bairros |
  |---|---|
  | I | Boa Vista, Cabanga, Coelhos, Ilha do Leite, Ilha Joana Bezerra, Paissandu, Recife, Santo Amaro, Santo Antônio, São José, Soledade |
  | II | Água Fria, Alto Santa Terezinha, Arruda, Beberibe, Bomba do Hemetério, Cajueiro, Campina do Barreto, Campo Grande, Dois Unidos, Encruzilhada, Fundão, Hipódromo, Linha do Tiro, Peixinhos, Ponto de Parada, Porto da Madeira, Rosarinho, Torreão |
  | III | Aflitos, Alto do Mandu, Apipucos, Casa Amarela, Casa Forte, Derby, Dois Irmãos, Espinheiro, Graças, Jaqueira, Monteiro, Parnamirim, Poço, Santana, Sítio dos Pintos, Tamarineira |
  | IV | Caxangá, Cidade Universitária, Cordeiro, Engenho do Meio, Ilha do Retiro, Iputinga, Madalena, Prado, Torre, Torrões, Várzea, Zumbi |
  | V | Afogados, Areias, Barro, Bongi, Caçote, Coqueiral, Curado, Estância, Jardim São Paulo, Jiquiá, Mangueira, Mustardinha, San Martin, Sancho, Tejipió, Totó |
  | VI | Boa Viagem, Brasília Teimosa, Imbiribeira, Ipsep, Pina |
  | VII | Alto José Bonifácio, Alto José do Pinho, Brejo da Guabiraba, Brejo de Beberibe, Córrego do Jenipapo, Guabiraba, Macaxeira, Mangabeira, Morro da Conceição, Nova Descoberta, Passarinho, Pau Ferro, Vasco da Gama |
  | VIII | Cohab, Ibura, Jordão |
- **Código**: `distritos_shape()` e bloco "Contorno + nome dos Distritos Sanitarios" dentro de `output$main_map` (`R/mod_municipio.R`); malha em `inst/app/www/shapes/distritos_sanitarios_recife.gpkg`

### 2.7 Áreas de abrangência da Atenção Primária (camada "Áreas de abrangência (APS)")

- **O que mostra**: o território de responsabilidade de cada unidade da Atenção Primária. São 148 áreas de USF, USF+ e EACS (estratégia de agentes comunitários de saúde), com contorno roxo e o nome da unidade no hover. Também mostra:
  - as **áreas descobertas**, sem equipe de Saúde da Família, em cinza, com a unidade de referência (em geral um centro de saúde tradicional) no hover;
  - as áreas **"não se aplica"**, sem população residente (mata, campus, área militar), só com contorno tracejado.
- **Por que existe**: a área de abrangência é a base territorial da APS. Com ela dá para ver qual equipe/unidade é responsável pelo território onde os casos se concentram e onde há vazios de cobertura.
- **Como é calculado**:
  - **Fonte**: territorialização oficial da SESAU no ESIG, camada ["Cobertura de Atenção Primária à Saúde do Recife por Unidades de Saúde"](https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/Cobertura_de_Aten%C3%A7%C3%A3o_Prim%C3%A1ria_%C3%A0_Sa%C3%BAde_do_Recife_por_Unidades_de_Sa%C3%BAde_do_Recife/FeatureServer/1) (versão de ago/2026, 167 polígonos depois do recorte).
  - **Tratamento**: recortada pela união dos bairros do IBGE (a camada original inclui cerca de 9,7 km² de água) e simplificada em 2 m.
  - **Atualização**: a camada é gerada por `dev/build_abrangencia_aps.R` e fica versionada em `inst/app/www/shapes/abrangencia_aps_recife.gpkg`. Basta rodar o script de novo quando a SESAU atualizar a territorialização.
- **Interação**: começa **desligada**, para não poluir a leitura do indicador. Ligada, fica por cima do indicador e o hover passa a ser o da área de abrangência.
- **Código**: `abrangencia_shape()` e bloco "Areas de abrangencia da APS" dentro de `output$main_map` (`R/mod_municipio.R`)

---

## 3. Tabela de casos

- **O que mostra**: lista detalhada de todas as notificações que atendem aos filtros ativos (independente da seleção de desfechos do mapa), com colunas de número de notificação, datas (diagnóstico, notificação, início de tratamento, encerramento), idade, sexo, raça/cor, forma clínica, desfecho (como selo colorido) e tempo em dias até o encerramento.
- **Por que existe**: permite auditoria caso a caso, busca e ordenação — necessário para investigação epidemiológica individualizada, complementando a visão agregada dos cards e do mapa.
- **Como é calculado**: exibição direta de `casos_filtered()`, sem agregação. Colunas de bairro, comorbidades, população especial, tipo de entrada e georreferenciamento existem nos dados mas ficam ocultas por padrão (disponíveis via ficha do caso).
- **Interação — Ficha completa do caso**: clicar no número de notificação abre um modal com todos os dados do caso (datas, demografia, comorbidades, população especial, endereço, desfecho, tempo até encerramento e status de georreferenciamento). A busca do caso usa a base completa (não filtrada), então a ficha pode ser aberta mesmo que o caso não esteja mais visível após uma mudança de filtro.
- **Desempenho**: as células de *Núm. Notificação*, *Desfecho* e *Georreferenciado* são montadas no navegador (`reactable::JS`), não no R. Montar uma tag HTML por linha no R custava ~58 s de servidor e 21 MB de payload no período completo (~26 mil casos); em JS, a mesma tabela leva ~0,8 s e 3,7 MB (no período padrão, 0,09 s contra 2,8 s). A aparência, o filtro por coluna e o clique que abre a ficha continuam iguais — o que muda é onde o HTML é gerado. Só as colunas exibidas vão para o navegador; as escondidas (tipo de entrada, comorbidades, população especial, bairro) deixaram de ser enviadas.
- **Código**: tabela `R/mod_municipio.R:1483-1667`; modal de ficha `R/mod_municipio.R:1064-1201`

---

## 4. Filtros

| Filtro | O que faz | Aplicado sobre |
|---|---|---|
| Período | Intervalo de datas (padrão: os 6 meses que terminam na última data de notificação da base — com os dados fictícios, 01/07/2023 a 31/12/2023; `periodo_default()`) | `dt_diagnostico` |
| Sexo | Feminino / Masculino / Ignorado | `sexo` |
| Idade | Faixa etária (0 a 120 anos) | `idade` |
| Raça/cor | Branca, Preta, Amarela, Parda, Indígena, Ignorado | `raca_cor` |
| Tipo de entrada | Caso novo, recidiva, reingresso, transferência, pós-óbito, não sabe | `tipo_entrada` |
| Forma clínica | Pulmonar, extrapulmonar, pulmonar + extrapulmonar | `forma` |
| Desfecho | As 11 categorias de desfecho | `desfecho` |
| Comorbidades | AIDS, alcoolismo, diabetes, doença mental, uso de drogas ilícitas, tabagismo (seleção única) | `comorbidades` |
| População especial | Privação de liberdade, situação de rua, profissional de saúde, imigrante, beneficiário de transferência de renda (seleção única) | `populacao_especial` |

Os filtros (exceto período, sempre visível) ficam numa caixa colapsável, aberta pelo botão "Abrir filtros". As mudanças só são aplicadas ao clicar em **"Aplicar filtros"** — os widgets não recalculam o painel a cada clique individual, evitando recomputações desnecessárias do mapa e da tabela a cada seleção. O botão **"Limpar filtros"** restaura todos os valores padrão.

**Código**: definição dos filtros `R/mod_municipio.R:121-267`; aplicação (`casos_filtered()`) `R/mod_municipio.R:498-527`; lógica de aplicar/limpar `R/mod_municipio.R:608-647`

---

## 5. Outras informações do painel

### 5.1 Status de atualização dos dados

- **O que mostra**: no cabeçalho do painel, a data da notificação mais recente disponível na base e o percentual de casos georreferenciados (`georreferenciado = 1`, ver seção 2.1; sobre o total da base, sem filtros).
- **Por que existe**: transparência sobre a atualidade dos dados e sobre a cobertura espacial (nem todo caso tem endereço geocodificável).
- **Código**: `R/mod_municipio.R:806-824`

### 5.2 Botão "Atualizar dados" (só na produção)

- **O que mostra**: na produção, botão administrativo no cabeçalho (ícone de sincronizar) que reprocessa a base a partir do PostgreSQL de origem. **Nesta vitrine ele não existe**: a base é montada automaticamente a partir dos CSVs fictícios (ou dos reais, com a variável `PAINEL_DADOS_REAIS_DIR` — [README, 6.5](../README.md#65-rodar-com-dados-reais)) e remontada sempre que os arquivos mudam (`prepara_base()` em `R/fct_db_update.R`). Com os dados fictícios, o lugar do botão no cabeçalho fica com o selo "DADOS FICTÍCIOS".
- **Por que existe**: permite à equipe atualizar o painel com os dados mais recentes do SINAN sem precisar reimplantar a aplicação.
- **Como funciona (produção)**: exige senha de administrador própria do painel; bloqueia execuções simultâneas; e tem uma trava de segurança que recusa sobrescrever a base local se o banco de origem retornar zero registros ou menos da metade dos registros já existentes — proteção contra sobrescrever dados bons com uma resposta vazia ou incompleta. A trava continua no `update_tb_data()` desta vitrine.
- **Código**: montagem e reprocessamento dos dados `R/fct_db_update.R`

### 5.3 Fonte da população por bairro

A população usada como denominador de incidência e mortalidade vem do **Censo Demográfico 2022 do IBGE** ([agregados por setores censitários](https://ftp.ibge.gov.br/Censos/Censo_Demografico_2022/Agregados_por_Setores_Censitarios/)), obtida por setor censitário via pacote [`geobr`](https://github.com/ipeaGIT/geobr) e agregada por bairro — 1.488.920 habitantes somando os 94 bairros. Esse processamento é feito uma vez, offline (script `R/recife_malha_bairro.R`), e o resultado fica salvo na malha geográfica (`bairros_recife.gpkg`) usada em tempo de execução — não é recalculado a cada carregamento do painel. A população de cada Distrito Sanitário é a soma dos seus bairros (seção 2.2).

---

## 6. Identidade visual

O painel segue o guia **["Documentação – ID visual para painéis"](https://cenarios.unb.br/documentacao-id-visual-para-paineis/)** do Programa Cenários (página protegida por senha).

- **Tipografia**:
  - Poppins 700 nos títulos, em azul títulos `#00638C`: 32 px no título do painel, 20–24 px nos títulos de seção.
  - DM Sans no corpo, rótulos e tabelas (400, 15 px) e nos números dos cards (700, 34 px, `#12222B`).
  - Algarismos tabulares (`tabular-nums`) em cards, tabelas, legendas e tooltips.
  - As fontes vêm do Google Fonts.
- **Exceção pedida pela equipe de Recife**: o navy `#12346B`, cor tema de Recife, continua nas barras estratégicas. São elas o cabeçalho, as barras de título das caixas "Mapa de casos" e "Tabela de casos", a borda da caixa de Filtros e o contorno dos Distritos Sanitários. As cores do mapa de indicadores também são exceção (seção 2.2). Tudo o mais segue o guia.
- **Interface**:
  - Títulos em azul títulos `#00638C`; botões em azul ação `#0E7BA8` (secundários com contorno azul ação); fundo `#F2F6F9`.
  - Controles (filtro de sexo, slider de idade, calendário, listas, caixas e botões de opção, paginação das tabelas) em azul ação no estado ativo/selecionado.
  - Estado "georreferenciado" na tabela com o símbolo do guia (✓ em adequado `#1F6F4A`).
  - Cards em superfície branca com barra lateral na cor do indicador, usando as cores de estado do guia onde há sentido: curados = adequado, óbitos = crítico, abandono = grave.
  - O logo Cenários+ fica sobre uma etiqueta branca no cabeçalho, porque o PNG é feito para fundo claro.
- **Cores dos 11 desfechos** (pontos do mapa, tabela de distribuição, tabela de casos e ficha):

  | Desfecho | Cor |
  |---|---|
  | Cura | adequado `#1F6F4A` |
  | Óbito por TB | crítico `#A32235` |
  | Abandono | grave `#C24B12` |
  | Abandono primário | atenção `#8A6100` |
  | Em aberto | série 1, azul |
  | Falência | série 2, terracota |
  | TB-DR | série 3, roxo |
  | Óbito por outras causas | série 5, vinho |
  | Transferência | série 8, ciano |
  | Mudança de esquema | série 7, índigo |
  | Mudança de diagnóstico | cinza `#7A8B95` |

  Cura, óbito por TB, abandono e abandono primário usam as cores de estado do guia; os demais usam as séries. Todos os 11 são distintos.
- **Mapa**:
  - **Exceção**: as cores do mapa de indicadores continuam as paletas ColorBrewer de antes do guia, a pedido da equipe (seção 2.2).
  - Pontos de caso com contorno branco fino, para aparecerem sobre qualquer cor do indicador.
  - Contorno e nomes dos DS em navy de Recife `#12346B`, com a linha sobre um halo branco.
  - Áreas de abrangência em roxo (série 3).
  - "S" da rede SUS em crítico `#A32235`: é o único vermelho do guia.
- **Código**: tokens de cor em `cores_cen` e `cores_desfecho` (topo de `R/mod_municipio.R`) e em variáveis `--cen-*` (`inst/app/badges_inline.css`); tema bs4Dash em `R/utils_app_theme.R`; fontes em `R/app_ui.R`.
- **Cabeçalho próprio**: o guia diz que, quando o painel está embutido no site (WordPress), a faixa azul e o cabeçalho vêm do template do site e o painel não deve criar a sua. O painel de Recife mantém cabeçalho próprio, em navy (exceção acima).

---

## 7. Fontes de dados e referências oficiais

Tudo o que o painel desenha vem de uma destas fontes. As malhas `.gpkg` são versionadas no repositório; o que fica em `local/` é gerado em cada ambiente e não é versionado.

| O que | Fonte oficial | Onde fica | Como atualizar |
|---|---|---|---|
| Casos de tuberculose | **Vitrine: fictícios** (`inst/extdata/dados_ficticios/sinan_tb_recife_ficticio.csv`, gerado por `dev/gerar_dados_ficticios.R`). Produção: SINAN, via pipeline de georreferenciamento do projeto, num PostgreSQL interno. Campos e categorias no [dicionário do SINAN NET – Tuberculose](http://portalsinan.saude.gov.br/images/documentos/Agravos/Tuberculose/DICI_DADOS_NET_Tuberculose_23_07_2020.pdf); unidade notificadora (`ID_UNIDADE`) no [dicionário da Notificação Individual](http://portalsinan.saude.gov.br/images/documentos/Agravos/NINDIV/DIC_DADOS_NET_Not_Individual_rev.pdf) | `local/sinan.duckdb` (`tb_sinan_treated`) e `local/casos_cache.rds` | Vitrine: trocar os CSVs e reabrir a página. Produção: botão "Atualizar dados" (seção 5.2) |
| Óbitos por TB sem notificação (só-SIM) | **Vitrine: fictícios** (`inst/extdata/dados_ficticios/sim_obitos_orfaos_ficticio.csv`). Produção: SIM, pelo linkage do projeto | `local/obitos_sim_orfaos_cache.rds` | Idem |
| População por bairro e por DS | IBGE, Censo Demográfico 2022 — [agregados por setores censitários](https://ftp.ibge.gov.br/Censos/Censo_Demografico_2022/Agregados_por_Setores_Censitarios/), obtidos via [`geobr`](https://github.com/ipeaGIT/geobr) | `inst/app/www/shapes/bairros_recife.gpkg` | `R/recife_malha_bairro.R` (offline) |
| Malha de bairros (94) | IBGE 2022, via [`geobr`](https://github.com/ipeaGIT/geobr) | `inst/app/www/shapes/bairros_recife.gpkg` | `R/recife_malha_bairro.R` |
| Distritos Sanitários (8) | SESAU/Prefeitura do Recife — shapefile "Distrito_Sanitário 24-09-14" (recebido em set/2026, não versionado); divisão também publicada em [dados abertos](https://dados.recife.pe.gov.br/dataset/distritos-sanitarios) | `inst/app/www/shapes/distritos_sanitarios_recife.gpkg` | `dev/build_distritos_sanitarios.R` |
| Áreas de abrangência da APS (167) | SESAU no ESIG — [Cobertura de Atenção Primária à Saúde do Recife por Unidades de Saúde](https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/Cobertura_de_Aten%C3%A7%C3%A3o_Prim%C3%A1ria_%C3%A0_Sa%C3%BAde_do_Recife_por_Unidades_de_Sa%C3%BAde_do_Recife/FeatureServer/1) (ago/2026) | `inst/app/www/shapes/abrangencia_aps_recife.gpkg` | `dev/build_abrangencia_aps.R` |
| Unidades de saúde ("S" e "✕") | [API pública do CNES/DATASUS](https://apidadosabertos.saude.gov.br/cnes/estabelecimentos) + coordenadas oficiais da camada [Rede de Saúde de Recife](https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/Rede_de_Sa%C3%BAde_de_Recife/FeatureServer/0) (SESAU/ESIG) | `local/unidades_cnes.rds` (na vitrine, copiado de `inst/extdata/dados_ficticios/unidades_cnes.rds`) | `dev/build_unidades_cnes.R` |
| Identidade visual | [Documentação – ID visual para painéis](https://cenarios.unb.br/documentacao-id-visual-para-paineis/), Programa Cenários (protegida por senha) | `inst/app/badges_inline.css`, `R/utils_app_theme.R`, `cores_cen`/`cores_desfecho` | Seção 6 |
| Mapas de fundo e fontes | Esri (`WorldGrayCanvas` e `WorldImagery`, via provedores do leaflet) e [Google Fonts](https://fonts.google.com/) (Poppins, DM Sans) | Carregados pelo navegador | — |

> O ESIG usa um certificado TLS que não valida a cadeia completa; os scripts de `dev/` baixam essas camadas com `ssl_verifypeer = FALSE`. São camadas públicas e de leitura.

---

## Observações gerais para manutenção futura
- Os pontos de atenção sinalizados acima (rótulos que descrevem uma fórmula diferente da implementada) não indicam necessariamente um erro — podem refletir uma decisão metodológica não documentada. Recomenda-se validar com a equipe responsável pela definição dos indicadores antes de qualquer ajuste.
