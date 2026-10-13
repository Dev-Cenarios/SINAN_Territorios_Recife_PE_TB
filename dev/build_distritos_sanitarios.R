# Gera a malha de Distritos Sanitarios (DS) do painel
# (inst/app/www/shapes/distritos_sanitarios_recife.gpkg) a partir da divisao
# oficial da SESAU/Prefeitura do Recife: shapefile "Distrito_Sanitário
# 24-09-14" (94 bairros, cada um com o codigo do DS em CRPAAACODI) --
# recebido por e-mail em set/2026, nao versionado neste repositorio.
#
# Por que nao usar direto o poligono de DS da SESAU (Distrito_per.shp): os
# limites da SESAU nao coincidem com os bairros do IBGE que o painel usa
# (bairros_recife.gpkg) e incluem ~9 km2 de agua (Bacia do Pina, faixa da
# praia). Aqui cada bairro do IBGE recebe o DS da SESAU pelo nome e cada DS
# e' a uniao dos seus bairros -- assim os limites de DS batem exatamente com
# os dos bairros no mapa, e a populacao do DS (Censo 2022) e' a soma dos
# bairros, o mesmo denominador do indicador por bairro. O Distrito_per.shp
# da SESAU e' exatamente a uniao dos bairros do arquivo acima, entao a
# composicao dos DS e' a mesma.
#
# Rodar da raiz do projeto, uma vez (ou quando a divisao de DS mudar).
# Defina `arquivo_sesau` antes de rodar se o shapefile estiver em outro lugar.

library(sf)
library(dplyr)

if (!exists("arquivo_sesau")) arquivo_sesau <- "Distrito_Sanitário 24-09-14.shp"

sf::sf_use_s2(FALSE) # uniao planar -- mantem os vertices dos bairros intactos

normalizar <- function(x) stringi::stri_trans_general(toupper(trimws(x)), "Latin-ASCII")

# Nomes que diferem entre SESAU e IBGE (SESAU -> IBGE, ja normalizados)
alias_bairro <- c("SITIO DOS PINTOS" = "SITIO DOS PINTOS - SAO BRAS")

sesau <- sf::st_read(arquivo_sesau, quiet = TRUE) |>
  sf::st_drop_geometry() |>
  dplyr::transmute(
    bairro_norm = normalizar(EBAIRRNOME),
    bairro_norm = dplyr::coalesce(alias_bairro[bairro_norm], bairro_norm),
    cod_ds = as.integer(CRPAAACODI)
  )

bairros <- sf::st_read("inst/app/www/shapes/bairros_recife.gpkg", quiet = TRUE)
bairros$bairro_norm <- normalizar(bairros$name_neighborhood)

sem_ds <- setdiff(bairros$bairro_norm, sesau$bairro_norm)
sem_bairro <- setdiff(sesau$bairro_norm, bairros$bairro_norm)
if (length(sem_ds) > 0 || length(sem_bairro) > 0) {
  stop(
    "Bairros sem correspondencia entre IBGE e SESAU -- adicione em alias_bairro.\n",
    "  So' no IBGE: ", paste(sem_ds, collapse = "; "), "\n",
    "  So' na SESAU: ", paste(sem_bairro, collapse = "; ")
  )
}

distritos <- bairros |>
  dplyr::left_join(sesau, by = "bairro_norm") |>
  dplyr::group_by(cod_ds) |>
  dplyr::summarise(
    n_bairros = dplyr::n(),
    pop = sum(pop),
    bairros = paste(sort(name_neighborhood), collapse = ", ")
  ) |>
  dplyr::mutate(
    ds = paste("DS", as.character(utils::as.roman(cod_ds))),
    nome = paste("Distrito Sanitário", as.character(utils::as.roman(cod_ds)))
  ) |>
  dplyr::select(cod_ds, ds, nome, n_bairros, pop, bairros)

print(sf::st_drop_geometry(distritos) |> dplyr::select(-bairros))
cat("Populacao total:", sum(distritos$pop), "\n")

sf::st_write(distritos, "inst/app/www/shapes/distritos_sanitarios_recife.gpkg", delete_dsn = TRUE, quiet = TRUE)
cat("\n✓ Salvo em inst/app/www/shapes/distritos_sanitarios_recife.gpkg\n")
