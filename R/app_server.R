#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @noRd
app_server <- function(input, output, session, chosen_municipio) {
  # Your application server logic

  sf::sf_use_s2(F)

  # Base local montada/atualizada a partir da fonte configurada -- dados
  # ficticios por padrao, ou reais com PAINEL_DADOS_REAIS_DIR (ver
  # prepara_base() em R/fct_db_update.R). O app_ui() ja' chamou antes de
  # desenhar a pagina; aqui normalmente so' confere que nada mudou.
  prepara_base()

  cache_trigger <- shiny::reactiveVal(0)

  # Painel único e independente para Recife - PE (sem seletor de município na UI)
  mod_municipio_server("municipio_1", shiny::reactive("recife"), cache_trigger)

  # Aviso de dados ficticios ao abrir o painel (so' quando a base carregada e'
  # a ficticia)
  if (dados_sao_ficticios()) {
    shiny::showModal(
      shiny::modalDialog(
        title = htmltools::tagList(shiny::icon("triangle-exclamation"), " Versão de demonstração com dados fictícios"),
        htmltools::p(htmltools::HTML(paste0(
          "Este painel é uma vitrine do <b>SINAN Territórios: Recife-PE</b>, do Programa",
          " Cenários (UnB). A versão real roda com dados sigilosos de pacientes,",
          " em ambiente seguro da Secretaria de Saúde."
        ))),
        htmltools::p(htmltools::HTML(paste0(
          "<b>Todos os dados exibidos aqui são fictícios.</b> Casos, óbitos, nomes, endereços,",
          " datas, coordenadas e unidades notificadoras foram gerados por simulação e não",
          " correspondem a pessoas reais."
        ))),
        htmltools::p(
          "A simulação foi calibrada para reproduzir a ordem de grandeza dos indicadores de",
          " tuberculose de Recife entre 2012 e 2023 (taxa de casos por bairro, perfil dos",
          " pacientes e desfechos do tratamento). Os números não devem ser usados para",
          " análise ou tomada de decisão."
        ),
        easyClose = TRUE,
        footer = shiny::modalButton("Entendi")
      )
    )
  }

}
