# R/fct_casos.R -- carga dos casos e das malhas, compartilhada entre sessoes
# ==================================================================================
# No Shiny Server todas as sessoes do painel (cada usuario que abre a pagina)
# rodam no mesmo processo R. Casos, obitos so-SIM e malhas sao carregados uma
# vez por processo e reaproveitados por toda sessao nova (carrega_casos(),
# carrega_obitos_orfaos(), malha_*()); os casos recarregam sozinhos quando o
# cache muda no disco (botao "Atualizar dados").
#
# Cada caso tambem ja' sai com o bairro e o Distrito Sanitario onde o ponto
# cai (atribui_territorio()), gravados no cache por update_tb_data(): os
# indicadores por territorio contam por essas colunas em vez de refazer o
# cruzamento espacial territorios x casos a cada clique.
# ==================================================================================

cache_processo <- new.env(parent = emptyenv())

# Guarda em cache_processo o resultado de `expr` na primeira chamada; as
# seguintes (inclusive de outras sessoes) devolvem o mesmo objeto.
memo_processo <- function(chave, expr) {
  if (is.null(cache_processo[[chave]])) cache_processo[[chave]] <- force(expr)
  cache_processo[[chave]]
}

caminho_shape <- function(arquivo) {
  app_sys("app/www/shapes", arquivo)
}

# Limite do municipio de Recife, SIRGAS 2000 / UTM 25S
limite_municipio <- function() {
  memo_processo("limite_municipio", {
    sf::st_read(caminho_shape("recife.gpkg"), quiet = TRUE) |> sf::st_transform(31985)
  })
}

# 94 bairros do IBGE, malha completa -- usada em todo calculo.
malha_bairros <- function() {
  memo_processo("malha_bairros", {
    if (file.exists("local/bairros_cache.rds")) {
      readRDS("local/bairros_cache.rds")
    } else {
      bair <- sf::st_read(caminho_shape("bairros_recife.gpkg"), quiet = TRUE) |> sf::st_transform(31985)
      saveRDS(bair, "local/bairros_cache.rds")
      bair
    }
  })
}

# Distritos Sanitarios, gerados por dev/build_distritos_sanitarios.R: cada DS
# e' a uniao dos bairros do IBGE que a SESAU atribui a ele (limites iguais
# aos dos bairros do mapa; pop = soma do Censo 2022 dos bairros).
malha_distritos <- function() {
  memo_processo("malha_distritos", {
    sf::st_read(caminho_shape("distritos_sanitarios_recife.gpkg"), quiet = TRUE) |> sf::st_transform(31985)
  })
}

# Areas de abrangencia da APS, geradas por dev/build_abrangencia_aps.R a
# partir da territorializacao oficial da SESAU no ESIG (uma area por
# USF/USF+/EACS, mais areas descobertas e "nao se aplica").
malha_abrangencia <- function() {
  memo_processo("malha_abrangencia", {
    sf::st_read(caminho_shape("abrangencia_aps_recife.gpkg"), quiet = TRUE)
  })
}

# Bairros e DS SO' PRO DESENHO do indicador no mapa, simplificados a 5 m de
# tolerancia -- o poligono do indicador e' reenviado a cada troca de filtro,
# periodo ou indicador. Nenhum calculo usa essas versoes.
malha_bairros_desenho <- function() {
  memo_processo("malha_bairros_desenho", {
    sf::st_simplify(malha_bairros(), dTolerance = 5, preserveTopology = TRUE)
  })
}

malha_distritos_desenho <- function() {
  memo_processo("malha_distritos_desenho", {
    sf::st_simplify(malha_distritos(), dTolerance = 5, preserveTopology = TRUE)
  })
}

# DS de cada bairro (mesma ordem de malha_bairros()) -- ponto interno do
# bairro dentro do poligono do DS. Usado pra somar os obitos so-SIM, que so'
# tem o nome do bairro, por DS.
ds_de_cada_bairro <- function() {
  memo_processo("ds_de_cada_bairro", {
    pontos <- sf::st_point_on_surface(sf::st_geometry(malha_bairros()))
    ds <- malha_distritos()
    idx <- sf::st_intersects(pontos, ds)
    ds$cod_ds[vapply(idx, function(i) if (length(i) > 0) i[1] else NA_integer_, integer(1))]
  })
}

# Centroide de cada bairro, usado como localizacao aproximada dos obitos por
# TB que so' aparecem no SIM (sem endereco/coordenada propria).
centroides_bairros <- function() {
  memo_processo("centroides_bairros", {
    bair <- malha_bairros()
    sf::st_sf(
      bairro_norm = stringi::stri_trans_general(toupper(trimws(bair$name_neighborhood)), "Latin-ASCII"),
      geometry = sf::st_geometry(suppressWarnings(sf::st_centroid(bair)))
    )
  })
}

# Bairro (territorio_bairro, name_neighborhood) e Distrito Sanitario
# (territorio_ds, cod_ds) onde o ponto de cada caso cai, na malha completa.
# NA = sem coordenada ou fora dos poligonos. Um ponto exatamente na divisa
# entre dois territorios fica no primeiro deles (o st_intersects() que os
# indicadores faziam antes contava nos dois).
atribui_territorio <- function(casos) {
  primeiro <- function(idx) vapply(idx, function(i) if (length(i) > 0) i[1] else NA_integer_, integer(1))

  bair <- malha_bairros()
  casos$territorio_bairro <- bair$name_neighborhood[primeiro(sf::st_intersects(casos, bair))]

  ds <- malha_distritos()
  casos$territorio_ds <- ds$cod_ds[primeiro(sf::st_intersects(casos, ds))]

  casos
}

# tb_sinan_treated (DuckDB) -> casos do painel: datas, pontos em SIRGAS 2000 /
# UTM 25S (caso sem coordenada vira ponto vazio), listas de comorbidade/
# populacao especial como texto, dias em aberto e territorio
# (atribui_territorio()). Usado pra gerar local/casos_cache.rds
# (update_tb_data()) e na carga direta do DuckDB quando o cache nao existe.
prepara_casos <- function(casos_raw) {
  casos_raw <- casos_raw |>
    dplyr::as_tibble() |>
    dplyr::mutate(
      dt_diagnostico = as.Date(dt_diagnostico, format = "%d/%m/%Y"),
      dt_notificacao = as.Date(dt_notificacao, format = "%d/%m/%Y")
    )

  last_date <- max(casos_raw$dt_notificacao, na.rm = TRUE)

  casos_raw |>
    # na.fail = FALSE: caso sem coordenada vira ponto vazio em vez de
    # derrubar o cache inteiro (fica fora do mapa e dos indicadores por
    # territorio, mas continua nos cards e na tabela de casos)
    sf::st_as_sf(coords = c("long", "lat"), crs = 4674, na.fail = FALSE) |>
    sf::st_transform(31985) |>
    dplyr::mutate(
      desfecho = dplyr::case_when(
        situacao == "Em aberto" & is.na(desfecho) ~ "Em aberto",
        TRUE ~ desfecho
      )
    ) |>
    dplyr::rowwise() |>
    dplyr::mutate(
      comorbidades       = paste(comorbidades, collapse = ", "),
      populacao_especial = paste(populacao_especial, collapse = ", "),
      tempo_aberto = dplyr::case_when(
        situacao == "Encerrado" ~ as.integer(difftime(dt_encerramento, dt_diagnostico, units = "days")),
        TRUE                    ~ as.integer(difftime(last_date,       dt_diagnostico, units = "days"))
      )
    ) |>
    dplyr::ungroup() |>
    atribui_territorio()
}

# Casos do painel, compartilhados entre as sessoes do processo. Le'
# local/casos_cache.rds (ou, sem ele, o DuckDB) so' na primeira chamada ou
# quando o arquivo muda.
carrega_casos <- function() {
  arq <- "local/casos_cache.rds"
  versao <- if (file.exists(arq)) file.mtime(arq) else "sem cache"

  if (!is.null(cache_processo$casos) && identical(cache_processo$casos_versao, versao)) {
    return(cache_processo$casos)
  }

  casos <- if (file.exists(arq)) {
    readRDS(arq)
  } else {
    con <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb", read_only = TRUE)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    prepara_casos(DBI::dbGetQuery(con, "select * from tb_sinan_treated"))
  }

  # Cache gerado antes da coluna `indicador` (vinda da pipeline de
  # georreferenciamento) existir: recria pela regra antiga
  # (POP_LIBER/POP_RUA) ate' o proximo update_tb_data().
  if (!"indicador" %in% names(casos)) {
    casos$indicador <- ifelse(grepl("Privado de liberdade|Situação de rua", casos$populacao_especial), 0L, 1L)
  }

  # Cache gerado antes do territorio ir pro cache (versao anterior do
  # update_tb_data()) -- calcula aqui, uma vez por processo.
  if (!all(c("territorio_bairro", "territorio_ds") %in% names(casos))) {
    casos <- atribui_territorio(casos)
  }

  cache_processo$casos <- casos
  cache_processo$casos_versao <- versao
  casos
}

# Obitos por TB so' no SIM (sem notificacao SINAN), compartilhados entre as
# sessoes. Nao sao "casos" (sem forma clinica, sem data de diagnostico, sem
# tratamento) -- alimentam so' os indicadores de mortalidade (card e mapa).
carrega_obitos_orfaos <- function() {
  arq <- "local/obitos_sim_orfaos_cache.rds"
  versao <- if (file.exists(arq)) file.mtime(arq) else if (file.exists("local/sinan.duckdb")) file.mtime("local/sinan.duckdb") else "sem base"

  if (!is.null(cache_processo$orfaos) && identical(cache_processo$orfaos_versao, versao)) {
    return(cache_processo$orfaos)
  }

  vazio <- dplyr::tibble(
    numerodo_do_sim = character(), dt_obito_sim = as.Date(character()),
    causabas_sim = character(), obito_tb_confirmado = logical(),
    bairro_norm = character()
  )

  orfaos <- if (file.exists(arq)) {
    readRDS(arq)
  } else if (file.exists("local/sinan.duckdb")) {
    con <- DBI::dbConnect(duckdb::duckdb(), "local/sinan.duckdb", read_only = TRUE)
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    if ("tb_sim_orfaos_treated" %in% DBI::dbListTables(con)) {
      DBI::dbGetQuery(con, "SELECT * FROM tb_sim_orfaos_treated") |> dplyr::as_tibble()
    } else {
      vazio
    }
  } else {
    vazio
  }

  cache_processo$orfaos <- orfaos
  cache_processo$orfaos_versao <- versao
  orfaos
}
