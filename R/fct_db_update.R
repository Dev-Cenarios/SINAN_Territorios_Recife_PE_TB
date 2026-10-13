# R/fct_db_update.R
# ==================================================================================
# FUNÇÃO: update_tb_data()
# 
# PROPÓSITO:
#   Monta a base local (DuckDB + caches) a partir da fonte de dados configurada
#   (ver fonte_dados_configurada() abaixo), aplica as transformações do painel
#   e salva no DuckDB local. Sem configuração, a fonte são os DADOS FICTÍCIOS
#   distribuídos com o pacote (inst/extdata/dados_ficticios, gerados por
#   dev/gerar_dados_ficticios.R).
#
# RETORNO:
#   Lista com: success (TRUE/FALSE), message (texto do resultado), records_updated (número)
#
# ==================================================================================

# ==================================================================================
# FONTE DOS DADOS: FICTÍCIOS (PADRÃO) OU REAIS
# ==================================================================================
# Sem configuracao, o painel usa os dados ficticios do pacote e mostra os
# avisos de DADOS FICTICIOS. Para rodar com dados reais, defina a variavel de
# ambiente PAINEL_DADOS_REAIS_DIR (no .Renviron do servidor, FORA do
# repositorio) com a pasta que contem:
#   - sinan_tb_recife.csv    (obrigatorio) casos, com as mesmas colunas do CSV
#                            ficticio (ver README, "Rodar com dados reais");
#   - sim_obitos_orfaos.csv  (opcional) obitos por TB so' no SIM.
# Os avisos nao tem chave propria: dependem da origem da base que esta'
# carregada (registrada em local/fonte_dados.rds por prepara_base()). Assim
# nao ha' como mostrar dados ficticios sem aviso, nem esquecer o aviso ligado
# sobre dados reais.

arquivo_fonte_base <- "local/fonte_dados.rds"

# Arquivo de inst/extdata/dados_ficticios, no pacote instalado ou na pasta do app
caminho_dados_ficticios <- function(arquivo) {
  app_sys("extdata/dados_ficticios", arquivo)
}

# Fonte configurada: modo ("ficticio"/"real") e caminho dos arquivos de casos
# (sinan) e de obitos so' no SIM (sim, NA quando nao existe)
fonte_dados_configurada <- function() {
  dir_reais <- Sys.getenv("PAINEL_DADOS_REAIS_DIR")

  if (!nzchar(dir_reais)) {
    return(list(
      modo  = "ficticio",
      sinan = caminho_dados_ficticios("sinan_tb_recife_ficticio.csv"),
      sim   = caminho_dados_ficticios("sim_obitos_orfaos_ficticio.csv")
    ))
  }

  # Com a variavel definida, nunca cai nos ficticios em silencio: sem o
  # arquivo de casos, para com erro.
  sinan <- file.path(dir_reais, "sinan_tb_recife.csv")
  if (!file.exists(sinan)) {
    stop("PAINEL_DADOS_REAIS_DIR esta' definido, mas a pasta nao tem o arquivo sinan_tb_recife.csv")
  }
  sim <- file.path(dir_reais, "sim_obitos_orfaos.csv")

  list(
    modo  = "real",
    sinan = normalizePath(sinan),
    sim   = if (file.exists(sim)) normalizePath(sim) else NA_character_
  )
}

# Identifica a fonte e a versao dos arquivos (data de modificacao e tamanho):
# a base local e' remontada quando muda
assinatura_fonte <- function(fonte) {
  arquivos <- stats::na.omit(c(fonte$sinan, fonte$sim))
  info <- file.info(arquivos)
  list(
    modo     = fonte$modo,
    arquivos = unname(as.character(arquivos)),
    mtime    = as.numeric(info$mtime),
    tamanho  = info$size
  )
}

# TRUE quando a base carregada veio dos dados ficticios -- liga os avisos de
# DADOS FICTICIOS. Sem registro de origem (base montada por uma versao antiga
# ou ainda em montagem), considera ficticia: na duvida, o aviso aparece.
dados_sao_ficticios <- function() {
  !identical(le_fonte_base()$modo, "real")
}

# Registro de origem da base local (NULL se nao existe ou nao da' para ler)
le_fonte_base <- function() {
  if (!file.exists(arquivo_fonte_base)) return(NULL)
  tryCatch(readRDS(arquivo_fonte_base), error = function(e) NULL)
}

# CSV com as colunas de texto lidas como texto (datas dd/mm/aaaa, codigos com
# letra, sexo "F"/"M"), como chegam do banco na producao; o resto (codigos
# numericos, coordenadas) e' convertido pelo read.csv. Aceita separador "," com
# decimal "." (formato dos ficticios) ou ";" com decimal "," (CSV brasileiro).
le_csv_fonte <- function(caminho, colunas_texto) {
  cabecalho <- readLines(caminho, n = 1, warn = FALSE, encoding = "UTF-8")
  conta <- function(caractere) lengths(regmatches(cabecalho, gregexpr(caractere, cabecalho, fixed = TRUE)))
  sep <- if (conta(";") > conta(",")) ";" else ","

  utils::read.csv(
    caminho,
    sep = sep,
    dec = if (sep == ";") "," else ".",
    colClasses = stats::setNames(rep("character", length(colunas_texto)), colunas_texto),
    na.strings = c("", "NA"),
    fileEncoding = "UTF-8",
    check.names = FALSE
  )
}

update_tb_data <- function(fonte = fonte_dados_configurada()) {

  # Envolve todo o código em tryCatch para capturar erros sem quebrar o app
  tryCatch({

    # ==================================================================================
    # PASSO 1: LER OS ÓBITOS POR TB SÓ NO SIM
    # ==================================================================================

    # Obitos por TB que aparecem so no SIM (sem notificacao SINAN
    # correspondente), vindos do linkage SINAN-SIM. Opcional: sem o arquivo,
    # o painel segue sem o reforco de mortalidade desses obitos.
    obitos_sim_orfaos_new <- if (!is.na(fonte$sim)) {
      le_csv_fonte(fonte$sim, c("CAUSABAS", "BAIRES"))
    }

    if (!dir.exists("local")) dir.create("local")
    
    # ==================================================================================
    # PASSO 2: CONTAR REGISTROS ANTIGOS NO DUCKDB
    # ==================================================================================
    
    # Só tenta abrir o banco em modo leitura se o arquivo ja existir --
    # duckdb::duckdb() com read_only = TRUE lanca erro direto na conexao
    # (fora de qualquer tryCatch interno) se o arquivo nao existir ainda,
    # o que quebra a primeira execucao (ex: producao recem clonada, sem
    # local/sinan.duckdb ainda) antes mesmo de chegar na parte que trata
    # "tabela nao existe ainda". Mesmo fix ja aplicado em SP/Manaus/DF.
    count_old <- if (file.exists("local/sinan.duckdb")) {
      # Cria conexão de LEITURA (read_only = TRUE) com o banco local DuckDB
      con_duck_check <- DBI::dbConnect(
        duckdb::duckdb(),                                 # Driver DuckDB
        "local/sinan.duckdb",                             # Caminho do arquivo do banco
        read_only = TRUE                                  # Só lê, não modifica
      )

      # Tenta contar quantos registros já existem na tabela transformada
      resultado <- tryCatch(
        # Se conseguir, pega a contagem
        DBI::dbGetQuery(con_duck_check, "SELECT COUNT(*) as cnt FROM tb_sinan_treated")$cnt,
        # Se falhar (ex: tabela não existe ainda), retorna 0
        error = function(e) 0
      )

      # Fecha conexão de leitura para liberar recurso
      DBI::dbDisconnect(con_duck_check, shutdown = TRUE)
      resultado
    } else {
      0
    }
    
    # ==================================================================================
    # PASSO 3: LER OS CASOS
    # ==================================================================================

    # Colunas da tabela da pipeline de georreferenciamento: campos do SINAN,
    # campos do SIM vindos do linkage (DTOBITO, CAUSABAS), GEORREFERENCIADO e
    # INDICADOR -- ver comentario no PASSO 6.
    tb_sinan_new <- le_csv_fonte(
      fonte$sinan,
      c("NU_NOTIFIC", "DT_NOTIFIC", "DT_DIAG", "NM_PACIENT", "DT_NASC", "CS_SEXO",
        "NM_BAIRRO", "ADDRESS_CORE", "ENDERECO_CNEFE", "AGRAVOUTDE", "DT_INIC_TR",
        "DT_ENCERRA", "CAUSABAS")
    )

    # ==================================================================================
    # PASSO 3.1: VALIDAR OS DADOS NOVOS ANTES DE SOBRESCREVER
    # ==================================================================================

    # Nunca sobrescrever dados bons com uma resposta vazia ou suspeitosamente
    # menor do que o que já existia (ex.: instabilidade momentânea no Postgres,
    # tabela de origem em recarga, problema de permissão pontual). Sem essa
    # trava, qualquer falha silenciosa aqui apaga a tabela local de produção.
    if (nrow(tb_sinan_new) == 0) {
      stop("Atualizacao abortada: os dados de origem vieram com 0 registros. Nenhum dado foi sobrescrito.")
    }
    if (count_old > 0 && nrow(tb_sinan_new) < count_old * 0.5) {
      stop(
        "Atualizacao abortada: os dados de origem vieram com ", nrow(tb_sinan_new),
        " registros, bem menos que os ", count_old, " ja existentes. ",
        "Nenhum dado foi sobrescrito."
      )
    }

    # ==================================================================================
    # PASSO 4: CONECTAR AO DUCKDB PARA ATUALIZAR
    # ==================================================================================
    
    # Cria nova conexão de ESCRITA com DuckDB (sem read_only)
    con_duck <- DBI::dbConnect(
      duckdb::duckdb(),                                 # Driver DuckDB
      "local/sinan.duckdb"                              # Caminho do arquivo
      # Sem read_only = TRUE, então pode modificar dados
    )
    
    # ==================================================================================
    # PASSO 5: ESCREVER TABELA BRUTA (tb_sinan)
    # ==================================================================================
    
    # Escreve os dados brutos (CSV da fonte) na tabela tb_sinan
    # overwrite = TRUE significa: se a tabela já existe, substitui completamente
    DBI::dbWriteTable(
      con_duck,                                         # Conexão DuckDB
      "tb_sinan",                                       # Nome da tabela
      tb_sinan_new,                                     # Dados a inserir (CSV da fonte)
      overwrite = TRUE                                  # Sobrescreve se já existe
    )

    # Escreve a tabela de obitos orfaos do SIM. Sem o arquivo, apaga a de
    # uma carga anterior -- senao o painel mostraria obitos de outra base.
    if (!is.null(obitos_sim_orfaos_new)) {
      DBI::dbWriteTable(
        con_duck,
        "tb_sim_orfaos",
        obitos_sim_orfaos_new,
        overwrite = TRUE
      )
    } else {
      DBI::dbExecute(con_duck, "drop table if exists tb_sim_orfaos")
      DBI::dbExecute(con_duck, "drop table if exists tb_sim_orfaos_treated")
      unlink("local/obitos_sim_orfaos_cache.rds")
    }

    # ==================================================================================
    # PASSO 6: APLICAR TRANSFORMAÇÃO SQL (tb_sinan → tb_sinan_treated)
    # ==================================================================================
    
    # Executa comando SQL que CRIA UMA TABELA NOVA/SUBSTITUIDA com dados transformados
    # Este é o SQL que estava em dados_cenarios.r - faz limpeza e padronização de dados
    DBI::dbExecute(
      con_duck,                                         # Conexão DuckDB
      # COMANDO SQL GIGANTE que:
      # - Renomeia colunas (NU_NOTIFIC → numero_notificacao)
      # - Converte datas (DT_INIC_TR de texto para DATE)
      # - Decodifica categorias (SITUA_ENCE 1 → "Cura", 2 → "Abandono", etc)
      # - Calcula idade em anos (NU_IDADE_N é codificado com tipo e valor)
      # - Agrupa comorbidades em arrays
      # - Determina se casos estão "Encerrados" ou "Em aberto"
      # - Verifica se tem georreferenciamento (coords válidas)
      "create or replace table tb_sinan_treated as (
      with base as (
      select
      NU_NOTIFIC as numero_notificacao,
      DT_DIAG as dt_diagnostico,
      DT_NOTIFIC as dt_notificacao,
      try_cast(try_strptime(DT_INIC_TR, '%d/%m/%Y') as date) as dt_inicio_tratamento,
      try_cast(try_strptime(DT_ENCERRA, '%d/%m/%Y') as date) as dt_encerramento_sinan,
      case when
        SITUA_ENCE in (1,2,3,4,5,6,7,8,9,10) then 'Encerrado'
        else 'Em aberto'
      end as situacao_sinan,
      nm_pacient as nome_paciente,
      try_cast(try_strptime(DT_NASC, '%d/%m/%Y') as date) as dt_nasc,
      case
        when left(cast(NU_IDADE_N as varchar), 1) = 1 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)/8760
        when left(cast(NU_IDADE_N as varchar), 1) = 2 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)/365
        when left(cast(NU_IDADE_N as varchar), 1) = 3 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)/12
        when left(cast(NU_IDADE_N as varchar), 1) = 4 then cast(right(cast(NU_IDADE_N as varchar), 3) as integer)
      end as idade,
      cs_sexo as sexo,
      case
        when CS_RACA = 1 then 'Branca'
        when CS_RACA = 2 then 'Preta'
        when CS_RACA = 3 then 'Amarela'
        when CS_RACA = 4 then 'Parda'
        when CS_RACA = 5 then 'Indígena'
        when CS_RACA = 9 then 'Ignorado'
      end as raca_cor,
      list_sort(
        list_distinct(
          [
            case when AGRAVAIDS = 1 then 'AIDS' else null end,
            case when AGRAVALCOO = 1 then 'Alcoolismo' else null end,
            case when AGRAVDIABE = 1 then 'Diabetes' else null end,
            case when AGRAVDOENC = 1 then 'Doença mental' else null end,
            case when AGRAVDROGA = 1 then 'Uso de drogas ilícitas' else null end,
            case when AGRAVTABAC = 1 then 'Tabagismo' else null end,
            case when AGRAVOUTRA = 1 then AGRAVOUTDE else null end
          ]
        )
      ) as comorbidades,
      array_length(comorbidades) as n_comorbidades,
      case
        when TRATAMENTO = 1 then 'Caso Novo'
        when TRATAMENTO = 2 then 'Recidiva'
        when TRATAMENTO = 3 then 'Reingresso após abandono'
        when TRATAMENTO = 4 then 'Não Sabe'
        when TRATAMENTO = 5 then 'Transferência'
        when TRATAMENTO = 6 then 'Pós-óbito'
      end as tipo_entrada,
      list_sort(
        list_distinct(
          [
            case when POP_LIBER = 1 then 'Privado de liberdade' else null end,
            case when POP_RUA = 1 then 'Situação de rua' else null end,
            case when POP_SAUDE = 1 then 'Profissional de Saúde' else null end,
            case when POP_IMIG = 1 then 'Imigrante' else null end,
            case when BENEF_GOV = 1 then 'Beneficiário programa de transferência de renda' else null end
          ]
        )
      ) as populacao_especial,
      case
        when FORMA = 1 then 'Pulmonar'
        when FORMA = 2 then 'Extrapulmonar'
        when FORMA = 3 then 'Pulmonar + Extrapulmonar'
      end as forma,
      case
        when SITUA_ENCE = 1 then 'Cura'
        when SITUA_ENCE = 2 then 'Abandono'
        when SITUA_ENCE = 3 then 'Óbito por TB'
        when SITUA_ENCE = 4 then 'Óbito por outras causas'
        when SITUA_ENCE = 5 then 'Transferência'
        when SITUA_ENCE = 6 then 'Mudança de diagnóstico'
        when SITUA_ENCE = 7 then 'TB-DR'
        when SITUA_ENCE = 8 then 'Mudança de esquema'
        when SITUA_ENCE = 9 then 'Falência'
        when SITUA_ENCE = 10 then 'Abandono primário'
      end as desfecho_sinan,
      -- Obito por TB confirmado via SIM (Declaracao de Obito), quando o caso
      -- tem par no linkage SINAN-SIM. DTOBITO vem do SIM as vezes sem zero a
      -- esquerda (ex.: dia 2 vira '2082021' em vez de '02082021'); por isso
      -- o lpad antes do strptime -- mesmo tipo de bug ja visto em DT_DIAG.
      try_cast(try_strptime(lpad(cast(DTOBITO as varchar), 8, '0'), '%d%m%Y') as date) as dt_obito_sim,
      CAUSABAS as causabas_sim,
      -- Obito confirmado no SIM por linkage, seja qual for a causa (nao so
      -- TB). O linkage (etapa 03 do pipeline de enriquecimento) agora traz
      -- qualquer causa de obito pros casos pareados, nao so tuberculose --
      -- usado abaixo pra corrigir qualquer desfecho que o SINAN registrou
      -- (Cura, Abandono, Em aberto etc.) quando a pessoa de fato morreu,
      -- mesmo que a causa nao seja TB.
      CAUSABAS is not null as obito_confirmado_sim,
      -- Quando o SIM tem um obito pareado, ele decide (corrige subnotificacao
      -- e falso-positivo do proprio SINAN); sem par no SIM, cai no desfecho
      -- do SINAN (SITUA_ENCE = 3) como estava antes.
      case
        when CAUSABAS is not null then
          substr(cast(CAUSABAS as varchar), 1, 3) in ('A15','A16','A17','A18','A19')
        else SITUA_ENCE = 3
      end as obito_tb_confirmado,
      ADDRESS_CORE as endereco,
      endereco_cnefe as endereco_cnefe,
      nm_bairro as bairro,
      -- Codigo CNES da unidade notificadora -- usado pro mapa plotar as
      -- unidades de saude (cruzado com a API publica do DATASUS em
      -- dev/build_unidades_cnes.R, ver local/unidades_cnes.rds).
      trim(cast(ID_UNIDADE as varchar)) as cod_unidade_notificadora,
      -- GEORREFERENCIADO e INDICADOR vem prontos da pipeline de
      -- georreferenciamento (repositorio Sistema-de-georreferenciamento-
      -- Projeto-Cenarios-UnB, classificar_georreferenciado() e
      -- classificar_indicador()) -- antes o painel calculava o proprio
      -- georreferenciado so' olhando se NM_LOGRADO/NM_COMPLEM estavam
      -- preenchidos, o que contava centroide como georreferenciado.
      --   georreferenciado = 1: o caso casou numa fase de endereco; 0:
      --     centroide (CENTROIDE_MUN), sem coordenada ou endereco vazio.
      --     Linhas que a pipeline nao classificou (NULL) contam como 0.
      --   indicador = 0: detento ou situacao de rua (POP_LIBER/POP_RUA ou
      --     endereco de presidio/albergue etc.); 1: demais. Sem
      --     classificacao da pipeline, cai no POP_LIBER/POP_RUA.
      coalesce(cast(GEORREFERENCIADO as integer), 0) as georreferenciado,
      coalesce(
        cast(INDICADOR as integer),
        case when POP_LIBER = 1 or POP_RUA = 1 then 0 else 1 end
      ) as indicador,
      LATITUDE AS lat,
      LONGITUDE AS long
      from tb_sinan
      )
      -- Reclassifica desfecho/situacao/encerramento pelo SIM quando os dois
      -- divergem (decisao: SIM manda). Cobre qualquer par SINAN-SIM
      -- divergente, nao so quando o SINAN ja dizia 'Óbito por TB' -- um caso
      -- registrado como Cura/Abandono/Em aberto cujo SIM mostra que a pessoa
      -- morreu (de qualquer causa) tambem precisa fechar como óbito. Sem
      -- isso, o card de obitos (que ja usa obito_tb_confirmado) fica
      -- inconsistente com qualquer lugar que ainda lesse o desfecho puro do
      -- SINAN (tabela de casos, popup, filtro, legenda do mapa).
      select
      * exclude (situacao_sinan, desfecho_sinan, dt_encerramento_sinan),
      case
        when obito_confirmado_sim then 'Encerrado'
        else situacao_sinan
      end as situacao,
      case
        when obito_tb_confirmado then 'Óbito por TB'
        when obito_confirmado_sim then 'Óbito por outras causas'
        else desfecho_sinan
      end as desfecho,
      case
        when obito_confirmado_sim then coalesce(dt_encerramento_sinan, dt_obito_sim)
        else dt_encerramento_sinan
      end as dt_encerramento
      from base
    );"
    )
    
    # ==================================================================================
    # PASSO 6.1: TRANSFORMAR TABELA DE OBITOS ORFAOS DO SIM (se existir)
    # ==================================================================================
    # Obitos por TB que nao tem notificacao correspondente no SINAN (nao
    # passaram pelo linkage). Nao viram "casos" -- so alimentam os cards/mapa
    # de mortalidade e letalidade. O nome do bairro e normalizado aqui
    # (maiusculo, sem acento, alias de abreviacoes do DATASUS) para casar,
    # do lado R, com o nome do bairro no shapefile do painel.
    if (!is.null(obitos_sim_orfaos_new)) {
      DBI::dbExecute(
        con_duck,
        "create or replace table tb_sim_orfaos_treated as (
        select
          NUMERODO as numerodo_do_sim,
          try_cast(try_strptime(lpad(cast(DTOBITO as varchar), 8, '0'), '%d%m%Y') as date) as dt_obito_sim,
          CAUSABAS as causabas_sim,
          substr(cast(CAUSABAS as varchar), 1, 3) in ('A15','A16','A17','A18','A19') as obito_tb_confirmado,
          -- Alias de abreviacoes conhecidas do DATASUS antes de normalizar
          strip_accents(upper(trim(
            case
              when BAIRES like 'I.%' then 'ILHA ' || substr(BAIRES, 3)
              else BAIRES
            end
          ))) as bairro_norm
        from tb_sim_orfaos
        );"
      )
    }

    # ==================================================================================
    # PASSO 6.5: GERAR CACHE RDS (carregamento rápido na sessão do usuário)
    # ==================================================================================

    tryCatch({
      # prepara_casos() (R/fct_casos.R) monta os casos do painel e ja' grava
      # o bairro e o Distrito Sanitario de cada ponto no cache -- o painel
      # nao precisa refazer esses cruzamentos espaciais ao abrir nem a cada
      # clique.
      casos_cache <- DBI::dbGetQuery(con_duck, "SELECT * FROM tb_sinan_treated") |>
        prepara_casos()

      saveRDS(casos_cache, "local/casos_cache.rds")
    }, error = function(e) {
      warning("Cache RDS não gerado: ", as.character(e))
    })

    # Cache dos obitos orfaos do SIM (se a tabela existir)
    tryCatch({
      if (DBI::dbExistsTable(con_duck, "tb_sim_orfaos_treated")) {
        orfaos_cache <- DBI::dbGetQuery(con_duck, "SELECT * FROM tb_sim_orfaos_treated") |>
          dplyr::as_tibble()
        saveRDS(orfaos_cache, "local/obitos_sim_orfaos_cache.rds")
      }
    }, error = function(e) {
      warning("Cache de obitos orfaos nao gerado: ", as.character(e))
    })

    # ==================================================================================
    # PASSO 7: CONTAR REGISTROS NOVOS NO DUCKDB
    # ==================================================================================
    
    # Pega a contagem de registros APÓS a transformação
    count_new <- DBI::dbGetQuery(
      con_duck,                                         # Usa a conexão DuckDB aberta
      "SELECT COUNT(*) as cnt FROM tb_sinan_treated"   # Conta registros na tabela transformada
    )$cnt                                               # Extrai apenas o número (coluna $cnt)
    
    # Fecha a conexão DuckDB
    DBI::dbDisconnect(
      con_duck,                                         # Conexão a fechar
      shutdown = TRUE                                   # Encerra o driver DuckDB também
    )
    
    # ==================================================================================
    # PASSO 8: CALCULAR DIFERENÇA E RETORNAR RESULTADO
    # ==================================================================================
    
    # Calcula quantos registros foram ADICIONADOS
    records_updated <- count_new - count_old
    
    # Se houver registros novos (diferença positiva)
    if (records_updated > 0) {
      # Retorna lista com sucesso, mensagem amigável e contador
      return(list(
        success = TRUE,                                 # Flag de sucesso
        message = paste0("✅ Atualização concluída! ", records_updated, " novo(s) registro(s) adicionado(s)."),
        records_updated = records_updated               # Quantidade de registros novos
      ))
    # Se não tiver registro novo (diferença = 0)
    } else if (records_updated == 0) {
      # Retorna lista informando que não há dados novos
      return(list(
        success = TRUE,
        message = "ℹ️ Nenhum dado novo para atualizar.",
        records_updated = 0
      ))
    # Se houver diferença negativa (dados foram removidos)
    } else {
      # Retorna informação sobre reprocessamento
      return(list(
        success = TRUE,
        message = paste0("📊 Dados reprocessados. Total: ", count_new, " registros."),
        records_updated = count_new
      ))
    }
    
  # ==================================================================================
  # TRATAMENTO DE ERROS
  # ==================================================================================
  
  # Se ocorrer qualquer erro durante execução do código acima
  }, error = function(e) {
    # Retorna lista com erro (success = FALSE)
    return(list(
      success = FALSE,                                  # Flag de erro
      message = paste0("❌ Erro na atualização: ", as.character(e)), # Mensagem de erro formatada
      records_updated = 0                               # Nenhum registro foi atualizado
    ))
  })
}

# ==================================================================================
# FUNÇÃO: prepara_base()
#
# Chamada a cada abertura do painel. Monta a base local quando ela ainda nao
# existe ou quando a fonte mudou -- troca entre dados ficticios e reais, outra
# pasta, ou arquivo atualizado -- e registra a origem em local/fonte_dados.rds
# (que liga ou desliga os avisos de DADOS FICTICIOS, ver dados_sao_ficticios()).
# Sem mudanca, so' confere data e tamanho dos arquivos. Tambem copia o cadastro
# publico das unidades de saude, se local/ ainda nao tem um.
# ==================================================================================

prepara_base <- function() {
  if (!dir.exists("local")) dir.create("local")

  if (!file.exists("local/unidades_cnes.rds")) {
    file.copy(caminho_dados_ficticios("unidades_cnes.rds"), "local/unidades_cnes.rds")
  }

  fonte <- fonte_dados_configurada()
  nova <- assinatura_fonte(fonte)
  atual <- le_fonte_base()

  if (identical(atual, nova) && file.exists("local/casos_cache.rds")) {
    return(invisible(nova$modo))
  }

  # Outra fonte (ficticio <-> real, outra pasta) ou base sem registro de
  # origem: comeca do zero, sem a trava de "bem menos registros que antes"
  # do update_tb_data() (que so' faz sentido para a mesma fonte). O registro
  # de origem sai primeiro: enquanto a base nao estiver pronta, vale o aviso.
  mesma_fonte <- !is.null(atual) && identical(atual[c("modo", "arquivos")], nova[c("modo", "arquivos")])
  if (!mesma_fonte) {
    unlink(c(arquivo_fonte_base, "local/sinan.duckdb", "local/sinan.duckdb.wal",
             "local/casos_cache.rds", "local/obitos_sim_orfaos_cache.rds"))
  }

  message("Montando a base local a partir dos dados ",
          if (fonte$modo == "real") "REAIS" else "ficticios", "...")
  resultado <- update_tb_data(fonte)

  if (!isTRUE(resultado$success)) {
    # Mesma fonte com arquivo novo recusado pela validacao: segue com a base
    # anterior, que tem a mesma origem (e tenta de novo na proxima abertura)
    if (mesma_fonte && file.exists("local/casos_cache.rds")) {
      warning(resultado$message)
      return(invisible(atual$modo))
    }
    stop(resultado$message)
  }

  saveRDS(nova, arquivo_fonte_base)
  message(resultado$message)
  invisible(nova$modo)
}
