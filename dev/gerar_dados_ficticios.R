# dev/gerar_dados_ficticios.R
# ==================================================================================
# Gera a base FICTICIA de casos de TB (formato SINAN, com os campos do linkage
# com o SIM) e de obitos por TB que so' aparecem no SIM, usadas pela versao de
# demonstracao do painel.
#
# NENHUM registro aqui corresponde a uma pessoa real. Cada caso e' sorteado:
# datas, sexo, idade, raca/cor, comorbidades, populacoes especiais, forma
# clinica, desfecho, causa do obito, unidade notificadora, nome ("PACIENTE
# FICTICIO 00001"), endereco ("RUA FICTICIA ...") e coordenada (ponto
# aleatorio dentro de um setor censitario do bairro, sorteado pela populacao
# do Censo 2022).
#
# O que vem da realidade sao so' ordens de grandeza agregadas, para o painel
# se parecer com o de producao:
#   - total de casos por ano e proporcoes gerais (sexo, idade, desfecho...),
#     arredondados, no bloco PARAMETROS abaixo;
#   - inst/extdata/dados_ficticios/parametros_bairros.csv: taxa media anual
#     de casos por 100 mil hab. em cada bairro, com ruido aleatorio de ~15% e
#     arredondada -- define so' o peso relativo de cada bairro;
#
# A unidade notificadora NAO usa nenhum dado de notificacao real: sai de uma
# regra sobre o cadastro publico de unidades (unidades_cnes.rds, API do CNES/
# DATASUS + rede de saude da Prefeitura) -- parte dos casos e' notificada pela
# USF da area de abrangencia da APS onde o ponto do caso cai (territorializacao
# oficial da SESAU, abrangencia_aps_recife.gpkg), o resto por uma unidade
# sorteada pelo tipo (hospital, policlinica, UPA...). As proporcoes dessa
# regra sao hipoteses da simulacao (bloco PARAMETROS).
#
# Uso (na raiz do projeto):
#   Rscript dev/gerar_dados_ficticios.R
# Regrava inst/extdata/dados_ficticios/sinan_tb_recife_ficticio.csv e
# sim_obitos_orfaos_ficticio.csv. Depois apague a pasta local/ para o painel
# remontar a base na proxima abertura.
# ==================================================================================

suppressMessages({
  library(dplyr)
  library(sf)
})

sf::sf_use_s2(FALSE)
set.seed(20261009)

dir_saida <- "inst/extdata/dados_ficticios"
dir_shapes <- "inst/app/www/shapes"

# ==================================================================================
# PARAMETROS (ordens de grandeza, arredondadas)
# ==================================================================================

anos <- 2012:2023

# Casos notificados por ano de diagnostico (todos os tipos de entrada)
casos_por_ano <- c(1300, 1620, 1680, 1750, 1830, 1890, 1730, 1780, 1660, 1910, 2300, 2420)

# Proporcao de casos em situacao de rua ou privados de liberdade por ano
# (ficam fora dos indicadores por territorio -- coluna INDICADOR = 0)
prop_rua_detento <- c(.09, .08, .11, .09, .12, .16, .13, .17, .17, .19, .21, .16)

# Proporcao de abandono entre os casos de cada ano
prop_abandono <- c(.13, .14, .11, .10, .10, .11, .12, .12, .12, .13, .13, .19)

# Obitos por TB so' no SIM (sem notificacao) por ano -- media do sorteio
obitos_orfaos_por_ano <- c(24, 13, 26, 18, 14, 20, 21, 12, 10, 19, 20, 21)

prop_sem_georref <- 0.004 # endereco nao localizado (fica no centroide do municipio)

# Desfecho final (depois da correcao pelo SIM). Abandono vem por ano, acima.
desfechos <- c("Cura", "Transferência", "Abandono", "Óbito por TB", "Óbito por outras causas",
               "Mudança de diagnóstico", "TB-DR", "Mudança de esquema", "Abandono primário", "Falência")
prop_desfecho <- c(.574, .133, NA, .066, .059, .024, .0084, .0043, .0038, .0005)

# Codigo SITUA_ENCE do SINAN de cada desfecho
cod_situa <- c("Cura" = 1, "Abandono" = 2, "Óbito por TB" = 3, "Óbito por outras causas" = 4,
               "Transferência" = 5, "Mudança de diagnóstico" = 6, "TB-DR" = 7,
               "Mudança de esquema" = 8, "Falência" = 9, "Abandono primário" = 10)

# Idade por sexo (faixas e pesos) -- dentro da faixa, idade uniforme
faixas <- list(c(0, 14), c(15, 24), c(25, 34), c(35, 44), c(45, 54), c(55, 64), c(65, 90))
peso_faixa <- list(
  M = c(350, 2620, 3690, 2690, 2420, 1830, 1320),
  F = c(320, 1120, 1340, 1250, 1130, 910, 900)
)

raca <- c("1" = .175, "2" = .107, "3" = .013, "4" = .54, "5" = .003, "9" = .15, "NA" = .012)
tipo_entrada <- c("1" = .744, "2" = .081, "3" = .087, "4" = .006, "5" = .063, "6" = .022)

outras_comorbidades <- c("HIPERTENSAO", "HEPATITE C", "DOENCA RENAL CRONICA", "CARDIOPATIA",
                         "NEOPLASIA", "DPOC", "ASMA", "DESNUTRICAO")

# Causas basicas (CID-10) no SIM
cid_tb <- c("A169" = .40, "A162" = .11, "A150" = .20, "A153" = .12, "A159" = .09,
            "A199" = .04, "A190" = .01, "A180" = .01, "A181" = .007, "A170" = .013)
cid_aids <- c("B200" = .25, "B201" = .10, "B207" = .20, "B208" = .15, "B209" = .15, "B227" = .05,
              "B342" = .02, "J189" = .05, "A419" = .03)
cid_outras <- c("I219" = .12, "E149" = .11, "C349" = .10, "F102" = .08, "J449" = .07, "K703" = .06,
                "K746" = .05, "I269" = .04, "A419" = .05, "I251" = .04, "C169" = .03, "C159" = .03,
                "J189" = .07, "N189" = .05, "I679" = .04, "B342" = .06)

# Unidade notificadora (hipoteses da simulacao, sem calibracao): proporcao de
# casos notificados pela USF do territorio de residencia; os demais vao para
# uma unidade sorteada pelo tipo, com estes pesos, e uniforme dentro do tipo
prop_notificacao_aps <- .55
peso_tipo_unidade <- c(
  "Hospital geral" = .45, "Hospital especializado" = .15, "Policlínica" = .15,
  "Clínica / centro de especialidade" = .10, "Pronto atendimento (UPA)" = .08,
  "Centro de Atenção Psicossocial (CAPS)" = .03, "Pronto-socorro especializado" = .02,
  "Gestão em saúde" = .02
)

# ==================================================================================
# MALHAS E PARAMETROS POR TERRITORIO
# ==================================================================================

setores <- sf::st_read(file.path(dir_shapes, "setores_recife.gpkg"), quiet = TRUE) |>
  sf::st_transform(31985) |>
  dplyr::filter(!is.na(pop), pop > 0)
limite <- sf::st_read(file.path(dir_shapes, "recife.gpkg"), quiet = TRUE) |> sf::st_transform(31985)

par_bairros <- utils::read.csv(file.path(dir_saida, "parametros_bairros.csv"), fileEncoding = "UTF-8")
bairros <- sf::st_read(file.path(dir_shapes, "bairros_recife.gpkg"), quiet = TRUE) |>
  sf::st_drop_geometry() |>
  dplyr::select(bairro = name_neighborhood, pop) |>
  dplyr::inner_join(par_bairros, by = "bairro") |>
  dplyr::mutate(peso = taxa_media_anual_100mil * pop)

# Cadastro publico das unidades de saude e areas de abrangencia da APS
unidades <- readRDS(file.path(dir_saida, "unidades_cnes.rds")) |>
  dplyr::filter(!is.na(latitude), !is.na(longitude), !is.na(tipo_unidade))
abrangencia <- sf::st_read(file.path(dir_shapes, "abrangencia_aps_recife.gpkg"), quiet = TRUE) |>
  sf::st_transform(4674)

sorteia <- function(n, probs) sample(names(probs), n, replace = TRUE, prob = probs)
sem_acento <- function(x) toupper(stringi::stri_trans_general(x, "Latin-ASCII"))
data_br <- function(d) ifelse(is.na(d), NA_character_, format(d, "%d/%m/%Y"))
data_sim <- function(d) ifelse(is.na(d), NA_integer_, as.integer(format(d, "%d%m%Y")))

# ==================================================================================
# 1. CASOS (SINAN)
# ==================================================================================

casos <- purrr::map_dfr(seq_along(anos), function(i) {
  n <- stats::rpois(1, casos_por_ano[i])
  inicio <- as.Date(sprintf("%d-01-01", anos[i]))
  fim <- as.Date(sprintf("%d-12-31", anos[i]))
  dplyr::tibble(
    ano = anos[i],
    dt_diag = inicio + sample(0:as.integer(fim - inicio), n, replace = TRUE),
    rua_detento = stats::runif(n) < prop_rua_detento[i]
  )
})
n <- nrow(casos)

casos <- casos |>
  dplyr::mutate(
    sem_georref = stats::runif(n) < prop_sem_georref,
    # Detentos e pessoas em situacao de rua: quase sempre homens
    sexo = ifelse(rua_detento, ifelse(stats::runif(n) < .93, "M", "F"),
                  ifelse(stats::runif(n) < .636, "M", "F")),
    tipo_rd = ifelse(rua_detento, ifelse(stats::runif(n) < .78, "detento", "rua"), NA)
  )

# Idade: faixa sorteada pelo sexo, idade uniforme dentro da faixa; detentos
# sao adultos jovens
faixa <- integer(n)
for (s in c("M", "F")) {
  idx <- which(casos$sexo == s)
  faixa[idx] <- sample(seq_along(faixas), length(idx), replace = TRUE, prob = peso_faixa[[s]])
}
lim_inf <- vapply(faixas, `[`, numeric(1), 1)[faixa]
lim_sup <- vapply(faixas, `[`, numeric(1), 2)[faixa]
casos$idade <- as.integer(lim_inf + floor(stats::runif(n) * (lim_sup - lim_inf + 1)))
detento_idx <- which(casos$tipo_rd %in% "detento")
casos$idade[detento_idx] <- as.integer(18 + round(stats::rgamma(length(detento_idx), shape = 4, scale = 3)))

sim_nao <- function(p) ifelse(stats::runif(length(p)) < p, 1L,
                              ifelse(stats::runif(length(p)) < .85, 2L, 9L))

casos <- casos |>
  dplyr::mutate(
    rua = tipo_rd %in% "rua",
    detento = tipo_rd %in% "detento",
    homem = sexo == "M",
    AGRAVAIDS  = sim_nao(ifelse(rua, .20, .105)),
    AGRAVDROGA = sim_nao(dplyr::case_when(rua | detento ~ .50, homem & idade < 45 ~ .15, homem ~ .07, TRUE ~ .05)),
    AGRAVALCOO = sim_nao(dplyr::case_when(rua ~ .60, homem ~ .22, TRUE ~ .10)),
    AGRAVTABAC = sim_nao(dplyr::case_when(rua | detento ~ .45, homem ~ .20, TRUE ~ .13)),
    AGRAVDIABE = sim_nao(dplyr::case_when(idade < 30 ~ .02, idade < 50 ~ .08, TRUE ~ .19) * ifelse(homem, 1, 1.3)),
    AGRAVDOENC = sim_nao(ifelse(rua, .12, .033)),
    AGRAVOUTRA = sim_nao(rep(.10, n)),
    AGRAVOUTDE = ifelse(AGRAVOUTRA == 1, sample(outras_comorbidades, n, replace = TRUE), NA_character_),
    POP_LIBER  = ifelse(detento, 1L, 2L),
    POP_RUA    = ifelse(rua, 1L, 2L),
    POP_SAUDE  = ifelse(stats::runif(n) < .015 & !rua_detento, 1L, 2L),
    POP_IMIG   = ifelse(stats::runif(n) < .002, 1L, 2L),
    BENEF_GOV  = ifelse(stats::runif(n) < .072, 1L, 2L),
    CS_RACA    = suppressWarnings(as.integer(sorteia(n, raca))),
    TRATAMENTO = as.integer(sorteia(n, tipo_entrada)),
    # Reingresso apos abandono mais comum em rua/uso de drogas
    TRATAMENTO = ifelse(TRATAMENTO == 1 & (rua | AGRAVDROGA == 1) & stats::runif(n) < .10, 3L, TRATAMENTO),
    FORMA = ifelse(AGRAVAIDS == 1,
                   as.integer(sorteia(n, c("1" = .65, "2" = .206, "3" = .144))),
                   as.integer(sorteia(n, c("1" = .868, "2" = .106, "3" = .026))))
  )

# ---- Desfecho final ----
# Pesos por pessoa (risco maior de abandono em rua/drogas, de obito em AIDS e
# idosos...), depois ajustados por raking para que a proporcao de cada
# desfecho no ano bata com os parametros.
multiplicador <- function(d) {
  m <- matrix(1, n, length(desfechos), dimnames = list(NULL, desfechos))
  aids <- d$AGRAVAIDS == 1; idoso <- d$idade >= 60
  m[, "Abandono"] <- ifelse(d$rua | d$AGRAVDROGA == 1, 2.2, 1) * ifelse(d$AGRAVALCOO == 1, 1.3, 1) * ifelse(idoso, .6, 1)
  m[, "Abandono primário"] <- m[, "Abandono"]
  m[, "Óbito por TB"] <- ifelse(aids, 2, 1) * ifelse(idoso, 2, 1) * ifelse(d$rua, 1.5, 1)
  m[, "Óbito por outras causas"] <- ifelse(aids, 3, 1) * ifelse(idoso, 2.5, 1)
  m[, "TB-DR"] <- ifelse(d$TRATAMENTO %in% c(2L, 3L), 2.5, 1)
  m[, "Transferência"] <- ifelse(d$detento, 1.8, 1)
  # Pos-obito (diagnostico feito depois da morte): so' desfechos de obito.
  # Entra no raking abaixo, para o total de obitos continuar no parametro.
  pos <- d$TRATAMENTO == 6L
  m[pos, ] <- 0
  m[pos, "Óbito por TB"] <- 85
  m[pos, "Óbito por outras causas"] <- 15
  m
}
mult <- multiplicador(casos)
casos$desfecho <- NA_character_
for (i in seq_along(anos)) {
  idx <- which(casos$ano == anos[i])
  alvo <- prop_desfecho
  alvo[desfechos == "Abandono"] <- prop_abandono[i]
  alvo <- alvo / sum(alvo)
  w <- mult[idx, , drop = FALSE]
  esc <- rep(1, length(desfechos))
  for (it in 1:30) {
    p <- sweep(w, 2, esc, "*"); p <- p / rowSums(p)
    esc <- esc * alvo / colMeans(p)
  }
  p <- sweep(w, 2, esc, "*"); p <- p / rowSums(p)
  casos$desfecho[idx] <- desfechos[apply(p, 1, function(pr) sample.int(length(pr), 1, prob = pr))]
}
pos_obito <- casos$TRATAMENTO == 6L

# Casos ainda em aberto (mais comuns nos diagnosticos recentes)
p_aberto <- dplyr::case_when(
  casos$dt_diag >= as.Date("2023-10-01") ~ .03,
  casos$ano == 2023 ~ .009,
  casos$ano == 2022 ~ .006,
  TRUE ~ .001
)
casos$desfecho[stats::runif(n) < p_aberto & !pos_obito] <- "Em aberto"

# ---- Datas ----
atraso_lognormal <- function(k, mediana, dispersao) round(stats::rlnorm(k, log(mediana), dispersao))
dias_ate_encerrar <- function(d) {
  k <- length(d)
  dplyr::case_when(
    d == "Cura" ~ 165 + round(ifelse(stats::runif(k) < .9, stats::rgamma(k, 2, 1/20), stats::rgamma(k, 2, 1/60))),
    d == "Abandono" ~ atraso_lognormal(k, 135, .9),
    d == "Abandono primário" ~ atraso_lognormal(k, 30, 1),
    d == "Transferência" ~ atraso_lognormal(k, 35, 1.3),
    d == "Mudança de diagnóstico" ~ atraso_lognormal(k, 45, 1.2),
    d %in% c("TB-DR", "Mudança de esquema") ~ atraso_lognormal(k, 100, 1.2),
    d == "Falência" ~ round(stats::runif(k, 180, 400)),
    d %in% c("Óbito por TB", "Óbito por outras causas") ~ ifelse(stats::runif(k) < .25, 0, atraso_lognormal(k, 25, 1.8)),
    TRUE ~ NA_real_
  )
}

data_corte <- as.Date("2023-12-31") # ultima notificacao da base
casos <- casos |>
  dplyr::mutate(
    atraso_notif = dplyr::case_when(
      stats::runif(n) < .55 ~ 0,
      stats::runif(n) < .45 ~ as.numeric(sample(1:7, n, replace = TRUE)),
      TRUE ~ atraso_lognormal(n, 20, 1.2)
    ),
    dt_notif = pmin(dt_diag + atraso_notif, data_corte),
    dt_inicio = dplyr::if_else(stats::runif(n) < .09, as.Date(NA),
                               dt_diag + sample(c(0, 0, 0, 0, 1, 2, 3, 7), n, replace = TRUE)),
    dt_encerra = dt_diag + dias_ate_encerrar(desfecho),
    dt_encerra = dplyr::if_else(TRATAMENTO == 6L & !is.na(dt_encerra), dt_diag + sample(0:5, n, replace = TRUE), dt_encerra)
  )

# ---- SINAN x SIM ----
# Obitos pareados no linkage: o SIM traz a causa basica e manda no desfecho do
# painel (ver fct_db_update.R); o SINAN as vezes registrou outra coisa.
obito_tb <- casos$desfecho == "Óbito por TB"
obito_outras <- casos$desfecho == "Óbito por outras causas"
pareado <- (obito_tb & stats::runif(n) < .69) | (obito_outras & stats::runif(n) < .45)

casos$SITUA_ENCE <- unname(cod_situa[casos$desfecho])
casos$SITUA_ENCE[pareado & obito_tb] <- as.integer(sorteia(sum(pareado & obito_tb), c("3" = .85, "4" = .05, "2" = .04, "1" = .03, "5" = .03)))
casos$SITUA_ENCE[pareado & obito_outras] <- as.integer(sorteia(sum(pareado & obito_outras), c("4" = .80, "3" = .06, "5" = .06, "2" = .05, "1" = .03)))

casos$CAUSABAS <- NA_character_
casos$CAUSABAS[pareado & obito_tb] <- sorteia(sum(pareado & obito_tb), cid_tb)
idx_out <- which(pareado & obito_outras)
casos$CAUSABAS[idx_out] <- ifelse(casos$AGRAVAIDS[idx_out] == 1 & stats::runif(length(idx_out)) < .85,
                                  sorteia(length(idx_out), cid_aids), sorteia(length(idx_out), cid_outras))
casos$dt_obito <- dplyr::if_else(pareado, casos$dt_encerra - sample(0:3, n, replace = TRUE), as.Date(NA))
casos$dt_obito <- pmax(casos$dt_obito, casos$dt_diag)

# ---- Territorio, coordenada e endereco ----
casos$bairro <- NA_character_
com_ponto <- !casos$sem_georref
casos$bairro[com_ponto] <- sample(bairros$bairro, sum(com_ponto), replace = TRUE, prob = bairros$peso)

# Setor censitario dentro do bairro, pela populacao; ponto aleatorio no setor
casos$setor <- NA_character_
for (b in unique(casos$bairro[com_ponto])) {
  idx <- which(casos$bairro == b)
  st <- setores[setores$name_neighborhood == b, ]
  casos$setor[idx] <- sample(st$code_tract, length(idx), replace = TRUE, prob = st$pop)
}
casos <- casos |> dplyr::mutate(id_tmp = dplyr::row_number()) |> dplyr::arrange(setor)
cont <- casos |> dplyr::filter(!is.na(setor)) |> dplyr::count(setor)
st_ord <- setores[match(cont$setor, setores$code_tract), ]
pontos <- sf::st_sample(st_ord, size = cont$n, exact = TRUE)
stopifnot(length(pontos) == sum(cont$n))
xy <- sf::st_coordinates(sf::st_transform(pontos, 4674))
centro <- sf::st_coordinates(sf::st_transform(suppressWarnings(sf::st_point_on_surface(limite)), 4674))

casos$LONGITUDE <- centro[1, "X"]; casos$LATITUDE <- centro[1, "Y"]
com <- !is.na(casos$setor)
casos$LONGITUDE[com] <- round(xy[, "X"], 6)
casos$LATITUDE[com] <- round(xy[, "Y"], 6)
casos <- casos |> dplyr::arrange(id_tmp)

nomes_rua <- c("DAS ACÁCIAS", "DOS IPÊS", "DAS ORQUÍDEAS", "DAS BROMÉLIAS", "DOS CAJUEIROS",
               "DAS MANGUEIRAS", "DOS JASMINS", "DOS GIRASSÓIS", "DAS VIOLETAS", "DAS HORTÊNSIAS",
               "DAS AZALEIAS", "DOS CRAVOS", "DOS LÍRIOS", "DAS MAGNÓLIAS", "DAS PITANGUEIRAS",
               "DAS JAQUEIRAS", "DOS CORAIS", "DAS GAIVOTAS", "DOS SABIÁS", "DOS BEIJA-FLORES",
               "DAS GARDÊNIAS", "DOS COQUEIROS", "DAS CAMÉLIAS", "DOS JACARANDÁS")
tipo_via <- c("RUA" = .7, "AVENIDA" = .1, "TRAVESSA" = .15, "VILA" = .05)
endereco <- paste0(sorteia(n, tipo_via), " FICTÍCIA ", sample(nomes_rua, n, replace = TRUE), ", ",
                   sample(1:1500, n, replace = TRUE))
endereco[casos$detento] <- "UNIDADE PRISIONAL FICTÍCIA"
endereco[casos$rua] <- "SEM ENDEREÇO FIXO (FICTÍCIO)"
endereco[casos$sem_georref] <- "ENDEREÇO NÃO LOCALIZADO (FICTÍCIO)"

# ---- Unidade notificadora (regra sobre o cadastro publico, ver cabecalho) ----
pts_casos <- sf::st_as_sf(casos[, c("LONGITUDE", "LATITUDE")], coords = c("LONGITUDE", "LATITUDE"), crs = 4674)

# USF da area de abrangencia onde o ponto cai; fora de area coberta (ou area
# cuja USF nao esta no cadastro), a UBS/USF mais proxima
area <- vapply(sf::st_intersects(pts_casos, abrangencia), function(i) if (length(i)) i[1] else NA_integer_, integer(1))
cnes_area <- suppressWarnings(as.integer(abrangencia$cnes))[area]
cnes_area[!cnes_area %in% as.integer(unidades$codigo_cnes)] <- NA_integer_
ubs <- unidades |>
  dplyr::filter(tipo_unidade == "Unidade básica de saúde (UBS/USF)") |>
  sf::st_as_sf(coords = c("longitude", "latitude"), crs = 4674)
cnes_ubs_proxima <- as.integer(ubs$codigo_cnes)[sf::st_nearest_feature(pts_casos, ubs)]
cnes_aps <- dplyr::coalesce(cnes_area, cnes_ubs_proxima)

# Demais casos: tipo de unidade sorteado pelos pesos, unidade uniforme no tipo
tipo_sorteado <- sorteia(n, peso_tipo_unidade[names(peso_tipo_unidade) %in% unidades$tipo_unidade])
cnes_tipo <- integer(n)
for (t in unique(tipo_sorteado)) {
  idx <- which(tipo_sorteado == t)
  codigos <- as.integer(unidades$codigo_cnes[unidades$tipo_unidade == t])
  cnes_tipo[idx] <- codigos[sample.int(length(codigos), length(idx), replace = TRUE)]
}
notifica_aps <- stats::runif(n) < prop_notificacao_aps & !casos$sem_georref
id_unidade <- ifelse(notifica_aps, cnes_aps, cnes_tipo)

# ---- Monta a tabela no formato do SINAN ----
# 8 digitos (o SINAN numera com 7): nunca coincide com uma notificacao real
nu_notific <- sample(99000000:99999999, n)
idade_cod <- ifelse(casos$idade == 0, 3000L + sample(1:11, n, replace = TRUE), 4000L + casos$idade)
dt_nasc <- casos$dt_diag - round(casos$idade * 365.25) - sample(0:364, n, replace = TRUE)

sinan <- dplyr::tibble(
  NU_NOTIFIC = as.character(nu_notific),
  DT_NOTIFIC = data_br(casos$dt_notif),
  DT_DIAG = data_br(casos$dt_diag),
  ID_MN_RESI = 261160L,
  ID_UNIDADE = id_unidade,
  NM_PACIENT = NA_character_, # numerado abaixo, na ordem de notificacao
  DT_NASC = data_br(dt_nasc),
  NU_IDADE_N = idade_cod,
  CS_SEXO = casos$sexo,
  CS_RACA = casos$CS_RACA,
  NM_BAIRRO = ifelse(is.na(casos$bairro), NA_character_, sem_acento(casos$bairro)),
  ADDRESS_CORE = endereco,
  ENDERECO_CNEFE = ifelse(casos$rua_detento | casos$sem_georref, NA_character_, sem_acento(endereco)),
  LATITUDE = casos$LATITUDE,
  LONGITUDE = casos$LONGITUDE,
  GEORREFERENCIADO = ifelse(casos$sem_georref, 0L, 1L),
  INDICADOR = ifelse(casos$rua_detento, 0L, 1L),
  TRATAMENTO = casos$TRATAMENTO,
  FORMA = casos$FORMA,
  AGRAVAIDS = casos$AGRAVAIDS, AGRAVALCOO = casos$AGRAVALCOO, AGRAVDIABE = casos$AGRAVDIABE,
  AGRAVDOENC = casos$AGRAVDOENC, AGRAVDROGA = casos$AGRAVDROGA, AGRAVTABAC = casos$AGRAVTABAC,
  AGRAVOUTRA = casos$AGRAVOUTRA, AGRAVOUTDE = casos$AGRAVOUTDE,
  POP_LIBER = casos$POP_LIBER, POP_RUA = casos$POP_RUA, POP_SAUDE = casos$POP_SAUDE,
  POP_IMIG = casos$POP_IMIG, BENEF_GOV = casos$BENEF_GOV,
  DT_INIC_TR = data_br(casos$dt_inicio),
  SITUA_ENCE = ifelse(casos$desfecho == "Em aberto", NA_integer_, as.integer(casos$SITUA_ENCE)),
  DT_ENCERRA = data_br(casos$dt_encerra),
  NUMERODO_SIM = ifelse(pareado, sample(99000000:99499999, n), NA_integer_),
  DTOBITO = data_sim(casos$dt_obito),
  CAUSABAS = casos$CAUSABAS
) |>
  dplyr::arrange(as.Date(DT_NOTIFIC, "%d/%m/%Y"), NU_NOTIFIC) |>
  dplyr::mutate(NM_PACIENT = sprintf("PACIENTE FICTÍCIO %05d", dplyr::row_number()))

utils::write.csv(sinan, file.path(dir_saida, "sinan_tb_recife_ficticio.csv"),
                 row.names = FALSE, na = "", fileEncoding = "UTF-8")

# ==================================================================================
# 2. OBITOS POR TB SO' NO SIM (sem notificacao no SINAN)
# ==================================================================================

orfaos <- purrr::map_dfr(seq_along(anos), function(i) {
  k <- stats::rpois(1, obitos_orfaos_por_ano[i])
  inicio <- as.Date(sprintf("%d-01-01", anos[i]))
  dplyr::tibble(dt_obito = inicio + sample(0:364, k, replace = TRUE))
})
k <- nrow(orfaos)
bairro_orfao <- sample(bairros$bairro, k, replace = TRUE, prob = bairros$peso)
baires <- sem_acento(bairro_orfao)
# O SIM abrevia "ILHA" como "I." em parte dos registros; alguns ficam sem bairro valido
abrevia <- grepl("^ILHA ", baires) & stats::runif(k) < .5
baires[abrevia] <- sub("^ILHA ", "I. ", baires[abrevia])
baires[stats::runif(k) < .03] <- "IGNORADO"

sim_orfaos <- dplyr::tibble(
  NUMERODO = sample(99500000:99999999, k),
  DTOBITO = data_sim(orfaos$dt_obito),
  CAUSABAS = sorteia(k, c("A169" = .55, "A162" = .17, "A150" = .12, "A159" = .08, "A199" = .045, "A180" = .02, "A170" = .015)),
  BAIRES = baires
) |>
  dplyr::arrange(NUMERODO)

utils::write.csv(sim_orfaos, file.path(dir_saida, "sim_obitos_orfaos_ficticio.csv"),
                 row.names = FALSE, na = "", fileEncoding = "UTF-8")

# ==================================================================================
# Resumo
# ==================================================================================

cat("Casos ficticios:", nrow(sinan), "| obitos so' no SIM:", nrow(sim_orfaos), "\n")
print(table(ano = casos$ano))
print(round(prop.table(table(casos$desfecho)), 3))
cat("Taxa media anual (casos com endereco, fora rua/detento) por 100 mil hab.:",
    round(1e5 * sum(!casos$rua_detento & !casos$sem_georref) / sum(bairros$pop) / length(anos), 1), "\n")
