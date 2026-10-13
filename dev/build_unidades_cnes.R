# Monta o cache de unidades de saude do mapa (local/unidades_cnes.rds): as
# unidades notificadoras (codigo CNES) que aparecem nos casos do painel +
# toda a rede publica/SUS assistencial do municipio (UBS/USF, UPA,
# policlinicas, CAPS, hospitais publicos...), mesmo sem notificacao. Dados
# da API publica do DATASUS (coordenada, tipo, natureza juridica, status de
# habilitacao), com a coordenada oficial da SESAU (ESIG) quando a unidade
# esta na rede municipal. No mapa: "S" vermelho pra rede publica, "✕" pras
# demais notificadoras.
#
# Por que a API publica em vez do schema `cnes` do Postgres local: o schema
# local e' uma carga unica e parada em jan/2017 (ver cnes.controle_carga) e
# tem cobertura de coordenada quase nula entre as unidades que realmente
# aparecem nos casos (~1%). A API publica e' atualizada com regularidade e,
# numa amostra ao vivo, teve ~60% de cobertura.
#
# Rodar manualmente de vez em quando pra atualizar o cache -- nao roda
# automaticamente junto com update_tb_data(). Precisa de acesso a internet
# (API publica do DATASUS, sem autenticacao) e das credenciais do Postgres
# (.Renviron: PG_DB, PG_HOST, PG_PORT, PG_USER, PG_PASS). Rodar no mesmo
# lugar/maquina de onde `local/unidades_cnes.rds` precisa ser lido pelo app
# (em producao, direto no servidor -- `local/` nao e' versionado no git).

library(DBI)
library(RPostgres)
library(httr2)
library(dplyr)

MUNICIPIO_CODIGO <- "261160" # Recife
# Preencha com o schema e a tabela de casos georreferenciados do seu banco
SCHEMA_GEOLINK <- "<schema>"
TABELA_GEOLINK <- "<tabela_de_casos_georreferenciados>"

`%||%` <- function(a, b) if (is.null(a)) b else a

if (!dir.exists("local")) dir.create("local")

# ============================================================================
# 1. Codigos de unidade (ID_UNIDADE) vistos nos casos
# ============================================================================

cat("Buscando codigos de unidade notificadora nos casos...\n")

required_pg_vars <- c("PG_DB", "PG_HOST", "PG_USER", "PG_PASS")
missing_pg_vars <- required_pg_vars[!nzchar(Sys.getenv(required_pg_vars))]
if (length(missing_pg_vars) > 0) {
  stop(
    "Variaveis de ambiente do Postgres ausentes: ",
    paste(missing_pg_vars, collapse = ", ")
  )
}

con_pg <- DBI::dbConnect(
  RPostgres::Postgres(),
  dbname   = Sys.getenv("PG_DB"),
  host     = Sys.getenv("PG_HOST"),
  port     = as.numeric(Sys.getenv("PG_PORT", "5432")),
  user     = Sys.getenv("PG_USER"),
  password = Sys.getenv("PG_PASS")
)

codigos_casos <- DBI::dbGetQuery(con_pg, sprintf('
  SELECT DISTINCT TRIM("ID_UNIDADE"::text) as codigo_cnes
  FROM %s.%s
  WHERE "ID_UNIDADE" IS NOT NULL
', DBI::dbQuoteIdentifier(con_pg, SCHEMA_GEOLINK), DBI::dbQuoteIdentifier(con_pg, TABELA_GEOLINK)))$codigo_cnes

DBI::dbDisconnect(con_pg)

cat(sprintf("  %d codigos distintos de unidade encontrados nos casos.\n", length(codigos_casos)))

# ============================================================================
# 2. Unidades do municipio na API publica do DATASUS (coordenada + status)
# ============================================================================
# A API pagina em blocos fixos de 20 (o parametro `limit` nao aumenta o
# tamanho da pagina, so' `offset` avanca). Percorre ate' vir uma pagina vazia.

buscar_estabelecimentos_municipio <- function(codigo_municipio, tamanho_pagina = 20, max_paginas = 500) {
  cat(sprintf("Consultando API do DATASUS para o municipio %s...\n", codigo_municipio))
  todas_paginas <- list()
  offset <- 0

  repeat {
    resp <- httr2::request("https://apidadosabertos.saude.gov.br/cnes/estabelecimentos") |>
      httr2::req_url_query(codigo_municipio = codigo_municipio, limit = tamanho_pagina, offset = offset) |>
      httr2::req_retry(max_tries = 3) |>
      httr2::req_perform()

    pagina <- httr2::resp_body_json(resp)$estabelecimentos
    if (length(pagina) == 0) break

    todas_paginas[[length(todas_paginas) + 1]] <- dplyr::bind_rows(lapply(pagina, function(e) {
      tibble::tibble(
        codigo_cnes   = as.character(e$codigo_cnes %||% NA),
        nome_fantasia = e$nome_fantasia %||% NA_character_,
        razao_social  = e$nome_razao_social %||% NA_character_,
        latitude      = as.numeric(e$latitude_estabelecimento_decimo_grau %||% NA),
        longitude     = as.numeric(e$longitude_estabelecimento_decimo_grau %||% NA),
        bairro        = e$bairro_estabelecimento %||% NA_character_,
        codigo_tipo   = as.integer(e$codigo_tipo_unidade %||% NA),
        # Vem o codigo (ex.: "1244"), apesar do nome do campo na API
        natureza_juridica = as.character(e$descricao_natureza_juridica_estabelecimento %||% NA),
        atende_sus    = e$estabelecimento_faz_atendimento_ambulatorial_sus %||% NA_character_,
        habilitado    = is.null(e$codigo_motivo_desabilitacao_estabelecimento)
      )
    }))

    offset <- offset + tamanho_pagina
    if (offset %/% tamanho_pagina >= max_paginas) {
      warning("Atingiu o limite de seguranca de paginas (", max_paginas, ") -- pode ter parado antes do fim da lista.")
      break
    }
    Sys.sleep(0.1) # nao martelar a API publica
  }

  dplyr::bind_rows(todas_paginas)
}

estabelecimentos <- buscar_estabelecimentos_municipio(MUNICIPIO_CODIGO)

cat(sprintf("  %d estabelecimentos retornados pela API para o municipio %s.\n", nrow(estabelecimentos), MUNICIPIO_CODIGO))

# ============================================================================
# 3. Classifica (rede publica/SUS x demais) e escolhe as unidades do mapa
# ============================================================================
# Publica = natureza juridica de administracao publica (codigos 1xxx: orgaos,
# autarquias e fundacoes publicas federais, estaduais e municipais) ou
# empresa publica / sociedade de economia mista (2011/2038 -- ex.: Hospital
# das Clinicas, gerido pela EBSERH). NAO usar descricao_esfera_administrativa:
# ela reflete a gestao, nao a propriedade (consultorio particular e Unimed
# vem como "MUNICIPAL"). Filantropicos (3xxx -- IMIP, Santa Casa, Hospital
# Portugues) atendem SUS mas nao sao publicos: ficam com "✕", com "atende
# SUS" no hover.

# Rotulos dos tipos de unidade do CNES (lista completa em
# https://apidadosabertos.saude.gov.br/cnes/tipounidades)
TIPOS_UNIDADE <- c(
  "1" = "Posto de saúde", "2" = "Unidade básica de saúde (UBS/USF)", "4" = "Policlínica",
  "5" = "Hospital geral", "7" = "Hospital especializado", "15" = "Unidade mista",
  "20" = "Pronto-socorro geral", "21" = "Pronto-socorro especializado", "22" = "Consultório isolado",
  "32" = "Unidade móvel fluvial", "36" = "Clínica / centro de especialidade",
  "39" = "Apoio diagnóstico e terapia (SADT)", "40" = "Unidade móvel terrestre",
  "42" = "Unidade móvel de urgência", "43" = "Farmácia", "50" = "Vigilância em saúde",
  "60" = "Cooperativa / cessão de trabalhadores", "61" = "Centro de parto normal", "62" = "Hospital-dia",
  "64" = "Central de regulação", "67" = "Laboratório central (LACEN)", "68" = "Gestão em saúde",
  "69" = "Hemoterapia / hematologia", "70" = "Centro de Atenção Psicossocial (CAPS)",
  "71" = "Centro de apoio à saúde da família", "72" = "Atenção à saúde indígena",
  "73" = "Pronto atendimento (UPA)", "74" = "Polo Academia da Saúde", "75" = "Telessaúde",
  "76" = "Regulação médica das urgências", "77" = "Atenção domiciliar", "78" = "Atenção em regime residencial",
  "79" = "Oficina ortopédica", "80" = "Laboratório de saúde pública", "81" = "Regulação do acesso",
  "82" = "Central de captação de órgãos", "83" = "Prevenção e promoção da saúde",
  "84" = "Central de abastecimento", "85" = "Centro de imunização"
)

# Tipos assistenciais da rede publica que entram no mapa mesmo sem notificar
# caso: atencao basica, urgencia, especializada e hospitalar. Ficam de fora
# ambulancias, farmacias, laboratorios, vigilancia, gestao, regulacao,
# academias etc. (entram so' se notificaram algum caso).
TIPOS_REDE_SUS <- c(1, 2, 4, 5, 7, 15, 20, 21, 36, 61, 62, 70, 73)

estabelecimentos <- estabelecimentos |>
  dplyr::mutate(
    publica = dplyr::coalesce(substr(natureza_juridica, 1, 1) == "1" | natureza_juridica %in% c("2011", "2038"), FALSE),
    natureza = dplyr::case_when(
      publica ~ "Pública",
      substr(natureza_juridica, 1, 1) == "3" ~ "Sem fins lucrativos (filantrópica)",
      substr(natureza_juridica, 1, 1) == "4" ~ "Pessoa física",
      TRUE ~ "Privada"
    ),
    natureza = dplyr::if_else(!publica & atende_sus %in% "SIM", paste0(natureza, ", atende SUS"), natureza),
    tipo_unidade = dplyr::coalesce(unname(TIPOS_UNIDADE[as.character(codigo_tipo)]), paste("Tipo CNES", codigo_tipo))
  )

# Coordenada oficial da SESAU pras unidades da rede municipal (camada "Rede
# de Saude de Recife" do ESIG, servidor de mapas da Prefeitura) -- corrige
# unidades que o CNES poe errado (ex.: US 142 USF Mais Bidu Krause, a 4,4 km
# da costa no CNES). Pontos "satelite" que dividem o CNES da unidade
# principal (residencias terapeuticas dos CAPS, Espacos Mae Coruja,
# farmacias, equipes...) sao ignorados quando a unidade principal tambem
# esta la'. O certificado TLS do ESIG nao valida a cadeia completa ("unable
# to verify the first certificate"); a camada e' publica e so' de leitura.
# Se o ESIG estiver fora do ar, segue so' com a coordenada do CNES.

SATELITES_ESIG <- c(
  "RT", "ESPACO MAE CORUJA", "FARMACIA FAMILIA", "FARMACIA DISTRITAL", "CONSULTORIO DE RUA",
  "CONSULTORIO NA RUA", "ACOLHIMENTO CAPS AD", "NDI", "PAC", "AMBULANCIA", "MOTOLANCIA", "eMulti",
  "EMAD", "EMAP", "BASE SAMU", "HELICOPTERO SAMU", "CENTRO DE VACINACAO SHOPPING",
  "CENTRO DE CONVIVENCIA", "ATENDIMENTO DOMICILIAR"
)

cat("Buscando coordenadas oficiais da rede municipal no ESIG...\n")
coord_sesau <- tryCatch({
  url_esig <- paste0(
    "https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/",
    utils::URLencode("Rede_de_Saúde_de_Recife"),
    "/FeatureServer/0/query?where=servico_saude%3D%27S%27&outFields=cnes,tipo_servico&outSR=4326&f=geojson"
  )
  arquivo_esig <- tempfile(fileext = ".geojson")
  curl::curl_download(url_esig, arquivo_esig, handle = curl::new_handle(ssl_verifypeer = FALSE))

  rede <- sf::st_read(arquivo_esig, quiet = TRUE)
  rede$cnes <- as.character(suppressWarnings(as.integer(rede$cnes)))
  rede <- rede |>
    dplyr::filter(!is.na(cnes), !cnes %in% c("0", "9999999")) |>
    dplyr::group_by(cnes) |>
    dplyr::filter(!tipo_servico %in% SATELITES_ESIG | all(tipo_servico %in% SATELITES_ESIG)) |>
    dplyr::slice(1) |>
    dplyr::ungroup()

  xy <- sf::st_coordinates(rede)
  tibble::tibble(codigo_cnes = rede$cnes, lon_sesau = xy[, "X"], lat_sesau = xy[, "Y"])
}, error = function(e) {
  warning("ESIG indisponivel -- usando so' a coordenada do CNES: ", conditionMessage(e))
  tibble::tibble(codigo_cnes = character(), lon_sesau = double(), lat_sesau = double())
})

estabelecimentos <- estabelecimentos |>
  dplyr::left_join(coord_sesau, by = "codigo_cnes") |>
  dplyr::mutate(
    fonte_coordenada = dplyr::if_else(!is.na(lat_sesau), "SESAU (ESIG)", "CNES"),
    latitude = dplyr::coalesce(lat_sesau, latitude),
    longitude = dplyr::coalesce(lon_sesau, longitude)
  ) |>
  dplyr::select(-lat_sesau, -lon_sesau)

cat(sprintf("  %d unidades com coordenada oficial da SESAU.\n", sum(estabelecimentos$fonte_coordenada == "SESAU (ESIG)")))

# Entram no mapa: toda a rede publica assistencial (mesmo sem notificacao) +
# qualquer unidade que aparece como notificadora nos casos
unidades_cnes <- estabelecimentos |>
  dplyr::filter(
    habilitado,
    !is.na(latitude), !is.na(longitude),
    codigo_cnes %in% codigos_casos | (publica & codigo_tipo %in% TIPOS_REDE_SUS)
  ) |>
  dplyr::distinct(codigo_cnes, .keep_all = TRUE) |>
  dplyr::select(codigo_cnes, nome_fantasia, razao_social, latitude, longitude, bairro,
                publica, tipo_unidade, natureza, fonte_coordenada)

cat(sprintf(
  "  %d unidades no mapa: %d da rede publica/SUS (S) e %d outras notificadoras (✕) -- de %d codigos distintos nos casos.\n",
  nrow(unidades_cnes), sum(unidades_cnes$publica), sum(!unidades_cnes$publica), length(codigos_casos)
))

# ============================================================================
# 4. Ajusta as coordenadas ao territorio de Recife
# ============================================================================
# Parte das coordenadas do CNES cai fora de Recife: no mar, no estuario ou em
# outro municipio (ha' coordenadas arredondadas que viram uma "grade" de
# pontos no oceano, varias ambulancias no mesmo ponto a 2,6 km da costa e
# unidades a mais de 100 km). Referencia: uniao dos bairros
# (bairros_recife.gpkg), que e' o que o mapa desenha -- o contorno municipal
# simplificado (recife.gpkg) tem so' 129 vertices e inclui a agua da Bacia do
# Pina, entao nao serve pra separar terra de agua.
#   - dentro dos bairros: mantem a coordenada (da SESAU ou do CNES)
#   - ate' TOLERANCIA_M fora: puxa pro ponto mais proximo da borda (impreci-
#     sao da coordenada ou do poligono -- ex.: USFs na divisa com Jaboatao,
#     a 6-64 m do limite)
#   - mais longe que isso (coordenada errada no CNES): poe no centroide do
#     bairro informado no proprio cadastro (bairro_estabelecimento), marcado
#     em bairro_aproximado pro hover do mapa avisar -- mesma solucao "por
#     enquanto" dos obitos so-SIM (ver docs/DOCUMENTACAO_GRAFICOS.md). Sem
#     bairro reconhecivel, descarta. As duas listas saem no console pra
#     correcao da coordenada no CNES.

TOLERANCIA_M <- 250

bairros <- sf::st_read("inst/app/www/shapes/bairros_recife.gpkg", quiet = TRUE) |>
  sf::st_transform(31985)
territorio <- sf::st_union(bairros)

pontos <- unidades_cnes |>
  sf::st_as_sf(coords = c("longitude", "latitude"), crs = 4326) |>
  sf::st_transform(31985)

# Distancia ate' o territorio (0 = dentro)
dist_m <- as.numeric(sf::st_distance(pontos, territorio))

# Bairro do cadastro -> bairro do shapefile, pelo nome normalizado (mesma
# normalizacao do casamento dos obitos so-SIM no mapa)
normalizar_bairro <- function(x) stringi::stri_trans_general(toupper(trimws(x)), "Latin-ASCII")
idx_bairro <- match(normalizar_bairro(unidades_cnes$bairro), normalizar_bairro(bairros$name_neighborhood))

ajustar <- dist_m > 0 & dist_m <= TOLERANCIA_M
centroide <- dist_m > TOLERANCIA_M & !is.na(idx_bairro)
descartar <- dist_m > TOLERANCIA_M & is.na(idx_bairro)

unidades_cnes$bairro_aproximado <- NA_character_

if (any(ajustar)) {
  # st_nearest_points() devolve uma linha do ponto ate' a borda; o 2o
  # vertice de cada linha e' o ponto mais proximo dentro do territorio.
  linhas <- sf::st_nearest_points(pontos[ajustar, ], territorio)
  sf::st_geometry(pontos)[ajustar] <- sf::st_cast(linhas, "POINT")[seq(2, 2 * sum(ajustar), by = 2)]

  # So' reescreve as linhas ajustadas -- as demais mantem a coordenada
  # original do CNES (a ida e volta de projecao mexe nas ultimas casas).
  coords <- sf::st_coordinates(sf::st_transform(pontos[ajustar, ], 4326))
  unidades_cnes$longitude[ajustar] <- coords[, "X"]
  unidades_cnes$latitude[ajustar] <- coords[, "Y"]
}

if (any(centroide)) {
  # Centroide de cada bairro; num bairro concavo o centroide pode cair fora
  # do proprio bairro (ou na agua) -- nesses usa st_point_on_surface(), que
  # garante um ponto interno.
  geom_bairros <- sf::st_geometry(bairros)
  centroides <- sf::st_centroid(geom_bairros)
  centroide_interno <- diag(sf::st_intersects(centroides, geom_bairros, sparse = FALSE))
  centroides[!centroide_interno] <- sf::st_point_on_surface(geom_bairros[!centroide_interno])

  coords <- sf::st_coordinates(sf::st_transform(centroides[idx_bairro[centroide]], 4326))
  unidades_cnes$longitude[centroide] <- coords[, "X"]
  unidades_cnes$latitude[centroide] <- coords[, "Y"]
  unidades_cnes$bairro_aproximado[centroide] <- bairros$name_neighborhood[idx_bairro[centroide]]
}

cat(sprintf(
  paste0(
    "  %d dentro de Recife, %d ajustadas ate' a borda (<= %d m fora), ",
    "%d no centroide do bairro do cadastro, %d descartadas (sem bairro reconhecivel).\n"
  ),
  sum(dist_m == 0), sum(ajustar), TOLERANCIA_M, sum(centroide), sum(descartar)
))

listar_unidades <- function(sel, titulo) {
  if (!any(sel)) return(invisible())
  cat("\n  ", titulo, "\n", sep = "")
  print(
    data.frame(
      codigo_cnes = unidades_cnes$codigo_cnes[sel],
      unidade = dplyr::coalesce(unidades_cnes$nome_fantasia[sel], unidades_cnes$razao_social[sel]),
      bairro_cnes = unidades_cnes$bairro[sel],
      distancia_km = round(dist_m[sel] / 1000, 1)
    )[order(-dist_m[sel]), ],
    row.names = FALSE
  )
}

listar_unidades(centroide, "Unidades no centroide do bairro (corrigir a coordenada no CNES):")
listar_unidades(descartar, "Unidades descartadas (corrigir a coordenada ou o bairro no CNES para aparecerem no mapa):")

unidades_cnes <- unidades_cnes[!descartar, ]

saveRDS(unidades_cnes, "local/unidades_cnes.rds")

cat("\n✓ Salvo em local/unidades_cnes.rds\n")
