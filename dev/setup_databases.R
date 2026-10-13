# Setup script para criar os bancos DuckDB necessários
# Execute este script uma única vez para inicializar os bancos

library(tidyverse)
library(duckdb)
library(geobr)
library(sf)

# Cria pasta local se não existir
if (!dir.exists("local")) {
  dir.create("local")
}

# ============================================================================
# 1. Criar banco sinan.duckdb com dados de casos tuberculose Recife
# ============================================================================

cat("Criando banco sinan.duckdb...\n")

# Caminho do arquivo CSV SINAN
sinan_path <- "<caminho/para/o/csv_de_casos_do_sinan.csv>"

if (!file.exists(sinan_path)) {
  stop(paste("Arquivo não encontrado:", sinan_path))
}

# Conecta ao DuckDB
con_sinan <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb")

# Remove tabelas se existirem
tryCatch(DBI::dbExecute(con_sinan, "DROP TABLE IF EXISTS tb_sinan"), error = function(e) NULL)
tryCatch(DBI::dbExecute(con_sinan, "DROP TABLE IF EXISTS tb_sinan_treated"), error = function(e) NULL)

# Cria tabela bruta tb_sinan lendo o CSV
cat("  Lendo dados SINAN...\n")
sinan_sql <- sprintf("
  CREATE TABLE tb_sinan AS
  SELECT * FROM read_csv('%s', nullstr = 'NA', decimal_separator = ',')
", sinan_path)

DBI::dbExecute(con_sinan, sinan_sql)

# Cria tabela tratada tb_sinan_treated com transformações
cat("  Transformando dados SINAN...\n")
DBI::dbExecute(con_sinan, "
  CREATE TABLE tb_sinan_treated AS
  SELECT
    NU_NOTIFIC as numero_notificacao,
    DT_DIAG as dt_diagnostico,
    DT_NOTIFIC as dt_notificacao,
    try_cast(try_strptime(DT_INIC_TR, '%d/%m/%Y') as date) as dt_inicio_tratamento,
    try_cast(try_strptime(DT_ENCERRA, '%d/%m/%Y') as date) as dt_encerramento,
    CASE WHEN SITUA_ENCE IN (1,2,3,4,5,6,7,8,9,10) THEN 'Encerrado' ELSE 'Em aberto' END as situacao,
    NM_PACIENT as nome_paciente,
    try_cast(try_strptime(DT_NASC, '%d/%m/%Y') as date) as dt_nasc,
    CASE 
      WHEN LEFT(CAST(NU_IDADE_N AS VARCHAR), 1) = '1' THEN CAST(RIGHT(CAST(NU_IDADE_N AS VARCHAR), 3) AS INTEGER)/8760
      WHEN LEFT(CAST(NU_IDADE_N AS VARCHAR), 1) = '2' THEN CAST(RIGHT(CAST(NU_IDADE_N AS VARCHAR), 3) AS INTEGER)/365
      WHEN LEFT(CAST(NU_IDADE_N AS VARCHAR), 1) = '3' THEN CAST(RIGHT(CAST(NU_IDADE_N AS VARCHAR), 3) AS INTEGER)/12
      WHEN LEFT(CAST(NU_IDADE_N AS VARCHAR), 1) = '4' THEN CAST(RIGHT(CAST(NU_IDADE_N AS VARCHAR), 3) AS INTEGER)
    END as idade,
    CS_SEXO as sexo,
    CASE 
      WHEN CS_RACA = 1 THEN 'Branca'
      WHEN CS_RACA = 2 THEN 'Preta'
      WHEN CS_RACA = 3 THEN 'Amarela'
      WHEN CS_RACA = 4 THEN 'Amarela'
      WHEN CS_RACA = 5 THEN 'Indígena'
      WHEN CS_RACA = 9 THEN 'Ignorado'
      ELSE 'Não informado'
    END as raca_cor,
    LIST_SORT(
      LIST_DISTINCT(
        [
          CASE WHEN AGRAVAIDS = 1 THEN 'AIDS' ELSE NULL END,
          CASE WHEN AGRAVALCOO = 1 THEN 'Alcoolismo' ELSE NULL END,
          CASE WHEN AGRAVDIABE = 1 THEN 'Diabetes' ELSE NULL END,
          CASE WHEN AGRAVDOENC = 1 THEN 'Doença mental' ELSE NULL END,
          CASE WHEN AGRAVDROGA = 1 THEN 'Uso de drogas ilícitas' ELSE NULL END,
          CASE WHEN AGRAVTABAC = 1 THEN 'Tabagismo' ELSE NULL END,
          CASE WHEN AGRAVOUTRA = 1 THEN AGRAVOUTDE ELSE NULL END
        ]
      )
    ) as comorbidades,
    ARRAY_LENGTH(
      LIST_SORT(
        LIST_DISTINCT(
          [
            CASE WHEN AGRAVAIDS = 1 THEN 'AIDS' ELSE NULL END,
            CASE WHEN AGRAVALCOO = 1 THEN 'Alcoolismo' ELSE NULL END,
            CASE WHEN AGRAVDIABE = 1 THEN 'Diabetes' ELSE NULL END,
            CASE WHEN AGRAVDOENC = 1 THEN 'Doença mental' ELSE NULL END,
            CASE WHEN AGRAVDROGA = 1 THEN 'Uso de drogas ilícitas' ELSE NULL END,
            CASE WHEN AGRAVTABAC = 1 THEN 'Tabagismo' ELSE NULL END,
            CASE WHEN AGRAVOUTRA = 1 THEN AGRAVOUTDE ELSE NULL END
          ]
        )
      )
    ) as n_comorbidades,
    CASE 
      WHEN FORMA = 1 THEN 'Pulmonar'
      WHEN FORMA = 2 THEN 'Extrapulmonar'
      WHEN FORMA = 3 THEN 'Pulmonar + Extrapulmonar'
    END as forma,
    CASE
      WHEN SITUA_ENCE = 1 THEN 'Cura'
      WHEN SITUA_ENCE = 2 THEN 'Abandono'
      WHEN SITUA_ENCE = 3 THEN 'Óbito por TB'
      WHEN SITUA_ENCE = 4 THEN 'Óbito por outras causas'
      WHEN SITUA_ENCE = 5 THEN 'Transferência'
      WHEN SITUA_ENCE = 6 THEN 'Mudança de diagnóstico'
      WHEN SITUA_ENCE = 7 THEN 'TB-DR'
      WHEN SITUA_ENCE = 8 THEN 'Mudança de esquema'
      WHEN SITUA_ENCE = 9 THEN 'Falência'
      WHEN SITUA_ENCE = 10 THEN 'Abandono primário'
      ELSE 'Em aberto'
    END as desfecho,
    NM_LOGRADO as endereco,
    COALESCE(NM_LOGRADO, '') as endereco_cnefe,
    NM_BAIRRO as bairro,
    LATITUDE as lat,
    LONGITUDE as long
  FROM tb_sinan
")

DBI::dbDisconnect(con_sinan, shutdown = TRUE)

cat("✓ Banco sinan.duckdb criado com sucesso!\n")

# ============================================================================
# 2. Criar banco censo_aux.duckdb com dados de setores censitários Recife
# ============================================================================

cat("Criando banco censo_aux.duckdb...\n")

# Baixa dados de setores censitários Recife
setor_re <- geobr::read_census_tract(
  code_tract = 2611606,  # Código de Recife
  year = 2022,
  simplified = FALSE
)

# Processa dados de população
# Extrai apenas as colunas necessárias
tb_setor_censitario <- setor_re %>%
  sf::st_drop_geometry() %>%
  dplyr::as_tibble() %>%
  dplyr::select(
    id_setor_censitario = code_tract,
    code_neighborhood,
    name_neighborhood,
    code_subdistrict,
    name_subdistrict
  ) %>%
  # Adiciona coluna de população (placeholder)
  # Você pode substituir isso pelos dados reais de população
  dplyr::mutate(pessoas = NA_integer_)

# Conecta ao DuckDB e cria tabela
con_censo <- DBI::dbConnect(duckdb::duckdb(), "local/censo_aux.duckdb")

dbGetQuery(con_censo, "SELECT * FROM TB_SETOR_CENSITARIO WHERE CODE_NEIGHBORHOOD IS NULL")

# Remove tabela se existir
tryCatch(
  DBI::dbExecute(con_censo, "DROP TABLE tb_setor_censitario"),
  error = function(e) NULL
)

# Cria a tabela
DBI::dbWriteTable(con_censo, "tb_setor_censitario", tb_setor_censitario, overwrite = TRUE)

DBI::dbDisconnect(con_censo, shutdown = TRUE)

cat("✓ Banco censo_aux.duckdb criado com sucesso!\n")

# ============================================================================
# Resumo
# ============================================================================

cat("\n========================================\n")
cat("✓ Inicialização completa!\n")
cat("========================================\n")
cat("Bancos criados:\n")
cat("  - local/sinan.duckdb (tabela: tb_sinan_treated)\n")
cat("  - local/censo_aux.duckdb (tabela: tb_setor_censitario)\n")
cat("\nVocê já pode rodar o app com run_dev()\n")
