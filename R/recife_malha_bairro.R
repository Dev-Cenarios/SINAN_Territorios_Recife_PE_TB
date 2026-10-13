if (FALSE) {
  library(tidyverse)
  library(geobr)
  library(sf)

  bair_re <- read_neighborhood(year=2022, simplified = F) %>%
    dplyr::filter(code_muni == 2611606)

  setor_re <- read_census_tract(code_tract = 2611606, year = 2022, simplified = F)

  bair_re %>% sf::st_write()

  bair_re %>% dplyr::pull(geom) %>% plot()

  library(duckdb)

  con <- DBI::dbConnect(duckdb::duckdb(), "local/censo_aux.duckdb", read_only=T)

  pop_setor <- con %>% DBI::dbGetQuery("select id_setor_censitario, pessoas from tb_setor_censitario") %>% dplyr::as_tibble()
  con %>% DBI::dbDisconnect(shutdown=T)

  setor_re

  setor_re <- setor_re %>%
    dplyr::mutate(code_tract = as.character(code_tract)) %>%
    dplyr::left_join(
      pop_setor, by=c("code_tract" = "id_setor_censitario")
    )

  pop_bairros <- setor_re %>%
    sf::st_drop_geometry() %>%
    dplyr::summarise(
      pop = sum(pessoas),
      .by=c(name_neighborhood, code_neighborhood)
    )

  bair_re <- bair_re %>%
    dplyr::left_join(
      pop_bairros %>% dplyr::select(code_neighborhood, pop),
      by = "code_neighborhood"
    )

  bair_re %>%
    ggplot(aes(geometry=geom)) +
    geom_sf(aes(fill = pop)) +
    scale_fill_distiller(palette = "Blues", direction = 1)

  bair_re <- bair_re %>%
    dplyr::select(code_muni, code_neighborhood, name_neighborhood, code_subdistrict, name_subdistrict, pop, geom) %>%
    dplyr::mutate(area_km2 = as.numeric(sf::st_area(geom))/1e6,
                  densidade = pop/(1e6*area_km2)) %>%
    dplyr::relocate(geom, .after = dplyr::everything())

  setor_re <- setor_re %>%
    dplyr::mutate(densidade = pessoas/(1e6*area_km2)) %>%
    dplyr::select(code_tract, code_neighborhood, name_neighborhood, code_subdistrict, name_subdistrict, pop=pessoas, area_km2, densidade, geom)

  bair_re %>% sf::st_write("inst/app/www/shapes/bairros_recife.gpkg")
  setor_re %>% sf::st_write("inst/app/www/shapes/setores_recife.gpkg")

}
