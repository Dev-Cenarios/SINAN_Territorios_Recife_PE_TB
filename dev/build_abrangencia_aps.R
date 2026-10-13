# Gera a camada de areas de abrangencia da Atencao Primaria (APS) do painel
# (inst/app/www/shapes/abrangencia_aps_recife.gpkg) a partir da camada
# oficial da SESAU no ESIG (servidor de mapas da Prefeitura do Recife):
# "Cobertura de Atencao Primaria a Saude do Recife por Unidades de Saude" --
# um poligono por area de abrangencia de USF/USF+/EACS, mais as areas
# descobertas (com a unidade de referencia) e as areas "nao se aplica"
# (sem populacao residente: mata, campus, area militar etc.).
#
# Recorta pela uniao dos bairros do IBGE (a camada do ESIG inclui ~9,7 km2
# de agua, como a malha de bairros da SESAU) e simplifica 2 m pra deixar a
# camada leve no mapa (~400 KB).
#
# Rodar da raiz do projeto quando a SESAU atualizar a territorializacao
# (a versao atual e' de ago/2026). Precisa de acesso a internet; nao precisa
# de banco.

library(sf)
library(dplyr)

sf::sf_use_s2(FALSE)

URL_ESIG <- paste0(
  "https://esigportal2.recife.pe.gov.br/arcgis/rest/services/Hosted/",
  utils::URLencode("Cobertura_de_Atenção_Primária_à_Saúde_do_Recife_por_Unidades_de_Saúde_do_Recife"),
  "/FeatureServer/1/query?where=1%3D1&outFields=cnes,ds,unidade,tipo,cobertura,referencia&outSR=4326&f=geojson"
)

# O certificado TLS do ESIG nao valida a cadeia completa (erro "unable to
# verify the first certificate"); a camada e' publica e so' de leitura.
arquivo_tmp <- tempfile(fileext = ".geojson")
curl::curl_download(URL_ESIG, arquivo_tmp, handle = curl::new_handle(ssl_verifypeer = FALSE))

areas <- sf::st_read(arquivo_tmp, quiet = TRUE)
cat(sprintf("%d poligonos baixados do ESIG.\n", nrow(areas)))

terra <- sf::st_read("inst/app/www/shapes/bairros_recife.gpkg", quiet = TRUE) |>
  sf::st_transform(31985) |>
  sf::st_union()

abrangencia <- areas |>
  sf::st_make_valid() |>
  sf::st_transform(31985) |>
  sf::st_intersection(terra) |>
  sf::st_collection_extract("POLYGON") |>
  dplyr::mutate(
    # Classificacao pelo `tipo` (o campo `cobertura` tem codigos A/T sem
    # documentacao; `tipo` e' inequivoco)
    situacao = dplyr::case_when(
      tipo %in% c("USF", "USFMAIS", "EACS") ~ "Coberta",
      tipo == "ÁREA DESCOBERTA" ~ "Descoberta",
      TRUE ~ "Não se aplica"
    ),
    tipo = dplyr::recode(tipo, "USFMAIS" = "USF+"),
    cnes = dplyr::if_else(situacao == "Coberta", sprintf("%07d", as.integer(cnes)), NA_character_),
    unidade = dplyr::if_else(situacao == "Coberta", unidade, NA_character_),
    referencia = dplyr::if_else(situacao == "Descoberta", referencia, NA_character_),
    ds = as.integer(ds)
  ) |>
  dplyr::group_by(cnes, unidade, tipo, situacao, referencia, ds) |>
  dplyr::summarise(.groups = "drop") |> # junta os pedacos de cada area apos o recorte
  sf::st_simplify(preserveTopology = TRUE, dTolerance = 2) |>
  sf::st_transform(4674) |>
  dplyr::select(cnes, unidade, tipo, situacao, referencia, ds)

cat("\nAreas por situacao:\n")
print(table(abrangencia$situacao))
cat(sprintf("Unidades com area coberta: %d\n", dplyr::n_distinct(abrangencia$cnes, na.rm = TRUE)))

sf::st_write(abrangencia, "inst/app/www/shapes/abrangencia_aps_recife.gpkg", delete_dsn = TRUE, quiet = TRUE)
cat("\n✓ Salvo em inst/app/www/shapes/abrangencia_aps_recife.gpkg\n")
