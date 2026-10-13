if (FALSE) {

  library(tidyverse)
  library(sf)
  recife <- sf::st_read("inst/app/www/shapes/recife.gpkg")

  set.seed(7711)

  cluster_centers <-
    sf::st_sample(recife, size = 4) %>%
    sf::st_coordinates() %>%
    dplyr::as_tibble()

  clustered <- cluster_centers %>%
    dplyr::rowwise() %>%
    dplyr::reframe(X_noise = X + rnorm(140, mean = 0, sd = 0.01),
            Y_noise = Y + rnorm(140, mean = 0, sd = 0.01)
    ) %>%
    sf::st_as_sf(coords = c("X_noise", "Y_noise")) %>%
    dplyr::rename(geom=1) %>%
    `st_crs<-`(sf::st_crs(recife)) %>%
    sf::st_intersection(recife) %>%
    dplyr::add_row(
      sf::st_sample(recife, 240, type="random") %>% sf::st_as_sf() %>% dplyr::rename(geom=1)
    ) %>%
    dplyr::select(geom) %>%
    dplyr::mutate(
      dt_diagnostico = lubridate::ymd("2022-01-01") + as.integer(round(runif(n=nrow(.), min=0, max=1460))),
      dt_notific = pmin(lubridate::ymd("2025-12-31"), dt_diagnostico + as.integer(rnbinom(nrow(.), mu=7, size=6))),
      dt_inicio_tratamento = pmin(lubridate::ymd("2025-12-31"), dt_notific + as.integer(round(abs(rnorm(nrow(.), mean = 19, sd = 10))))),
      situacao = rbinom(nrow(.), size=1, prob = 1 - (as.integer(dt_diagnostico - lubridate::ymd("2022-01-01"))/1460)^1.3) %>%
        factor(levels=c(0,1), labels=c("Em aberto", "Encerrado")),
      numero_notific = as.character(sample(size = nrow(.), x = seq(1700200800, 1900200800, by=212), replace = F)),
      idade = as.integer(abs(round(rnorm(nrow(.), mean=55, sd=14)))),
      sexo = sample(x=c("M", "F"), size=nrow(.), prob = c(0.63, 0.37), replace = T),
      raca_cor = sample(
        x=c("Branca", "Parda", "Preta", "Amarela", "Indígena"),
        size=nrow(.),
        prob = c(0.255, 0.525, 0.217, 0.001, 0.002),
        replace=T
      ),
      comorbidades = sample(
        size=nrow(.),
        x = c("Nenhuma", "HIV", "Diabetes", "Uso de drogas"),
        prob = c(0.4, 0.18, 0.34, 0.08),
        replace=T
      ),
      forma = dplyr::case_when(
        comorbidades == "Nenhuma" ~ sample(size=nrow(.), x=c("Pulmonar", "Extra-pulmonar"), prob=c(0.92, 0.08), replace=T),
        TRUE ~ sample(size=nrow(.), x=c("Pulmonar", "Extra-pulmonar"), prob=c(0.68, 0.32), replace=T)
      ),
      desfecho = dplyr::case_when(
        situacao == "Em aberto" ~ "Em tratamento",
        situacao == "Encerrado" ~ sample(
          x=c("Cura", "Óbito por TB", "Óbito por outras causas",
              "Abandono", "Falência", "TB-DR"),
          size = nrow(.),
          prob = c(0.39, 0.07, 0.15, 0.26, 0.10, 0.03),
          replace = T
        )
      )
    )

  recife %>%
    ggplot(aes(geometry=geom)) +
    geom_sf() +
    geom_sf(data=clustered)

  library(tidygeocoder)

  addresses <-
    sf::st_coordinates(clustered) |>
    dplyr::as_tibble() |>
    reverse_geocode(
      lat = Y, long = X, method = "osm", full_results=T
    )

  enderecos <- addresses |>
    dplyr::mutate(name = ifelse(name == "", NA_character_, name)) |>
    dplyr::rowwise() |>
    dplyr::mutate(endereco = paste(na.omit(c(name, suburb, city)), collapse = ", ")) |>
    dplyr::pull(endereco)

  ?tidygeocoder::reverse_geocode()

  clustered$endereco <- enderecos

  sf::st_write(clustered, dsn = "inst/app/www/shapes/tb_sample_points.gpkg", append = F)
}
