# SINAN Territórios: Recife-PE — versão de demonstração

> ⚠️ **Atenção**
>
> **DADOS FICTÍCIOS.** Esta é uma vitrine do painel, com dados do SINAN e do SIM **inteiramente fictícios**. Nenhum caso, óbito, nome, endereço, data ou coordenada corresponde a uma pessoa real. A versão de produção roda com dados sigilosos de pacientes, em ambiente seguro da Secretaria de Saúde, e não é distribuída aqui. Veja [como os dados fictícios foram gerados](#2-dados-fictícios).

### [▶ Ver o painel ao vivo](https://dev-cenarios.github.io/SINAN_Territorios_Recife_PE_TB/)

O painel roda inteiro no seu navegador, com os dados fictícios, sem instalar nada. A primeira abertura leva de 30 segundos a pouco mais de um minuto, conforme a conexão — o navegador baixa o R e os pacotes —, e as seguintes são mais rápidas. Funciona melhor num computador; em celulares mais simples pode ficar lento ([como é feito](#66-versão-web-github-pages)).

> Veja também o painel irmão, de hanseníase: [SINAN Territórios: Hanseníase – Pernambuco](https://github.com/Dev-Cenarios/SINAN_Territorios_Pernambuco_Hansen) ([painel ao vivo](https://dev-cenarios.github.io/SINAN_Territorios_Pernambuco_Hansen/)).

Painel de vigilância epidemiológica de tuberculose do município de Recife-PE, construído em R/Shiny com o framework [`golem`](https://engineering-shiny.org/). O painel consolida as notificações de TB do SINAN, permitindo que gestores e equipes de vigilância acompanhem o volume de casos, identifiquem áreas de maior incidência/mortalidade por bairro e monitorem desfechos de tratamento (cura, abandono, óbito) em um único lugar, com filtros por período, perfil demográfico, comorbidades e populações especiais.

## Sobre o Projeto

O Programa Cenários, coordenado pelo Prof. Dr. Walter Massa Ramalho da Universidade de Brasília (UnB), é uma iniciativa científica e tecnológica que reúne pesquisadores, gestores de saúde e parceiros nacionais e internacionais para desenvolver soluções inovadoras no enfrentamento de doenças determinadas socialmente. Atualmente, o programa é composto por dois grandes eixos de pesquisa:

### 1. Hanseníase – Modelagem de Cenários de Risco

Cenários Hanseníase tem como objetivo identificar áreas de risco e cadeias invisíveis de transmissão da hanseníase no Brasil, com foco especial nas regiões metropolitanas de Brasília (DF), Recife (PE), Palmas (TO) e demais capitais. A proposta integra inteligência artificial generativa, georreferenciamento por setores censitários e rastreamento de contatos. Os resultados incluem um dashboard nacional, algoritmos de análise espacial e temporal, e relatórios técnicos para subsidiar ações estratégicas do SUS, com foco na redução de desigualdades e modernização da vigilância.

### 2. Tuberculose – Cenários de Risco e Determinantes Sociais

Cenários TB visa apoiar a eliminação da tuberculose como problema de saúde pública no Brasil e em países lusófonos africanos e latino-americanos. A pesquisa combina modelagem epidemiológica, vinculação de bases de dados (linkage) e estratificação de cenários para avaliar a situação dos municípios e orientar ações prioritárias. Entre as entregas previstas estão toolkits com árvores de decisão e IA, dashboards interativos, matrizes de indicadores e metodologias de microplanejamento integradas à atenção primária. Também serão promovidas parcerias com municípios e capacitações para gestores de saúde.

Este painel — o **SINAN Territórios: Recife-PE** — é uma das entregas do eixo Tuberculose, com foco na estratificação territorial (por bairro) dos casos de TB notificados no município de Recife.

[Saiba mais sobre o projeto!](https://cenarios.unb.br/tuberculose-cenarios-de-risco-e-determinantes-sociais/)

### Abordagem Comum

Ambos os projetos compartilham princípios e tecnologias:

* Uso de dados sociais, econômicos e epidemiológicos para subsidiar decisões.
* Georreferenciamento de casos para detalhamento espacial.
* Análise temporal para identificar tendências e rupturas.
* Ferramentas digitais abertas para garantir transparência e replicabilidade.
* Interação com gestores e oficinas de validação para alinhar resultados às necessidades locais.

Essa atuação integrada fortalece o SUS, promove equidade em saúde e posiciona o Brasil na vanguarda da aplicação de ciência de dados e inteligência artificial em saúde pública.

## Sumário

1. [Funcionalidades](#1-funcionalidades)
2. [Dados fictícios](#2-dados-fictícios)
3. [Estrutura do projeto](#3-estrutura-do-projeto)
4. [Fontes de dados](#4-fontes-de-dados)
5. [Tecnologias e pré-requisitos](#5-tecnologias-e-pré-requisitos)
6. [Como rodar](#6-como-rodar)
7. [Desempenho](#7-desempenho)
8. [Troubleshooting](#8-troubleshooting)
9. [Desenvolvedores](#9-desenvolvedores)
10. [Licença](#licença)

## 1. Funcionalidades

- **Cards de indicadores** — total de casos no período, casos em aberto, curados, casos em abandono/falência, óbitos por TB e casos de TB-DR (tuberculose drogarresistente), todos recalculados de acordo com os filtros ativos. ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#1-cards-de-indicadores-topo-do-painel))
- **Mapa de casos** — pontos georreferenciados de cada notificação, com popup de detalhes (datas, demografia, endereço, comorbidades, desfecho) ao clicar, e uma camada opcional de indicador por território — por bairro ou por Distrito Sanitário (os 8 DS da SESAU) — com 5 opções: incidência, mortalidade, letalidade, proporção de cura e proporção de abandono — as duas primeiras calculadas por 100 mil habitantes/ano sobre a população do Censo 2022 do IBGE, agregada por bairro/DS. Camadas adicionais mostram o contorno dos Distritos Sanitários, a rede pública de saúde (UBS/USF, UPA, policlínicas, CAPS, hospitais públicos — marcada com um "S" vermelho), as demais unidades notificadoras (CNES) e as áreas de abrangência oficiais da Atenção Primária (SESAU/ESIG). Ao trocar filtros, indicador, recorte ou camadas, o mapa continua no zoom e na posição em que o usuário estava. ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#2-mapa-de-casos))
- **Tabela de casos** — lista detalhada e pesquisável de todas as notificações filtradas (busca e ordenação por coluna), com acesso à ficha completa de qualquer caso a partir do número de notificação, sem precisar sair do painel. ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#3-tabela-de-casos))
- **Filtros** — período (data de diagnóstico), sexo, idade, raça/cor, tipo de entrada, forma clínica, desfecho e comorbidades, além de populações especiais (situação de rua, privação de liberdade, profissional de saúde, imigrante, beneficiário de transferência de renda). Ficam numa caixa colapsável, aplicados de uma vez ao clicar em "Aplicar filtros". O período vale quando o calendário fecha: trocar início e fim recalcula o painel uma vez só. ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#4-filtros))
- **Aviso de dados fictícios** — exclusivo desta vitrine: selo no cabeçalho, faixa no topo da página, aviso ao abrir o painel, selo no mapa e na ficha de cada caso. Somem sozinhos quando o painel roda com dados reais ([6.5](#65-rodar-com-dados-reais)). Na versão de produção, no lugar do selo do cabeçalho fica o botão administrativo "Atualizar dados", que reprocessa a base a partir do banco de origem.

Para a metodologia completa por trás de cada número exibido (fórmulas, filtros aplicados e referência exata no código), veja a **[Documentação de Gráficos](docs/DOCUMENTACAO_GRAFICOS.md)**.

## 2. Dados fictícios

O painel lê duas bases, as mesmas da produção, mas aqui geradas por simulação:

| Arquivo | Conteúdo | Registros |
|---|---|---|
| [`inst/extdata/dados_ficticios/sinan_tb_recife_ficticio.csv`](inst/extdata/dados_ficticios/sinan_tb_recife_ficticio.csv) | Casos de TB no formato do SINAN (só as colunas que o painel usa), com os campos do SIM que o linkage traz (`NUMERODO_SIM`, `DTOBITO`, `CAUSABAS`) e as colunas `GEORREFERENCIADO` e `INDICADOR` da pipeline de georreferenciamento | 21.912 casos, diagnosticados de 2012 a 2023 |
| [`inst/extdata/dados_ficticios/sim_obitos_orfaos_ficticio.csv`](inst/extdata/dados_ficticios/sim_obitos_orfaos_ficticio.csv) | Óbitos por TB que só aparecem no SIM, sem notificação no SINAN | 224 óbitos |

**Como foram gerados** ([`dev/gerar_dados_ficticios.R`](dev/gerar_dados_ficticios.R), semente fixa): cada caso é sorteado — datas, sexo, idade, raça/cor, comorbidades, populações especiais, tipo de entrada, forma clínica, desfecho, causa básica do óbito e unidade notificadora. O nome é sempre `PACIENTE FICTÍCIO 00001`, `00002`…, o endereço é sempre uma `RUA FICTÍCIA …` (ou `UNIDADE PRISIONAL FICTÍCIA` / `SEM ENDEREÇO FIXO (FICTÍCIO)`), o número de notificação tem 8 dígitos começando por 99 (os do SINAN têm 7, então nunca coincidem com uma notificação real) e a coordenada é um ponto aleatório dentro de um setor censitário do bairro, sorteado pela população do Censo 2022. As associações entre as variáveis são simplificadas (por exemplo, mais abandono entre pessoas em situação de rua ou que usam drogas, mais óbito entre pessoas com AIDS e idosos) e não devem ser lidas como achados epidemiológicos.

**O que vem da realidade**: só ordens de grandeza agregadas, para o painel se comportar como o de produção — nenhum registro da base real foi copiado. São elas:
- o total de casos por ano e as proporções gerais (sexo, faixa etária, raça/cor, forma clínica, desfechos, populações especiais), arredondados;
- a taxa média anual de casos por 100 mil habitantes de cada bairro, com **ruído aleatório de ~15%** e arredondada ([`parametros_bairros.csv`](inst/extdata/dados_ficticios/parametros_bairros.csv)) — define só o peso relativo de cada bairro no sorteio.

**Unidade notificadora**: não usa nenhum dado de notificação real. Sai de uma regra sobre informação pública — 55% dos casos são notificados pela USF da área de abrangência da Atenção Primária onde o ponto do caso cai (territorialização oficial da SESAU) ou, fora de área coberta, pela UBS/USF mais próxima; os demais, por uma unidade sorteada pelo tipo (hospital geral, hospital especializado, policlínica, UPA etc.), com pesos que são hipóteses da simulação. Por isso, o número de casos que cada unidade "notificou" no painel não diz nada sobre a unidade real.

O resultado reproduz a ordem de grandeza dos indicadores de Recife — cerca de 1.300 a 2.400 casos por ano e taxa média de ~100 casos por 100 mil habitantes/ano nos casos com endereço de residência —, mas **os números não devem ser usados para análise ou tomada de decisão**.

O cadastro das unidades de saúde ([`unidades_cnes.rds`](inst/extdata/dados_ficticios/unidades_cnes.rds)) é público: API do CNES/DATASUS e camada da rede de saúde da Prefeitura do Recife (ver [Fontes de dados](#4-fontes-de-dados)). Ele traz só dados cadastrais (nome, tipo, natureza jurídica, coordenada), sem nenhuma contagem de casos.

Os avisos de dados fictícios (selo no cabeçalho, faixa, aviso de abertura, selos no mapa e na ficha do caso) aparecem sempre que a base carregada é a fictícia, e somem sozinhos quando o painel roda com dados reais — ver [6.5](#65-rodar-com-dados-reais).

## 3. Estrutura do projeto

```text
.
├── R/                           # Código-fonte do painel
│   ├── app_ui.R                 # Interface: cabeçalho, faixa e selo de dados fictícios, layout geral
│   ├── app_server.R             # Servidor raiz: confere a base e mostra o aviso de dados fictícios ao abrir
│   ├── app_config.R             # Acesso a arquivos internos do pacote (app_sys) e ao golem-config.yml
│   ├── mod_municipio.R          # Módulo principal: cards, mapa, tabela de casos, filtros
│   ├── fct_casos.R              # Carga dos casos e das malhas, compartilhada entre sessões (ver Desempenho)
│   ├── fct_db_update.R          # Fonte dos dados (fictícios ou reais) e montagem da base local (DuckDB + caches)
│   ├── recife_malha_bairro.R    # Preparação offline da malha de bairros + população (Censo 2022)
│   ├── recife_sample_points.R   # Geração de pontos de amostra para desenvolvimento/teste
│   ├── utils_app_theme.R        # Paleta de cores do painel (tema fresh)
│   ├── golem_utils_server.R     # Utilitários genéricos do framework golem (servidor)
│   ├── golem_utils_ui.R         # Utilitários genéricos do framework golem (UI)
│   └── run_app.R                # Função exportada que inicia o Shiny
├── inst/
│   ├── golem-config.yml         # Configuração golem (nome do app, ambiente)
│   ├── extdata/
│   │   └── dados_ficticios/     # Bases fictícias (SINAN e SIM), parâmetros da simulação e cadastro de unidades
│   └── app/
│       ├── badges_inline.css    # CSS customizado (cores dos cards, navbar, avisos) injetado inline
│       └── www/                 # Assets estáticos: logo, bandeira, favicon
│           └── shapes/          # Malhas geográficas (.gpkg), ver Fontes de dados:
│                                #   bairros_recife.gpkg (94 bairros + população do Censo 2022)
│                                #   distritos_sanitarios_recife.gpkg (8 Distritos Sanitários)
│                                #   abrangencia_aps_recife.gpkg (167 áreas de abrangência da APS)
│                                #   recife.gpkg (limite do município) e setores_recife.gpkg (setores censitários)
├── docs/
│   ├── DOCUMENTACAO_GRAFICOS.md    # O que cada card/indicador/gráfico mostra, por que existe e como é calculado
│   └── PROMPT_TEMPLATE_README.md   # Prompt padrão usado para gerar READMEs no Programa Cenários
├── dev/
│   ├── gerar_dados_ficticios.R      # Gera as bases fictícias desta vitrine
│   ├── build_shinylive.R            # Gera a versão web (Shinylive) publicada no GitHub Pages
│   ├── build_unidades_cnes.R        # (produção) Gera o cache das unidades de saúde (API do CNES + coordenadas oficiais da SESAU)
│   ├── build_distritos_sanitarios.R # Gera a malha dos 8 Distritos Sanitários (bairros do IBGE + divisão da SESAU)
│   ├── build_abrangencia_aps.R      # Gera as áreas de abrangência da APS (camada oficial da SESAU no ESIG)
│   ├── dados_cenarios.R             # (produção) Carga inicial a partir do banco do projeto
│   └── 01_start.R, 02_dev.R, …      # Scripts padrão do golem (setup inicial, deploy)
├── sql/
│   └── db_operations.sql        # Consultas SQL de apoio/manutenção da base local
├── tests/                        # Testes automatizados (testthat)
├── man/                           # Documentação do pacote R (gerada por roxygen2)
├── app.R                          # Ponto de entrada do Shiny (chama run_app())
├── DESCRIPTION                    # Metadados do pacote R (nome, versão, dependências)
└── NAMESPACE                      # Funções/pacotes importados pelo pacote
```

> A pasta `local/` não é versionada: o painel a cria sozinho na primeira abertura, com a base DuckDB (`sinan.duckdb`) montada a partir dos CSVs fictícios (ou dos reais, ver [6.5](#65-rodar-com-dados-reais)), o registro da origem da base (`fonte_dados.rds`), os caches (`casos_cache.rds`, `bairros_cache.rds`, `obitos_sim_orfaos_cache.rds`) e o cadastro das unidades de saúde (`unidades_cnes.rds`).

## 4. Fontes de dados

- **SINAN e SIM — fictícios nesta vitrine** (ver [Dados fictícios](#2-dados-fictícios)). Na produção, os casos de tuberculose notificados no SINAN chegam de um banco PostgreSQL interno, já georreferenciados pela pipeline do projeto (com as colunas `GEORREFERENCIADO` e `INDICADOR`) e vinculados ao SIM pelo linkage do projeto, que corrige o desfecho dos casos (óbito por TB ou por outras causas) e traz os **óbitos por TB sem notificação correspondente** ("órfãos"). O painel reprocessa essas tabelas e salva uma cópia local em **DuckDB** (`local/sinan.duckdb`, tabela `tb_sinan_treated`) — é essa cópia que ele efetivamente lê, nas duas versões. Os órfãos aparecem no mapa e na distribuição de desfechos, mas não entram nos cards nem nos indicadores por território ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#21-pontos-de-casos-marcadores)).
  Campos e categorias seguem o [dicionário de dados do SINAN NET – Tuberculose](http://portalsinan.saude.gov.br/images/documentos/Agravos/Tuberculose/DICI_DADOS_NET_Tuberculose_23_07_2020.pdf); a unidade notificadora vem do campo `ID_UNIDADE` (código CNES), do [dicionário da Notificação Individual](http://portalsinan.saude.gov.br/images/documentos/Agravos/NINDIV/DIC_DADOS_NET_Not_Individual_rev.pdf).
- **IBGE, Censo Demográfico 2022**: população por setor censitário ([agregados por setores censitários](https://ftp.ibge.gov.br/Censos/Censo_Demografico_2022/Agregados_por_Setores_Censitarios/), obtidos via pacote [`geobr`](https://github.com/ipeaGIT/geobr)), agregada por bairro — denominador da incidência e da mortalidade, por bairro e por Distrito Sanitário. São 1.488.920 habitantes somando os 94 bairros.
- **Malha de bairros de Recife** (94 bairros, IBGE 2022): preparada offline (`R/recife_malha_bairro.R`) e distribuída pronta em `inst/app/www/shapes/bairros_recife.gpkg` — não é regerada em tempo de execução. É o contorno que o mapa desenha e a base de todos os recortes territoriais.
- **Distritos Sanitários (SESAU)**: os 8 DS da divisão operacional da Secretaria de Saúde do Recife, publicados no portal de dados abertos da Prefeitura ([distritos sanitários](https://dados.recife.pe.gov.br/dataset/distritos-sanitarios)). Cada DS no painel é a **união dos bairros do IBGE**, para que os limites batam com os do mapa e a população do DS seja a soma dos bairros. Gerada por `dev/build_distritos_sanitarios.R` e versionada em `inst/app/www/shapes/distritos_sanitarios_recife.gpkg`.
- **Áreas de abrangência da Atenção Primária (SESAU/ESIG)**: territorialização oficial da APS, camada ["Cobertura de Atenção Primária à Saúde do Recife por Unidades de Saúde"](https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/Cobertura_de_Aten%C3%A7%C3%A3o_Prim%C3%A1ria_%C3%A0_Sa%C3%BAde_do_Recife_por_Unidades_de_Sa%C3%BAde_do_Recife/FeatureServer/1) do ESIG (servidor de mapas da Prefeitura), versão de ago/2026. São 167 polígonos: 148 áreas de USF, USF+ e EACS, 13 áreas descobertas (com a unidade de referência) e 6 áreas "não se aplica" (sem população residente). Recortada pela união dos bairros do IBGE, porque a camada original inclui ~9,7 km² de água. Gerada por `dev/build_abrangencia_aps.R` e versionada em `inst/app/www/shapes/abrangencia_aps_recife.gpkg`.
- **Unidades de saúde — rede SUS ("S") e outras notificadoras ("✕")**: [API pública do CNES/DATASUS](https://apidadosabertos.saude.gov.br/cnes/estabelecimentos) (coordenada, tipo de unidade, natureza jurídica, atendimento SUS e situação de habilitação). Entram as unidades públicas assistenciais do município — mesmo sem caso notificado — e as demais unidades que notificam casos. "Pública" é definida pela **natureza jurídica** (1xxx, 2011, 2038), não pela esfera administrativa, que no CNES reflete a gestão. Para as unidades da rede municipal, a coordenada é a oficial da SESAU, da camada ["Rede de Saúde de Recife"](https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/Rede_de_Sa%C3%BAde_de_Recife/FeatureServer/0) do ESIG, porque a do CNES erra bastante em Recife. Nesta vitrine o cadastro vem pronto em `inst/extdata/dados_ficticios/unidades_cnes.rds`; na produção é gerado por `dev/build_unidades_cnes.R` ([detalhamento e ajuste de coordenadas](docs/DOCUMENTACAO_GRAFICOS.md#25-unidades-de-saúde-camadas-rede-sus-s-e-outras-notificadoras-)). A quantidade de casos que cada unidade "notificou" no painel é fictícia.
- **Identidade visual**: o painel segue o guia ["Documentação – ID visual para painéis"](https://cenarios.unb.br/documentacao-id-visual-para-paineis/) do Programa Cenários (página protegida por senha), com as exceções acordadas com a equipe de Recife — o navy `#12346B` nas barras estratégicas e as paletas ColorBrewer no mapa de indicadores ([detalhamento](docs/DOCUMENTACAO_GRAFICOS.md#6-identidade-visual)).
- **Dados sensíveis (produção)**: a base real contém dados pessoais de pacientes (nome, endereço, comorbidades). Na produção, a base local e as credenciais de acesso ao banco de origem não são versionadas, e o painel roda atrás de autenticação institucional, em rede interna — com os mesmos cuidados de sigilo da LGPD. Esta vitrine existe justamente para mostrar o painel sem expor esses dados.

## 5. Tecnologias e pré-requisitos

**Linguagem/framework**: R (recomendado 4.4+) / [Shiny](https://shiny.posit.co/), estruturado como pacote com o framework [`golem`](https://thinkr-open.github.io/golem/).

**Principais dependências** (ver lista completa em [`DESCRIPTION`](DESCRIPTION)): `bs4Dash` (interface AdminLTE), `fresh` (tema), `leaflet` + `sf` (mapa e geoprocessamento), `reactable` (tabelas), `duckdb` + `DBI` (base local), `shinyjs`, `shinyWidgets`, `shinytoastr`, `dplyr`, `glue`, `scales`, `lubridate`, `plotly`, `purrr`, `tibble`, `attempt`, `config`, `htmltools`, `stringi`. Os scripts de `dev/` usados só na produção precisam também de `RPostgres`, `httr2` e `curl` (banco de origem, API do CNES e ESIG) e, na carga inicial das malhas, `geobr`.

**Dependências de sistema (Linux)** — necessárias para compilar `sf`/`duckdb`: `libgdal-dev`, `libgeos-dev`, `libproj-dev`, `libudunits2-dev`, `libcurl4-openssl-dev`, `libssl-dev`, `libxml2-dev`. No Windows e no macOS, os binários do CRAN já trazem tudo.

**Pré-requisitos de ambiente**: nenhum banco de dados nem credencial — os dados fictícios vêm no repositório. O navegador de quem usa o painel precisa de internet para as fontes (Google Fonts) e os mapas de fundo (Esri).

## 6. Como rodar

### 6.1 Clonar o repositório

```bash
git clone https://github.com/Dev-Cenarios/SINAN_Territorios_Recife_PE_TB.git
cd SINAN_Territorios_Recife_PE_TB
```

### 6.2 Instalar as dependências

Com o R aberto na pasta do projeto (ou o `.Rproj` aberto no RStudio):

```r
install.packages(c(
  "attempt", "bs4Dash", "config", "DBI", "dplyr", "DT", "duckdb",
  "fresh", "glue", "golem", "htmltools", "htmlwidgets", "leaflet", "lubridate",
  "plotly", "purrr", "reactable", "scales", "sf", "shiny", "shinyjs",
  "shinyWidgets", "tibble", "tidyr", "shinytoastr", "stringi", "pkgload"
))
```

### 6.3 Rodar o painel

Na raiz do projeto:

```r
pkgload::load_all()
run_app()
```

Ou, com o projeto aberto no RStudio, abra o `app.R` e use o botão **"Run App"**.

Na primeira abertura, o painel cria a pasta `local/` e monta a base a partir dos CSVs fictícios — leva alguns segundos e acontece uma vez só.

### 6.4 Regerar os dados fictícios

```bash
Rscript dev/gerar_dados_ficticios.R
```

Regrava os dois CSVs em `inst/extdata/dados_ficticios/` (leva cerca de 2 minutos). Na próxima abertura, o painel percebe que os arquivos mudaram e remonta a base sozinho. Para outra simulação, troque a semente (`set.seed`) ou os parâmetros no topo do script.

### 6.5 Rodar com dados reais

Sem configuração, o painel usa os dados fictícios e mostra os avisos. Para rodar com dados reais, defina a variável de ambiente `PAINEL_DADOS_REAIS_DIR` com o caminho de uma pasta **fora do repositório** — por exemplo, no `.Renviron` do usuário que roda o painel no servidor:

```
PAINEL_DADOS_REAIS_DIR=/caminho/seguro/dados_tb_recife
```

A pasta deve ter:

| Arquivo | Obrigatório | Conteúdo |
|---|---|---|
| `sinan_tb_recife.csv` | sim | Casos de TB, com as mesmas colunas de [`sinan_tb_recife_ficticio.csv`](inst/extdata/dados_ficticios/sinan_tb_recife_ficticio.csv) (colunas a mais são ignoradas) |
| `sim_obitos_orfaos.csv` | não | Óbitos por TB só no SIM, com as colunas de [`sim_obitos_orfaos_ficticio.csv`](inst/extdata/dados_ficticios/sim_obitos_orfaos_ficticio.csv). Sem ele, o painel não mostra esses óbitos |

Formato: UTF-8, com separador `,` e decimal `.` (como os fictícios) ou separador `;` e decimal `,`; datas em `dd/mm/aaaa` e `DTOBITO` como `ddmmaaaa`; códigos do SINAN e do SIM como no dicionário de dados.

O que acontece:
- **Os avisos de dados fictícios somem sozinhos.** Eles não têm uma chave própria: dependem da origem da base que está carregada, registrada em `local/fonte_dados.rds`. Não há como mostrar os dados fictícios sem aviso, nem esquecer o aviso ligado sobre dados reais.
- Na primeira abertura com a variável definida, o painel apaga a base fictícia de `local/` e monta a real. A cada abertura confere a data e o tamanho dos arquivos e remonta a base quando eles mudam — basta substituir os CSVs na pasta.
- Uma atualização com bem menos registros que a anterior (menos da metade) é recusada, e o painel segue com a base que já tinha — a mesma trava da produção contra uma extração incompleta.
- Se a variável apontar para uma pasta sem `sinan_tb_recife.csv`, o painel não abre e registra o erro no log, em vez de cair nos dados fictícios.
- Removida a variável, o painel volta à base fictícia, com os avisos.

> 🛑 **Cuidado**
>
> Dados reais de pacientes são sigilosos (LGPD). Mantenha a pasta e o `.Renviron` fora do repositório e rode o painel só em ambiente protegido. Como proteção extra, o `.gitignore` deste repositório ignora `.Renviron`, `local/`, `dados_reais/`, arquivos `.duckdb` e qualquer `.csv` fora de `inst/extdata/dados_ficticios/`.

O filtro de datas acompanha a base carregada: abre nos 6 meses que terminam na última data de notificação (a mesma "data de atualização" do cabeçalho), e essa data é também o limite do calendário (`periodo_default()` em `R/mod_municipio.R`). Com os dados fictícios, de 01/07/2023 a 31/12/2023.

### 6.6 Versão web (GitHub Pages)

O [painel ao vivo](https://dev-cenarios.github.io/SINAN_Territorios_Recife_PE_TB/) usa o [Shinylive](https://posit-dev.github.io/r-shinylive/): o R, compilado para WebAssembly ([webR](https://docs.r-wasm.org/webr/latest/)), roda no navegador de quem visita, sem servidor. É um site estático no branch `gh-pages` deste repositório, publicado pelo GitHub Pages.

Para regerar o site (por exemplo, depois de mudar o painel ou os dados fictícios):

```bash
Rscript dev/build_shinylive.R
```

O script monta a base fictícia, copia para uma pasta temporária só o código que o painel executa, as malhas e os caches prontos de `local/` (o navegador não refaz a carga dos CSVs) e exporta tudo para `site/` (não versionada no `main`). **Ele só aceita a base fictícia**: para com erro se `PAINEL_DADOS_REAIS_DIR` estiver definido ou se a base local não for a fictícia, porque o site é público. Para ver antes de publicar: `Rscript -e "httpuv::runStaticServer('site', port = 8008)"` e abra `http://localhost:8008`.

Para publicar, substituindo o site anterior:

```bash
cd site
git init -b gh-pages
git add -A
git commit -m "Versao web do painel"
git push --force https://github.com/Dev-Cenarios/SINAN_Territorios_Recife_PE_TB.git gh-pages
```

Na primeira publicação, em **Settings → Pages** do repositório, a fonte é "Deploy from a branch", branch `gh-pages`, pasta `/ (root)`.

## 7. Desempenho

No Shiny Server (versão aberta), cada painel roda num único processo R, compartilhado por todos os usuários. Enquanto o R calcula algo para uma pessoa, as outras esperam, e cada clique no mapa recriava e reenviava o mapa inteiro.

Em setembro de 2026 o painel recebeu as mesmas otimizações feitas no painel irmão de São Paulo, medidas com a base de produção. Aqui ficam o resultado e o que é específico de Recife.

### 7.1 Resultado

Medido em `localhost`. O volume é o que vai pelo WebSocket para o navegador. Em produção, some o tempo de transferência pela rede, que cresce com o volume.

As colunas foram medidas de formas diferentes:
- **Antes:** só o tempo do R, medido com `testServer()`.
- **Depois:** até a última resposta chegar ao navegador, já incluindo a entrega em `localhost`.

| Ação | Antes | Depois |
|---|---|---|
| Trocar o período ou aplicar filtros, 6 meses | 0,6 s · 2,8 MB | 0,9 s · 0,5 MB |
| Trocar o período ou aplicar filtros, 1 ano | 0,7 s · 3,9 MB | 1,0 s · 0,8 MB |
| Trocar o período ou aplicar filtros, 5 anos | 1,4 s · 10,5 MB | 1,5 s · 2,3 MB |
| Trocar o período ou aplicar filtros, período completo | 2,6 s · 20,8 MB | 2,3 s · 4,7 MB |
| Trocar o indicador do mapa, 6 meses | 0,4 s · 2,6 MB | 0,06 s · 0,2 MB |
| Trocar o indicador do mapa, período completo | 1,9 s · 17,3 MB | 0,07 s · 0,2 MB |
| Trocar o recorte (bairro ↔ DS), período completo | 1,7 s · 17,3 MB | 0,03 s · 0,07 MB |
| Desmarcar um desfecho, 6 meses | 0,3 s · 2,6 MB | 0,05 s · 0,06 MB |
| Desmarcar um desfecho, período completo | 1,7 s · 17,3 MB | 0,5 s · 0,9 MB |
| Abrir o painel (app já rodando), até o mapa completo | — | 1,7 s |

Em Recife, o tempo de uma troca de período quase não muda, porque a tabela de casos já tinha as células em JavaScript. O ganho está no volume, de 4 a 6 vezes menor. As trocas no mapa (indicador, recorte, desfecho) ficaram praticamente instantâneas. O mapa também deixou de voltar para o zoom inicial a cada clique.

### 7.2 O que foi feito

As mudanças foram feitas em três etapas:
- **Cálculo no servidor:**
  - Indicadores por território contados por colunas pré-calculadas.
  - Malhas simplificadas só para o desenho.
  - Mapa em canvas.
  - Tabela sem as colunas escondidas.
- **Mapa incremental:** camadas atualizadas por `leafletProxy()` e popup montado no clique.
- **Abertura:** casos e malhas compartilhados entre as sessões, período aplicado quando o calendário fecha e indicador de carregamento.

O que é específico de Recife:
- **Bairro e DS de cada caso** (`atribui_territorio()` em `R/fct_casos.R`). São atribuídos uma vez, na malha completa, e gravados no cache por `update_tb_data()` (colunas `territorio_bairro` e `territorio_ds`). `calcular_indicador_territorio()` conta por essas colunas em vez de refazer `st_intersects()` a cada clique.
  - O resultado é idêntico ao do método anterior nos dois recortes, conferido em 4 períodos × 5 indicadores.
  - Um ponto exatamente na divisa entre dois territórios passa a contar só no primeiro.
- **Malhas do desenho do indicador simplificadas a 5 m** (`malha_bairros_desenho()`, `malha_distritos_desenho()`):
  - Bairros: 19 mil para 5 mil vértices (0,61 MB para 0,17 MB), com área igual.
  - DS: 8,6 mil para 2,2 mil vértices.
- **Camadas do mapa** (`output$main_map`). Cada uma se atualiza só quando o que mostra muda:
  - **Casos e óbitos só-SIM:** filtros, período e desfechos marcados.
  - **Indicador por bairro ou DS:** indicador, recorte, filtros e período.
  - **Unidades (S e ✕):** filtros e período, porque o hover mostra quantos casos cada unidade notificou.
  - **Contorno dos DS e áreas da APS:** desenhados uma vez só.
- **Ordem de desenho no canvas** (`js_ordena_camadas`). É a mesma dos panes de antes: indicador < áreas da APS < contorno dos DS < casos < círculos de hover das unidades.
  - Em Recife, as unidades ficam por cima dos casos, como antes. Em SP é o contrário, porque lá são ~950 unidades.
  - O halo branco dos DS continua embaixo da linha azul.
- **Popups:** cada ponto (caso ou óbito só-SIM) leva um id da camada desenhada, e o popup é montado a partir dele no clique.

Para conferir, o mapa novo foi comparado com o antigo em 10 cenários: 5 indicadores nos dois recortes, APS ligada, desfecho desmarcado, indicador desligado, 5 anos e período completo. Pontos, cores, rótulos, polígonos, legendas, marcadores e popups saíram idênticos.

## 8. Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| Mapa não carrega / erro contendo `dsn must point to a source` | O painel não encontra as malhas em `inst/app/www/shapes/*.gpkg`: foi iniciado fora da raiz do projeto sem o pacote instalado | Rode a partir da raiz do projeto (`pkgload::load_all()` + `run_app()`) ou instale o pacote (`install.packages(".", repos = NULL, type = "source")`) |
| Erro "Montando a base local…" seguido de falha ao abrir | Os CSVs de `inst/extdata/dados_ficticios/` não foram encontrados ou estão incompletos | Confira se a pasta veio no clone (ou regere com `Rscript dev/gerar_dados_ficticios.R`), apague `local/` e abra de novo |
| Dados não mudam depois de trocar os CSVs | A base é conferida a cada abertura de página; uma sessão já aberta continua com a base anterior | Recarregue a página. Se a atualização tiver sido recusada (bem menos registros que antes), o log do R mostra "Atualizacao abortada" — para forçar, apague a pasta `local/` |
| Painel não abre e o log mostra `PAINEL_DADOS_REAIS_DIR esta' definido, mas a pasta nao tem o arquivo sinan_tb_recife.csv` | A variável aponta para uma pasta sem o arquivo de casos | Corrija o caminho ou o nome do arquivo (ver [6.5](#65-rodar-com-dados-reais)), ou remova a variável para voltar aos dados fictícios |
| Alterei uma imagem em `inst/app/www/` e a mudança não aparece | As imagens são servidas via `system.file()`/`app_sys()`, que aponta para a **instalação do pacote** quando ela existe | Reinstale o pacote e reinicie a sessão R. O CSS (`inst/app/badges_inline.css`) é lido da pasta do app sempre que ela existe |

## 9. Desenvolvedores

- **Eduardo Schneider Arruda** — colaborador do Projeto Cenários, Engenheiro de Computação. Trabalha à frente do georreferenciamento usado no painel. Contato: geoprocenarios@gmail.com
- **João Morais** — desenvolvedor do frontend. Contato: geoprocenarios@gmail.com

## Licença

[MIT](LICENSE.md) — © 2026 Projeto Cenários.
