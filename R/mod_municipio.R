# UI ----


filtro_sexo_default <- c("F", "M", "I")
filtro_idade_default <- as.integer(c(0, 120))
filtro_raca_cor_default <- c("Branca", "Preta", "Amarela", "Parda", "Indígena", "Ignorado")
filtro_tipo_entrada_default <- c("Caso Novo", "Recidiva", "Reingresso após abandono", "Não Sabe", "Transferência", "Pós-óbito")
filtro_comorbidades_default <- NULL
filtro_populacao_especial_default <- NULL
filtro_desfecho_default <- c("Cura", "Em aberto", "Abandono", "Abandono primário", "Falência", "TB-DR", "Mudança de diagnóstico", "Mudança de esquema", "Transferência", "Óbito por outras causas", "Óbito por TB")
filtro_forma_default <- c("Pulmonar", "Extrapulmonar", "Pulmonar + Extrapulmonar")

# Periodo inicial do filtro de datas: os 6 meses (de calendario) que terminam
# na ultima data de notificacao da base -- a mesma "data de atualizacao" do
# cabecalho --, que tambem e' o limite do calendario. Acompanha a base
# carregada (ficticia ou real). Sem base (ex.: teste da UI), termina hoje.
periodo_default <- function() {
  ultima <- tryCatch(
    max(carrega_casos()$dt_notificacao, na.rm = TRUE),
    error = function(e) NA, warning = function(w) NA
  )
  if (is.na(ultima) || !is.finite(ultima)) ultima <- Sys.Date()
  c(lubridate::floor_date(ultima, "month") - lubridate::period(5, "months"), ultima)
}

# O periodo so' vale pro painel quando a escolha termina: enquanto algum
# calendario do filtro de datas estiver aberto (ou o usuario digitando), a
# mudanca fica guardada; quando ele fecha, vai pro servidor como
# input$periodo_aplicado. Antes cada data escolhida recalculava tudo na hora
# -- trocar inicio e fim do periodo custava dois recalculos (e digitar uma
# data, um por tecla que formasse uma data valida).
js_periodo_aplicado <- "
(function() {
  var id = '%s', destino = '%s';
  var pendente = null, enviado = null, aberto = false, timer = null;
  function agenda() {
    clearTimeout(timer);
    timer = setTimeout(function() {
      if (aberto || pendente === null) return;
      var valor = JSON.stringify(pendente);
      if (valor === enviado) return;
      enviado = valor;
      Shiny.setInputValue(destino + ':shiny.date', pendente);
    }, 600);
  }
  $(document).on('shiny:inputchanged', function(e) {
    if (e.name === id) { pendente = e.value; agenda(); }
  });
  $(document).on('show', '#' + id + ' input', function() { aberto = true; clearTimeout(timer); });
  $(document).on('hide', '#' + id + ' input', function() { aberto = false; agenda(); });
})();
"

# O leaflet do R destroi e recria o mapa a cada render, e no Leaflet 1.3 um
# redesenho de canvas ja' agendado dispara depois do canvas destruido
# ("Cannot read properties of undefined (reading 'clearRect')" no console --
# inofensivo, mas polui). Ignora esse redesenho, como o proprio Leaflet
# passou a fazer a partir da 1.4. Roda na carga da pagina (o Leaflet ja'
# veio no <head>), antes do primeiro mapa: um redesenho agendado antes da
# correcao guardaria a funcao antiga.
js_canvas_redesenho <- "
if (window.L && L.Canvas && !L.Canvas.prototype._ignoraRedesenhoSemCanvas) {
  var redesenhaCanvas = L.Canvas.prototype._redraw;
  L.Canvas.prototype._redraw = function() {
    if (!this._ctx) { this._redrawRequest = null; return; }
    return redesenhaCanvas.apply(this, arguments);
  };
  L.Canvas.prototype._ignoraRedesenhoSemCanvas = true;
}
"

# Ordem de desenho no canvas do mapa -- a mesma dos panes de antes do canvas:
# indicador (ou contorno de Recife) < areas da APS < contorno dos DS < casos
# < circulos de hover das unidades (S e ✕). No canvas a ordem e' a ordem em
# que as camadas entram no mapa, e as camadas sao atualizadas separadamente
# (leafletProxy, ver output$main_map): um indicador redesenhado ou a APS
# religada entrariam por cima dos casos -- escondendo os pontos (indicador a
# 70% de opacidade) e roubando o hover deles. Registrado como metodo do
# leaflet: o servidor chama (leaflet::invokeMethod) depois de cada
# atualizacao, e o mapa, a cada camada religada no controle. Manda pro fundo
# so' as malhas (na ordem inversa, pra manter a ordem entre elas -- o halo
# branco dos DS continua embaixo da linha) e traz pra frente so' os circulos
# das unidades, sem mexer nos casos.
js_ordena_camadas <- "
if (window.LeafletWidget && !LeafletWidget.methods.ordenaCamadas) {
  LeafletWidget.methods.ordenaCamadas = function() {
    var map = this;
    var camadas = function(grupos, tipo) {
      var lista = [];
      grupos.forEach(function(nome) {
        var grupo = map.layerManager.getLayerGroup(nome, false);
        if (!grupo) return;
        grupo.eachLayer(function(l) {
          if (l instanceof tipo && map.hasLayer(l)) lista.push(l);
        });
      });
      return lista;
    };
    var aoFundo = function(grupos, tipo) {
      var lista = camadas(grupos, tipo);
      for (var i = lista.length - 1; i >= 0; i--) lista[i].bringToBack();
    };
    aoFundo(['Distritos Sanitários'], L.Polygon);
    aoFundo(['Áreas de abrangência (APS)'], L.Polygon);
    aoFundo(['Indicador por território', 'Recife'], L.Polygon);
    camadas(['Rede SUS (S)', 'Outras notificadoras (✕)'], L.CircleMarker).forEach(function(l) { l.bringToFront(); });
  };
}
"

reactable_idioma <- reactable::reactableLang(
  sortLabel = "Ordenar {name}",
  filterLabel = "Filtrar {name}",
  searchPlaceholder = "Buscar",
  searchLabel = "Buscar",
  noData = "Nenhum registro encontrado",
  pageNext = "Próxima",
  pagePrevious = "Anterior",
  pageNumbers = "{page} de {pages}",
  pageInfo = "{rowStart}\u2013{rowEnd} de {rows} registros",
  pageSizeOptions = "Mostrar {rows}",
  pageNextLabel = "Próxima",
  pagePreviousLabel = "Anterior",
  pageNumberLabel = "Página {page}",
  pageJumpLabel = "Ir para página",
  pageSizeOptionsLabel = "Registros por página",
  groupExpandLabel = "Abrir grupo",
  detailsExpandLabel = "Mostrar detalhes",
  selectAllRowsLabel = "Selecionar todos",
  selectAllSubRowsLabel = "Selecionar todos do grupo",
  selectRowLabel = "Selecionar linha"
)


#' municipio UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
#' @importFrom magrittr %>%
mod_municipio_ui <- function(id) {
  ns <- shiny::NS(id)
  periodo <- periodo_default()
  htmltools::tagList(
    shiny::fluidRow(
      bs4Dash::column(2,
                      ## General input ----
                      htmltools::h1("Panorama geral", style = "font-weight: 600"),
                      shiny::uiOutput(ns("periodo_ui")),
                      shiny::dateRangeInput(
                        ns("periodo"),
                        label = htmltools::HTML("Filtro de data de diagnóstico"),
                        start = periodo[1],
                        end = periodo[2],
                        min = lubridate::ymd("1939-01-01"),
                        max = periodo[2],
                        format = "dd/mm/yyyy",
                        startview = "month",
                        language = "pt-BR",
                        separator = "até",
                        width = "100%"
                      ),
                      htmltools::tags$script(htmltools::HTML(
                        sprintf(js_periodo_aplicado, ns("periodo"), ns("periodo_aplicado"))
                      )),
                      bs4Dash::actionButton(
                        ns("mostrar_filtros"),
                        label = "Abrir filtros",
                        icon = shiny::icon("plus"),
                        status = "secondary",
                        size = "xs",
                        width="60%"
                      ),
                      align="center", style="z-index:1002;"
      ),
      ## Boxes ----
      bs4Dash::column(
        10,
        shiny::fluidRow(
          bs4Dash::column(
            3,
            bs4Dash::bs4ValueBoxOutput(ns("box_total"),
                                       width = NULL
            )
          ),
          bs4Dash::column(3,
                          bs4Dash::bs4ValueBoxOutput(ns("box_aberto_6m"),
                                                     width = NULL
                          )
          ),
          bs4Dash::column(
            3,
            bs4Dash::bs4ValueBoxOutput(ns("box_cura"),
                                       width = NULL
            )
          ),
          bs4Dash::column(
            3,
            bs4Dash::bs4ValueBoxOutput(ns("box_mortalidade"),
                                       width = NULL
            )
          )
        ),
        shiny::fluidRow(
          bs4Dash::column(
            3,
            bs4Dash::bs4ValueBoxOutput(ns("box_abandono"),
                                       width = NULL
            )
          ),
          bs4Dash::column(
            3,
            bs4Dash::bs4ValueBoxOutput(ns("box_tbdr"),
                                       width = NULL
            )
          ),
          bs4Dash::column(
            3,
            bs4Dash::bs4ValueBoxOutput(ns("box_situacao_rua"),
                                       width = NULL
            )
          ),
          bs4Dash::column(
            3,
            bs4Dash::bs4ValueBoxOutput(ns("box_privado_liberdade"),
                                       width = NULL
            )
          )
        )
      )
    ),
    ## Filter boxes ----
    shiny::fluidRow(
      bs4Dash::column(12,
                      bs4Dash::box(
                        id = ns("box_filtro"),
                        title = "Filtros",
                        width = NULL,
                        status = "primary",
                        solidHeader = F,
                        closable = T,
                        collapsible = F,
                        icon = shiny::icon("sliders"),
                        shiny::fluidRow(
                          bs4Dash::column(3,
                                          shinyWidgets::checkboxGroupButtons(
                                            ns("filtro_sexo"),
                                            label = "Sexo",
                                            choiceNames = c("Feminino", "Masculino", "Ignorado"),
                                            choiceValues = c("F", "M", "I"),
                                            selected = filtro_sexo_default,
                                            checkIcon = list(
                                              yes = shiny::icon("check")
                                            ),
                                            status = "info"
                                          ),
                                          shiny::sliderInput(
                                            ns("filtro_idade"),
                                            label = "Idade (anos)",
                                            min = 0,
                                            max = 120,
                                            value = filtro_idade_default,
                                            step = 1
                                          )
                                          ),
                          bs4Dash::column(
                            3,
                            shinyWidgets::pickerInput(
                              ns("filtro_raca_cor"),
                              label = "Raça/cor",
                              choices = c("Branca", "Preta", "Amarela", "Parda", "Indígena", "Ignorado"),
                              selected = filtro_raca_cor_default,
                              multiple = TRUE,
                              options = shinyWidgets::pickerOptions(noneSelectedText = "Selecione raça/cor...",
                                                      noneResultsText = "Nenhum resultado encontrado.",
                                                      deselectAllText = "Limpar seleção",
                                                      selectAllText = "Selecionar tudo",
                                                      actionsBox = TRUE
                              )
                            ),
                            shinyWidgets::pickerInput(
                              ns("filtro_tipo_entrada"),
                              label = "Tipo de Entrada",
                              choices = c("Caso Novo", "Recidiva", "Reingresso após abandono",
                                          "Não Sabe", "Transferência", "Pós-óbito"),
                              selected = filtro_tipo_entrada_default,
                              multiple = T,
                              options = shinyWidgets::pickerOptions(noneSelectedText = "Selecione tipo de entrada...",
                                                      noneResultsText = "Nenhum resultado encontrado.",
                                                      deselectAllText = "Limpar seleção",
                                                      selectAllText = "Selecionar tudo",
                                                      actionsBox = TRUE
                              )
                            )
                          ),
                          bs4Dash::column(
                            3,
                            shinyWidgets::pickerInput(
                              ns("filtro_comorbidades"),
                              label = "Comorbidades",
                              choices = c("AIDS", "Alcoolismo", "Diabetes", "Doença mental",
                                          "Uso de drogas ilícitas", "Tabagismo"),
                              selected = filtro_comorbidades_default,
                              multiple = TRUE,
                              options = shinyWidgets::pickerOptions(noneSelectedText = "Selecione comorbidade...",
                                                      noneResultsText = "Nenhum resultado encontrado.",
                                                      deselectAllText = "Limpar seleção",
                                                      selectAllText = "Selecionar tudo",
                                                      maxOptions = 1,
                                                      actionsBox = FALSE
                              )
                            ),
                            shinyWidgets::pickerInput(
                              ns("filtro_populacao_especial"),
                              label = "População especial",
                              choices = c("Privado de liberdade", "Situação de rua",
                                          "Profissional de Saúde", "Imigrante",
                                          "Beneficiário programa de transferência de renda"),
                              selected = filtro_populacao_especial_default,
                              multiple = TRUE,
                              options = shinyWidgets::pickerOptions(noneSelectedText = "Selecione população específica...",
                                                      noneResultsText = "Nenhum resultado encontrado.",
                                                      deselectAllText = "Limpar seleção",
                                                      selectAllText = "Selecionar tudo",
                                                      maxOptions = 1,
                                                      actionsBox = FALSE
                              )
                            ),
                            bs4Dash::actionButton(
                              ns("filtro_clear"),
                              htmltools::strong("Limpar filtros"),
                              icon = shiny::icon("undo"),
                              width = "100%",
                              status = "secondary"
                            )
                          ),
                          bs4Dash::column(
                            3,
                            shinyWidgets::pickerInput(
                              ns("filtro_desfecho"),
                              label = "Desfecho",
                              choices = c(
                                "Cura", "Em aberto",
                                "Abandono", "Abandono primário", "Falência", "TB-DR",
                                "Mudança de diagnóstico", "Mudança de esquema", "Transferência",
                                "Óbito por outras causas", "Óbito por TB"
                              ),
                              selected = filtro_desfecho_default,
                              multiple = TRUE,
                              options = shinyWidgets::pickerOptions(noneSelectedText = "Selecione desfecho...",
                                                                    noneResultsText = "Nenhum resultado encontrado.",
                                                                    deselectAllText = "Limpar seleção",
                                                                    selectAllText = "Selecionar tudo",
                                                                    actionsBox = TRUE
                            )),
                            shinyWidgets::pickerInput(
                              ns("filtro_forma"),
                              label = "Forma",
                              choices = c("Pulmonar", "Extrapulmonar", "Pulmonar + Extrapulmonar"),
                              selected = filtro_forma_default,
                              multiple = TRUE,
                              options = shinyWidgets::pickerOptions(noneSelectedText = "Selecione forma...",
                                                                    noneResultsText = "Nenhum resultado encontrado.",
                                                                    deselectAllText = "Limpar seleção",
                                                                    selectAllText = "Selecionar tudo",
                                                                    actionsBox = FALSE
                              )
                            ),
                            bs4Dash::actionButton(
                              ns("filtro_update"),
                              htmltools::strong("Aplicar filtros"),
                              icon = shiny::icon("refresh"),
                              width = "100%",
                              status = "primary"
                                 ), style="z-index:1002;"
                            )
                        )
                      )
                      ),
      id = ns("box_filtro_row")
    ) |> shinyjs::hidden(),
    #shiny::hr(),
    ## Leaflet Map ----
    shiny::fluidRow(
      bs4Dash::column(12,
                      bs4Dash::box(
                        title = htmltools::strong("Mapa de casos"),
                        width = NULL,
                        status = "primary",
                        solidHeader = TRUE,
                        icon = shiny::icon("map-pin"),
                        shiny::fluidRow(
                          bs4Dash::column(4,

                                          htmltools::h3("Distribuição dos desfechos", style = "font-weight: 600"),

                                          htmltools::p("Selecione quais desfechos a serem mostrados no mapa", style = "color: gray; font-size: 14px"),

                                          reactable::reactableOutput(ns("casos_table")),

                                          htmltools::hr(),

                                          htmltools::h3("Indicadores por território", style = "font-weight: 600"),

                                          shinyWidgets::prettyCheckbox(ns("show_indicador_bairro"),
                                                                       label = "Mostrar indicador no mapa",
                                                                       status = "info",
                                                                       icon = shiny::icon("check"),
                                                                       value = TRUE),
                                          shiny::radioButtons(
                                            ns("nivel_territorial"),
                                            label = "Recorte",
                                            choices = c("Bairro" = "bairro", "Distrito Sanitário" = "ds"),
                                            selected = "bairro",
                                            inline = TRUE
                                          ),
                                          shiny::selectInput(
                                            ns("indicador_bairro"),
                                            label = "Indicador",
                                            choices = c(
                                              "inc", "mort", "let", "prop_cura", "prop_aband"
                                            ) |> setNames(
                                              nm = c(
                                                "Incidência (casos/população)",
                                                "Mortalidade (óbitos por TB/população)",
                                                "Letalidade (óbitos por TB/casos encerrados)",
                                                "Proporção de cura (curados/casos encerrados)",
                                                "Proporção de abandono (abandono/casos encerrados)"
                                              )
                                            ), selected = "inc"
                                          )

                                 ),
                          bs4Dash::column(8,
                                          shiny::uiOutput(ns("main_map_title")),
                                          shiny::uiOutput(ns("main_map_subtitle")),
                                 # div so' pro spinner (badges_inline.css) -- no mapa, pelo
                                 # estado "ocupado" do servidor: as camadas sao atualizadas
                                 # por leafletProxy, a saida nao recalcula
                                 htmltools::div(
                                   class = "saida-carregando saida-carregando-ocupado",
                                   leaflet::leafletOutput(ns("main_map"), height = 720)
                                 ),
                                 htmltools::tags$script(htmltools::HTML(js_canvas_redesenho, js_ordena_camadas))
                                 )
                        )
                      ),
      )
    ),

    shiny::fluidRow(
      bs4Dash::column(12,
                      bs4Dash::box(
                        title = htmltools::strong("Tabela de casos"),
                        width = NULL,
                        status = "primary",
                        solidHeader = TRUE,
                        icon = shiny::icon("table"),
                        # div so' pro spinner enquanto recalcula (badges_inline.css)
                        htmltools::div(
                          class = "saida-carregando",
                          reactable::reactableOutput(ns("tabela_casos"))
                        )
                      )
                      )
    )

  )
}

# Identidade visual dos paineis do Programa Cenarios (guia "Documentacao --
# ID visual para paineis", cenarios.unb.br). Mesmos tokens --cen-* de
# inst/app/badges_inline.css.
cores_cen <- list(
  azul = "#3891C0", azul_acao = "#0E7BA8", azul_texto = "#00638C",
  terra = "#B67355", terra_texto = "#8C4A2A",
  tinta = "#12222B", tinta_2 = "#4A4A4A", tinta_3 = "#7A8B95", linha = "#D8E3EA",
  ok = "#1F6F4A", atencao = "#8A6100", grave = "#C24B12", critico = "#A32235",
  # series de dados 1 a 8, nesta ordem
  series = c("#3891C0", "#C0663C", "#6C5CA8", "#5A9E2E", "#8E3B46", "#B08A1E", "#3F4E9E", "#1B9AAA"),
  sequencial = c("#89B8D5", "#5BA1CA", "#2F8AB8", "#006E9C", "#005477", "#003A56"),
  divergente = c("#822F00", "#BE643A", "#DBA289", "#EDEAE6", "#89B8D5", "#2F8AB8", "#005477")
)

# Paletas do mapa de indicadores por territorio -- excecao ao guia pedida
# pela equipe: mantidas as paletas ColorBrewer que o painel usava antes da
# adequacao a identidade visual (o resto do painel segue o guia).
paletas_indicador <- c(
  inc = "YlOrRd",       # incidencia (classes por quantil)
  mort = "YlOrRd",      # mortalidade
  let = "BuPu",         # letalidade
  prop_cura = "RdYlGn", # proporcao de cura
  prop_aband = "Oranges" # proporcao de abandono
)
navy_recife <- "#12346B" # cor tema de Recife (barras e contorno dos DS)

# Cores dos 11 desfechos -- fonte unica pra ficha do caso, tabela de
# distribuicao, tabela de casos e mapa (antes duplicadas em 4 lugares).
# Cores de estado do guia onde ha' sentido clinico (cura = adequado, obito
# por TB = critico, abandono = grave, abandono primario = atencao); series
# do guia nos demais, escolhidas pra manter os 11 distinguiveis no mapa.
# A ordem aqui e' a da legenda do mapa.
cores_desfecho <- c(
  "Cura"                    = cores_cen$ok,
  "Em aberto"               = cores_cen$series[1], # azul
  "Abandono"                = cores_cen$grave,
  "Abandono primário"       = cores_cen$atencao,
  "Falência"                = cores_cen$series[2], # terracota
  "TB-DR"                   = cores_cen$series[3], # roxo
  "Óbito por TB"            = cores_cen$critico,
  "Óbito por outras causas" = cores_cen$series[5], # vinho
  "Transferência"           = cores_cen$series[8], # ciano
  "Mudança de diagnóstico"  = cores_cen$tinta_3,
  "Mudança de esquema"      = cores_cen$series[7]  # indigo
)

# Rotulos da legenda do indicador por territorio com virgula decimal (o
# labelFormat() do leaflet so' usa ponto -- "43.974" parecia milhar) e em %
# nas proporcoes; ultima faixa aberta ("Inf") vira "≥ x".
formato_legenda <- function(percentual = FALSE, digitos = 1) {
  function(type, cuts, p) {
    fmt <- function(x) {
      if (percentual) {
        paste0(formatC(100 * x, format = "f", digits = digitos, big.mark = ".", decimal.mark = ",", drop0trailing = TRUE), "%")
      } else {
        formatC(x, format = "f", digits = digitos, big.mark = ".", decimal.mark = ",")
      }
    }
    n <- length(cuts)
    rotulos <- paste0(fmt(cuts[-n]), " – ", fmt(cuts[-1]))
    if (is.infinite(cuts[n])) rotulos[n - 1] <- paste0("≥ ", fmt(cuts[n - 1]))
    rotulos
  }
}

# Paleta por quantil pro mapa de incidencia -- em vez de faixas de valor
# fixas (colorBin com bins manuais), cada cor abrange a mesma quantidade de
# bairros, recalculado a partir dos dados do periodo/filtro atual (pedido
# do coordenador do projeto: destacar sempre os piores/melhores relativos,
# nao um limiar absoluto). leaflet::colorQuantile() quebra com "'breaks'
# nao sao unicos" sempre que ha' muitos bairros com o mesmo valor (comum em
# incidencia, que costuma ter varios bairros zerados no mesmo periodo) --
# calcula os pontos de corte manualmente e usa so' os unicos, reduzindo o
# numero de classes em vez de dar erro.
pal_quantil <- function(palette, domain, n = 5) {
  breaks <- unique(stats::quantile(domain, probs = seq(0, 1, length.out = n + 1), na.rm = TRUE, names = FALSE))
  if (length(breaks) < 2) {
    breaks <- c(breaks, breaks[length(breaks)] + 1)
  }
  leaflet::colorBin(palette, domain = domain, bins = breaks)
}

# Indicador por territorio (bairro ou Distrito Sanitario): conta os casos por
# territorio e calcula o indicador escolhido. `coluna` e' a coluna do caso com
# o territorio onde o ponto cai (territorio_bairro/territorio_ds, atribuida
# uma vez por caso em R/fct_casos.R) e `chaves` o identificador de cada linha
# de `terr`, na mesma ordem -- em vez de refazer o cruzamento espacial
# territorios x casos a cada troca de filtro ou indicador. `orfaos` = obitos
# por TB so' no SIM (sem notificacao) por linha de `terr` -- entram por nome
# de bairro, fora daqui, porque nao tem coordenada propria: no numerador da
# mortalidade e no numerador e no denominador da letalidade (ver
# docs/DOCUMENTACAO_GRAFICOS.md, secao 2.2).
calcular_indicador_territorio <- function(terr, casos, orfaos, indicador, coluna, chaves) {
  contar <- function(x) as.integer(table(factor(x[[coluna]], levels = chaves)))

  if (indicador == "inc") {
    terr$casos <- contar(casos)
    terr$ind <- 1e5 * (terr$casos / terr$pop)
  } else if (indicador == "mort") {
    terr$obitos <- contar(casos |> dplyr::filter(obito_tb_confirmado)) + orfaos
    terr$ind <- 1e5 * (terr$obitos / terr$pop)
  } else if (indicador == "let") {
    terr$obitos <- contar(casos |> dplyr::filter(obito_tb_confirmado)) + orfaos
    terr$encerrados <- contar(casos |> dplyr::filter(situacao == "Encerrado")) + orfaos
    terr$ind <- terr$obitos / terr$encerrados
  } else if (indicador == "prop_cura") {
    terr$curados <- contar(casos |> dplyr::filter(desfecho == "Cura"))
    terr$encerrados <- contar(casos |> dplyr::filter(situacao == "Encerrado"))
    terr$ind <- terr$curados / terr$encerrados
  } else if (indicador == "prop_aband") {
    terr$aband <- contar(casos |> dplyr::filter(desfecho %in% c("Abandono", "Abandono primário", "Falência")))
    terr$encerrados <- contar(casos |> dplyr::filter(situacao == "Encerrado"))
    terr$ind <- terr$aband / terr$encerrados
  }

  terr
}

# Popup de um ou mais pontos do mapa (casos e obitos so-SIM). Montado so'
# quando o ponto e' clicado (ver output$main_map) -- antes ia um popup pronto
# pra cada ponto, a maior parte do que o mapa mandava pro navegador.
popup_caso <- function(casos) {
  sprintf(
    "<b>Número de notificação</b>: %s
        <br><b>Data de diagnóstico</b>: %s
        <br><b>Data de notificação</b>: %s
        <br><b>Data de início do tratamento</b>: %s
        <br><b>Data de encerramento</b>: %s
        <br><b>Sexo</b>: %s
        <br><b>Idade</b>: %s
        <br><b>Raça/cor</b>: %s
        <br><b>Endereço</b>: %s
        <br><b>Comorbidades</b>: %s
        <br><b>População especial?</b> %s
        <br><b>Forma</b>: %s
        <br><br><b>Situação</b>: %s",
    casos$numero_notificacao,
    casos$dt_diagnostico |> format("%d/%m/%Y"),
    casos$dt_notificacao |> format("%d/%m/%Y"),
    casos$dt_inicio_tratamento |> format("%d/%m/%Y"),
    casos$dt_encerramento |> format("%d/%m/%Y"),
    casos$sexo,
    round(casos$idade),
    casos$raca_cor,
    htmltools::htmlEscape(casos$endereco),
    htmltools::htmlEscape(casos$comorbidades),
    htmltools::htmlEscape(ifelse(casos$populacao_especial == "", "Não", casos$populacao_especial)),
    casos$forma,
    casos$desfecho
  )
}

# Simbolos das unidades de saude: "S" vermelho pra rede publica/SUS e "✕"
# pras demais unidades notificadoras.
estilo_unidade_sus <- list("color" = cores_cen$critico, "font-weight" = "900", "font-size" = "17px", "font-family" = "Arial, sans-serif")
estilo_unidade_outras <- list("color" = cores_cen$tinta, "font-weight" = "bold", "font-size" = "18px")

# Camada de unidades de saude no mapa: um rotulo fixo (`simbolo`, ex. "S" ou
# "✕") por ponto e, por cima, um circulo invisivel so' pra capturar o hover
# (addLabelOnlyMarkers nao combina rotulo fixo com tooltip de hover diferente
# na mesma camada; mesmo padrao usado em SP -- divIcon nao esta disponivel
# na versao instalada do leaflet). O circulo vai pro canvas dos casos e das
# malhas (preferCanvas, ver output$main_map), por cima dos casos
# (js_ordena_camadas) -- como no pane "topLayer" de antes do canvas. Um pane
# proprio nao serve: no Leaflet 1.3 pane personalizado vira SVG, e SVG por
# cima do canvas rouba o hover das camadas de baixo. `unidades` precisa de
# nome, descricao (tipo/natureza, pode ser NA), n_casos, bairro_aproximado,
# latitude e longitude.
adicionar_camada_unidades <- function(m, unidades, simbolo, estilo, grupo) {
  if (nrow(unidades) == 0) return(m)

  nota_aproximada <- function(bairro) {
    ifelse(
      is.na(bairro),
      "",
      sprintf(
        "<br><i>Localização aproximada: centro do bairro %s (coordenada do CNES fora de Recife)</i>",
        htmltools::htmlEscape(bairro)
      )
    )
  }

  # Unidades no mesmo ponto (varias no centroide do mesmo bairro, ou
  # varias clinicas do mesmo predio com a mesma coordenada no CNES) viram
  # um marcador so', com todas no hover -- senao so' a de cima fica
  # visivel. Lista curta e limitada a max_hover nomes (mais casos
  # primeiro) pra o hover nao passar da altura da tela.
  max_hover <- 8

  pontos <- unidades |>
    dplyr::arrange(dplyr::desc(n_casos)) |>
    dplyr::group_by(longitude, latitude) |>
    dplyr::summarise(
      hover = if (dplyr::n() == 1) {
        sprintf(
          "<b>%s</b>%s<br><b>%s</b> caso(s) notificado(s) no período selecionado%s",
          nome,
          ifelse(is.na(descricao), "", paste0("<br>", htmltools::htmlEscape(descricao))),
          n_casos, nota_aproximada(bairro_aproximado)
        )
      } else {
        paste0(
          sprintf("<b>%d unidades neste ponto</b>", dplyr::n()),
          paste0("<br>", utils::head(nome, max_hover), ": <b>", utils::head(n_casos, max_hover), "</b> caso(s)", collapse = ""),
          if (dplyr::n() > max_hover) sprintf("<br>+ %d outra(s)", dplyr::n() - max_hover) else "",
          "<br>(casos notificados no período selecionado)",
          nota_aproximada(dplyr::first(bairro_aproximado[!is.na(bairro_aproximado)]))
        )
      },
      .groups = "drop"
    ) |>
    sf::st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

  hover <- pontos$hover |> lapply(htmltools::HTML)

  m |>
    leaflet::addLabelOnlyMarkers(
      data = pontos,
      label = simbolo,
      labelOptions = leaflet::labelOptions(
        noHide = TRUE,
        direction = "center",
        textOnly = TRUE,
        style = c(estilo, list("text-shadow" = "-1px -1px 0 #fff, 1px -1px 0 #fff, -1px 1px 0 #fff, 1px 1px 0 #fff"))
      ),
      group = grupo,
      options = leaflet::markerOptions(pane = "topLayer")
    ) |>
    leaflet::addCircleMarkers(
      data = pontos,
      radius = 10,
      stroke = FALSE,
      fillOpacity = 0,
      label = hover,
      group = grupo,
      # Sem pane: canvas dos casos (ver comentario acima)
      options = leaflet::pathOptions()
    )
}

# SERVER ----
#' municipio Server Functions
#'
#' @noRd
mod_municipio_server <- function(id, chosen_municipio, cache_trigger = shiny::reactiveVal(0)){
  shiny::moduleServer(id, function(input, output, session){
    ns <- session$ns

    # Base carregada veio dos dados ficticios? Liga os avisos do mapa, da
    # ficha do caso e do cabecalho (ver dados_sao_ficticios() em
    # R/fct_db_update.R)
    ficticio <- dados_sao_ficticios()

    ## Filtros iniciais -----

    filtro_sexo_active <- shiny::reactiveVal(
      value = c("F", "M", "I")
    )

    filtro_idade_active <- shiny::reactiveVal(value = as.integer(c(0,120)))

    filtro_raca_cor_active <- shiny::reactiveVal(
      value = c("Branca", "Preta", "Amarela", "Parda", "Indígena", "Ignorado")
    )

    filtro_tipo_entrada_active <- shiny::reactiveVal(
      value = c("Caso Novo", "Recidiva", "Reingresso após abandono",
                "Não Sabe", "Transferência", "Pós-óbito")
    )

    filtro_comorbidades_active <- shiny::reactiveVal(
      value = NULL
    )

    filtro_populacao_especial_active <- shiny::reactiveVal(
      value = NULL
    )

    filtro_desfecho_active <- shiny::reactiveVal(
      value = c(
        "Cura", "Em aberto",
        "Abandono", "Abandono primário", "Falência", "TB-DR",
        "Mudança de diagnóstico", "Mudança de esquema", "Transferência",
        "Óbito por outras causas", "Óbito por TB"
      )
    )

    filtro_forma_active <- shiny::reactiveVal(
      value = c("Pulmonar", "Extrapulmonar", "Pulmonar + Extrapulmonar")
    )

    # Periodo em vigor no painel -- so' muda quando a escolha de datas
    # termina (input$periodo_aplicado, ver js_periodo_aplicado no topo do
    # arquivo), nao a cada data clicada. Tudo que depende do periodo usa
    # periodo_ativo(), nunca input$periodo direto. Periodo invalido (data
    # vazia ou inicio depois do fim) e' ignorado.
    periodo_ativo <- shiny::reactiveVal(periodo_default())

    shiny::observeEvent(input$periodo_aplicado, {
      periodo <- as.Date(input$periodo_aplicado)
      if (length(periodo) == 2 && !anyNA(periodo) && periodo[1] <= periodo[2]) {
        periodo_ativo(periodo)
      }
    })

    desfecho_ids <- dplyr::tibble(
      desfecho = c("Abandono",
                   "Abandono primário",
                   "Cura",
                   "Em aberto",
                   "Falência",
                   "Mudança de diagnóstico",
                   "Mudança de esquema",
                   "Óbito por outras causas",
                   "Óbito por TB",
                   "TB-DR",
                   "Transferência")
    ) |> dplyr::mutate(desfecho_id = dplyr::row_number())

    ## Reactive values ----

    ### Malhas ----
    # Carregadas uma vez por processo e compartilhadas entre as sessoes --
    # ver R/fct_casos.R (limite de Recife, bairros, Distritos Sanitarios,
    # areas de abrangencia da APS e as versoes simplificadas pro desenho).

    map_shape <- shiny::reactive({
      if (chosen_municipio() == "recife") limite_municipio()
    })

    bairro_shape <- shiny::reactive({
      if (chosen_municipio() == "recife") malha_bairros()
    })

    distritos_shape <- shiny::reactive(malha_distritos())

    abrangencia_shape <- shiny::reactive(malha_abrangencia())

    # DS de cada bairro (mesma ordem de bairro_shape()) -- usado pra somar os
    # obitos so-SIM, que so' tem o nome do bairro, por DS.
    bairro_cod_ds <- shiny::reactive(ds_de_cada_bairro())

    ### Unidades de saude (CNES) ----
    # Cache gerado manualmente por dev/build_unidades_cnes.R (API publica do
    # DATASUS) -- nao existe fallback de banco aqui: se o cache ainda nao foi
    # gerado, a camada de unidades simplesmente fica vazia no mapa.
    # bairro_aproximado: preenchido quando a coordenada do CNES caia fora de
    # Recife e a unidade foi posta no centroide do bairro do cadastro (NA =
    # coordenada do proprio CNES). publica: unidade da rede publica/SUS
    # (entra no mapa com "S", mesmo sem notificar caso); tipo_unidade e
    # natureza: rotulos pro hover. Caches gerados antes dessas colunas
    # existirem continuam funcionando -- coordenada tratada como do CNES e
    # unidade sem classificacao (entra como "✕", como antes).
    unidades_cnes <- shiny::reactive({
      if (file.exists("local/unidades_cnes.rds")) {
        unidades <- readRDS("local/unidades_cnes.rds")
        if (!"bairro_aproximado" %in% names(unidades)) unidades$bairro_aproximado <- NA_character_
        if (!"publica" %in% names(unidades)) unidades$publica <- NA
        if (!"tipo_unidade" %in% names(unidades)) unidades$tipo_unidade <- NA_character_
        if (!"natureza" %in% names(unidades)) unidades$natureza <- NA_character_
        unidades
      } else {
        tibble::tibble(
          codigo_cnes = character(), nome_fantasia = character(),
          razao_social = character(), latitude = double(), longitude = double(),
          bairro_aproximado = character(), publica = logical(), tipo_unidade = character(),
          natureza = character()
        )
      }
    })

    ### Cases -----

    # Casos compartilhados entre as sessoes, ja' com o bairro e o DS de cada
    # ponto (ver carrega_casos() em R/fct_casos.R). cache_trigger() faz a
    # sessao que clicou em "Atualizar dados" reler na hora.
    casos_sf <- shiny::reactive({
      cache_trigger()

      if (chosen_municipio() == "recife") carrega_casos()
    })


    ### Obitos por TB so no SIM (sem notificacao SINAN) -----

    # Nao sao "casos" (sem forma clinica, sem data de diagnostico, sem
    # tratamento) -- alimentam so os indicadores de mortalidade (card e mapa),
    # nunca a tabela/mapa de casos ou os demais cards. Ver
    # docs/DOCUMENTACAO_GRAFICOS.md para o racional dessa separacao.
    obitos_sim_orfaos <- shiny::reactive({
      cache_trigger()

      mun <- chosen_municipio()

      if (mun != "recife") return(dplyr::tibble())

      # Compartilhados entre as sessoes (ver carrega_obitos_orfaos() em
      # R/fct_casos.R)
      carrega_obitos_orfaos()
    })

    ### Last update ----

    dt_ultima_atualizacao <- shiny::reactive({
      shiny::req(casos_sf())

      casos_sf() |>
        dplyr::pull(dt_notificacao) |>
        max(na.rm=T)
    })

    ### Filtered cases -----

    casos_filtered <- shiny::reactive({

      shiny::req(casos_sf())
      shiny::req(periodo_ativo())

      casos <- casos_sf() |>
        dplyr::filter(dt_diagnostico >= periodo_ativo()[1],
                      dt_diagnostico <= periodo_ativo()[2],
                      sexo %in% filtro_sexo_active(),
                      idade >= filtro_idade_active()[1],
                      idade <= filtro_idade_active()[2],
                      raca_cor %in% filtro_raca_cor_active(),
                      tipo_entrada %in% filtro_tipo_entrada_active(),
                      desfecho %in% filtro_desfecho_active(),
                      forma %in% filtro_forma_active()
                      )

      if (!is.null(filtro_comorbidades_active())) {
        casos <- casos |>
          dplyr::filter(grepl(filtro_comorbidades_active(), comorbidades))
      }

      if (!is.null(filtro_populacao_especial_active())) {
        casos <- casos |>
          dplyr::filter(grepl(filtro_populacao_especial_active(), populacao_especial))
      }

      casos

    })

    ### Obitos orfaos filtrados por periodo -----

    # So o filtro de periodo se aplica (pela data do obito, dt_obito_sim) --
    # os demais filtros (sexo, idade, forma, comorbidades etc.) descrevem
    # dados clinicos/de notificacao que um obito so-SIM nao tem.
    obitos_sim_orfaos_filtrados <- shiny::reactive({
      shiny::req(periodo_ativo())

      # Todo orfao tem desfecho fixo "Óbito por TB" -- se esse desfecho nao
      # estiver entre os selecionados no filtro, os orfaos nao devem contar
      # em nada (card, mapa ou tabela lateral). Colocado aqui (nao só em
      # orfaos_pontos()) porque o card de obitos usa este reactive direto.
      if (!"Óbito por TB" %in% filtro_desfecho_active()) {
        return(obitos_sim_orfaos()[0, ])
      }

      obitos_sim_orfaos() |>
        dplyr::filter(
          obito_tb_confirmado,
          !is.na(dt_obito_sim),
          dt_obito_sim >= periodo_ativo()[1],
          dt_obito_sim <= periodo_ativo()[2]
        )
    })

    ### Filtered points ----

    desfecho_sel <- shiny::reactive(reactable::getReactableState("casos_table", "selected"))

    ### Pontos dos obitos so-SIM (centroide do bairro) -----

    # Centroide de cada bairro, usado como localizacao aproximada dos
    # obitos por TB que so aparecem no SIM (sem endereco/coordenada propria).
    # "Por enquanto" (ver docs/DOCUMENTACAO_GRAFICOS.md): uma posicao exata
    # dentro do bairro exigiria georreferenciamento proprio, que esses
    # registros nao tem.
    bairro_centroides <- shiny::reactive(centroides_bairros())

    orfaos_pontos <- shiny::reactive({
      # obitos_sim_orfaos_filtrados() ja retorna vazio se "Óbito por TB" nao
      # estiver entre os desfechos selecionados no filtro.
      orfaos <- obitos_sim_orfaos_filtrados()

      if (nrow(orfaos) == 0) return(casos_filtered()[0, ])

      centroides <- bairro_centroides()
      idx <- match(orfaos$bairro_norm, centroides$bairro_norm)

      orfaos_geo <- orfaos[!is.na(idx), ]
      idx <- idx[!is.na(idx)]

      if (nrow(orfaos_geo) == 0) return(casos_filtered()[0, ])

      sf::st_sf(
        numero_notificacao = paste0("SIM_", orfaos_geo$numerodo_do_sim),
        desfecho = "Óbito por TB",
        situacao = "Encerrado",
        dt_encerramento = orfaos_geo$dt_obito_sim,
        dt_obito_sim = orfaos_geo$dt_obito_sim,
        causabas_sim = orfaos_geo$causabas_sim,
        obito_tb_confirmado = TRUE,
        bairro = orfaos_geo$bairro_norm,
        # georreferenciado = 1 aqui nao significa endereco exato -- so
        # garante que o ponto (no centroide) e exibido no mapa, que hoje
        # filtra por essa coluna.
        georreferenciado = 1,
        geometry = centroides$geometry[idx]
      )
    })

    casos_points <- shiny::reactive({

      shiny::req(casos_filtered())

      shiny::req(desfecho_sel)

      desfechos <- desfecho_ids[desfecho_sel(),] |> dplyr::pull(desfecho)

      combinado <- dplyr::bind_rows(casos_filtered(), orfaos_pontos())
      if (!inherits(combinado, "sf")) combinado <- sf::st_as_sf(combinado)

      combinado |>
        dplyr::filter(desfecho %in% desfechos)

    })

    ### Indicator by territory (bairro / Distrito Sanitario) ----

    # Entram no indicador POR TERRITORIO so' os casos com
    # georreferenciado = 1 e indicador = 1 (colunas da pipeline de
    # georreferenciamento -- ver fct_db_update.R):
    #   - georreferenciado = 0 (centroide do municipio, sem coordenada,
    #     endereco vazio) nao tem localizacao de residencia: um caso no
    #     centroide de Recife seria contado no bairro onde fica o centro da
    #     cidade.
    #   - indicador = 0 (detento/situacao de rua) nao tem endereco de
    #     residencia confiavel (o caso costuma ficar geocodificado pelo
    #     endereco da unidade/presidio/albergue) -- atribuiria a taxa ao
    #     territorio da unidade, nao ao de residencia real.
    # Excluidos SO' AQUI (mapa de indicadores por bairro/DS); os cards do
    # topo e a tabela de casos continuam contando/mostrando todo mundo.
    # NAO cobre os obitos "orfaos" do SIM (obitos_sim_orfaos_filtrados())
    # somados abaixo -- essa base nao tem campo populacao_especial (so'
    # tem dt_obito_sim/causabas_sim/obito_tb_confirmado/bairro_norm, sem
    # nenhum dado do SINAN em si), entao nao ha' como saber se um obito
    # orfao era de rua/detento antes de somar por territorio.
    casos_indicador <- shiny::reactive({
      casos_filtered() |>
        dplyr::filter(georreferenciado == 1, indicador == 1)
    })

    # Obitos so-SIM (sem notificacao SINAN) por bairro de residencia, na
    # ordem de bairro_shape() -- essas linhas nao tem coordenada/endereco,
    # entao entram por nome de bairro normalizado, nao por interseccao
    # espacial. Letalidade: entram tanto no numerador quanto no denominador
    # (recomendacao da equipe tecnica que acompanha o painel) -- um obito
    # confirmado conta como um caso encerrado (por obito), mesmo sem
    # notificacao SINAN. Ver docs/DOCUMENTACAO_GRAFICOS.md.
    orfaos_por_bairro <- shiny::reactive({
      contagem <- obitos_sim_orfaos_filtrados() |>
        dplyr::count(bairro_norm, name = "n_orfaos")

      bairro_norm_shape <- stringi::stri_trans_general(toupper(trimws(bairro_shape()$name_neighborhood)), "Latin-ASCII")
      dplyr::coalesce(contagem$n_orfaos[match(bairro_norm_shape, contagem$bairro_norm)], 0L)
    })

    # Geometria so' pro desenho (simplificada) -- a contagem usa o bairro de
    # cada caso, atribuido na malha completa (ver R/fct_casos.R).
    ind_bair <- shiny::reactive({
      bair <- malha_bairros_desenho()
      calcular_indicador_territorio(bair, casos_indicador(), orfaos_por_bairro(), input$indicador_bairro,
                                    coluna = "territorio_bairro", chaves = bair$name_neighborhood) |>
        dplyr::mutate(nome_territorio = name_neighborhood)
    })

    # Mesmas contas do bairro, direto sobre o poligono do DS (um caso na
    # divisa entre dois bairros do mesmo DS conta uma vez so' no DS). Os
    # orfaos entram somados pelos bairros de cada DS.
    ind_ds <- shiny::reactive({
      ds <- malha_distritos_desenho()

      orfaos_ds <- tapply(orfaos_por_bairro(), bairro_cod_ds(), sum)
      orfaos <- dplyr::coalesce(as.integer(orfaos_ds[as.character(ds$cod_ds)]), 0L)

      calcular_indicador_territorio(ds, casos_indicador(), orfaos, input$indicador_bairro,
                                    coluna = "territorio_ds", chaves = ds$cod_ds) |>
        dplyr::mutate(nome_territorio = sprintf("%s (%d bairros)", nome, n_bairros))
    })

    ## ShinyJS ----

    shiny::observeEvent(input$show_indicador_bairro, {
      if (input$show_indicador_bairro) {
        shinyjs::enable("indicador_bairro")
        shinyjs::enable("nivel_territorial")
      } else {
        shinyjs::disable("indicador_bairro")
        shinyjs::disable("nivel_territorial")
      }
    })

    shiny::observeEvent(input$mostrar_filtros, {
      shinyjs::show("box_filtro_row")
      bs4Dash::updateBox("box_filtro", action = "restore", session = session)
    })

    shiny::observeEvent(input$filtro_update, {

      filtro_sexo_active(input$filtro_sexo)
      filtro_idade_active(as.integer(input$filtro_idade))
      filtro_raca_cor_active(input$filtro_raca_cor)
      filtro_tipo_entrada_active(input$filtro_tipo_entrada)
      filtro_comorbidades_active(input$filtro_comorbidades)
      filtro_populacao_especial_active(input$filtro_populacao_especial)
      filtro_desfecho_active(input$filtro_desfecho)
      filtro_forma_active(input$filtro_forma)


      bs4Dash::updateBox("box_filtro", action = "remove", session = session)
    })

    shiny::observeEvent(input$filtro_clear, {


      shinyWidgets::updateCheckboxGroupButtons("filtro_sexo", session = session, selected =filtro_sexo_default)
      shiny::updateSliderInput("filtro_idade", session=session, value = filtro_idade_default)
      shinyWidgets::updatePickerInput(session = session, "filtro_raca_cor", selected = filtro_raca_cor_default)
      shinyWidgets::updatePickerInput(session = session, "filtro_tipo_entrada", selected = filtro_tipo_entrada_default)
      shinyWidgets::updatePickerInput(session = session, "filtro_comorbidades", selected = filtro_comorbidades_default)
      shinyWidgets::updatePickerInput(session = session, "filtro_populacao_especial", selected = filtro_populacao_especial_default)
      shinyWidgets::updatePickerInput(session = session, "filtro_desfecho", selected = filtro_desfecho_default)
      shinyWidgets::updatePickerInput(session = session, "filtro_forma", selected = filtro_forma_default)


      filtro_sexo_active(filtro_sexo_default)
      filtro_idade_active(as.integer(filtro_idade_default))
      filtro_raca_cor_active(filtro_raca_cor_default)
      filtro_tipo_entrada_active(filtro_tipo_entrada_default)
      filtro_comorbidades_active(filtro_comorbidades_default)
      filtro_populacao_especial_active(filtro_populacao_especial_default)
      filtro_desfecho_active(filtro_desfecho_default)
      filtro_forma_active(filtro_forma_default)


      bs4Dash::updateBox("box_filtro", action = "remove", session = session)
    })

    shinyjs::onclick('box_aberto_6m_click', {
      shinyjs::show("box_filtro_row")
      bs4Dash::updateBox("box_filtro", action = "restore", session = session)
      shinyWidgets::updatePickerInput(session = session, "filtro_desfecho", selected = "Em aberto")
      filtro_desfecho_active("Em aberto")
    })

    shiny::observeEvent(input$ver_detalhes_casos, {

      num_notific <- input$ver_detalhes_casos$id

      # Cores dos desfechos: fonte unica em cores_desfecho (topo do arquivo)
      bg_color <- cores_desfecho

      caso <- casos_sf() |>
        dplyr::filter(numero_notificacao == num_notific) |>
        sf::st_drop_geometry() |>
        dplyr::slice_head(n=1) |>
        dplyr::mutate(
          desfecho_label = sprintf(
            '<span style="background-color: %s;
             color: white;
             padding: 5px 15px;
             border-radius: 20px;
             display: inline-block;
             font-size: 16px;
             font-weight: bold;">
    %s
</span>', bg_color[[desfecho]], desfecho
          )
        )

      print(num_notific)

      shiny::showModal(
        shiny::modalDialog(
          title = htmltools::tagList(
            paste0("Ficha de notificação ", num_notific, " "),
            if (ficticio) htmltools::span(class = "selo-ficticio", "CASO FICTÍCIO")
          ),
          htmltools::div(
            #style="line-height: 3.6;",
            shiny::fluidRow(
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Data de diagnóstico</b></h4> <p>%s</p>", format(caso$dt_diagnostico, "%d/%m/%Y")))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Data de notificação</b></h4> <p>%s</p>", format(caso$dt_notificacao, "%d/%m/%Y")))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Data de início do tratamento</b></h4> <p>%s</p>", format(caso$dt_inicio_tratamento, "%d/%m/%Y")))
              )
            ),
            shiny::hr(),
            shiny::fluidRow(
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Idade</b></h4> <p>%d</p>", floor(caso$idade)))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Sexo</b></h4> <p>%s</p>", caso$sexo))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Raça/cor</b></h4> <p>%s</p>", caso$raca_cor))
              )
            ),

            shiny::hr(),
            shiny::fluidRow(
              bs4Dash::column(
                6,
                htmltools::HTML(sprintf("<h4><b>Comorbidades</b></h4> <p>%s</p>",
                             htmltools::htmlEscape(ifelse(caso$n_comorbidades == 0, "Nenhuma", caso$comorbidades))))
              ),
              bs4Dash::column(
                6,
                htmltools::HTML(sprintf("<h4><b>População especial</b></h4> <p>%s</p>",
                             htmltools::htmlEscape(ifelse(caso$populacao_especial == "", "Não consta", caso$populacao_especial))))
              )
            ),

            shiny::hr(),
            shiny::fluidRow(
              bs4Dash::column(
                6,
                htmltools::HTML(sprintf("<h4><b>Tipo de entrada</b></h4> <p>%s</p>", caso$tipo_entrada))
              ),
              bs4Dash::column(
                6,
                htmltools::HTML(sprintf("<h4><b>Forma</b></h4> <p>%s</p>", caso$forma))
              )
            ),

            shiny::hr(),
            shiny::fluidRow(
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Desfecho</b></h4> <p>%s</p>", caso$desfecho_label))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Data de encerramento</b></h4> <p>%s</p>", format(caso$dt_encerramento, "%d/%m/%Y")))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Tempo até encerramento (dias)</b></h4> <p>%s</p>", caso$tempo_aberto))
              )
            ),

            shiny::hr(),
            shiny::fluidRow(
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Bairro</b></h4> <p>%s</p>", htmltools::htmlEscape(caso$bairro)))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Logradouro</b></h4> <p>%s</p>", htmltools::htmlEscape(caso$endereco)))
              ),
              bs4Dash::column(
                4,
                htmltools::HTML(sprintf("<h4><b>Georreferenciado?</b></h4> <p>%s</p>",
                             ifelse(caso$georreferenciado == 1, "Sim", "Não")))
              )
            )
          ),
          size = "xl",
          footer = shiny::modalButton("Ok")
        )
      )

    }
    )

    ## UI outputs ----



    output$periodo_ui <- shiny::renderUI({
      # Para fazer o filtro de período interativo com base na última data observada, alterar aqui
      htmltools::tagList()

    })

    output$db_info_ui <- shiny::renderUI({

      shiny::req(casos_sf())

      n_geo <- sum(casos_sf()$georreferenciado == 1)
      n_tot <- nrow(casos_sf())
      last_notif_date <- max(casos_sf()$dt_notificacao, na.rm=T)

      htmltools::div(
        htmltools::div(style="font-weight: 100; color: #FFF", htmltools::HTML(sprintf("<i class=\"fa fa-clock-o\" aria-hidden=\"true\"></i>  %s: %s",
                                                   if (ficticio) "Dados fictícios até" else "Data de atualização dos dados",
                                                   format(last_notif_date, "%d/%m/%Y")))),
        htmltools::div(style="font-weight: 100; color: #FFF", htmltools::HTML(sprintf("<i class=\"fa fa-globe\" aria-hidden=\"true\"></i> Total de casos georreferenciados: %s (%s)",
                                           format(n_geo, big.mark=".", decimal.mark=","),
                                           scales::percent(
                                             n_geo/n_tot, accuracy = 0.1, big.mark=".", decimal.mark=","
                                           )
                                           )))
      )
    })

    output$main_map_title <- shiny::renderUI({

      mun <- chosen_municipio()

      location <- dplyr::case_when(
        mun == "recife" ~ "Recife - PE",
        mun == "brasilia" ~ "Brasília-DF",
        TRUE ~ "Município"
      )

      title <- paste0(
        "Mapa de casos de TB em ",
        location, ", de ",
        format(periodo_ativo()[1], "%d/%m/%Y"), " à ", format(periodo_ativo()[2], "%d/%m/%Y")
      )

      htmltools::tagList(
        bs4Dash::column(12,
               htmltools::h3(title, style = "font-weight: 600"),
               align = "center"
               )
      )


    })

    output$main_map_subtitle <- shiny::renderUI({
      modified_sexo <- isTRUE(!identical(filtro_sexo_active(), filtro_sexo_default))
      modified_idade <- isTRUE(!identical(filtro_idade_active(), filtro_idade_default))
      modified_raca_cor <- isTRUE(!identical(filtro_raca_cor_active(), filtro_raca_cor_default))
      modified_tipo_entrada <- isTRUE(!identical(filtro_tipo_entrada_active(), filtro_tipo_entrada_default))
      modified_comorbidades <- isTRUE(!identical(filtro_comorbidades_active(), filtro_comorbidades_default))
      modified_populacao_especial <- isTRUE(!identical(filtro_populacao_especial_active(), filtro_populacao_especial_default))
      modified_desfecho <- isTRUE(!identical(filtro_desfecho_active(), filtro_desfecho_default))
      modified_forma <- isTRUE(!identical(filtro_forma_active(), filtro_forma_default))

      map_subtitle <- paste0(
        ifelse(any(c(modified_sexo, modified_idade, modified_raca_cor, modified_tipo_entrada,
                     modified_comorbidades, modified_populacao_especial, modified_desfecho, modified_forma)),
               "Filtros: ", ""),
        paste(
          c(ifelse(modified_sexo, paste0("<b>Sexo:</b> ", paste(filtro_sexo_active(), collapse = ", ")), NA),
            ifelse(modified_idade, paste0("<b>Idade:</b> ", paste(filtro_idade_active(), collapse = "-")), NA),
            ifelse(modified_raca_cor, paste0("<b>Raça/cor:</b> ", paste(filtro_raca_cor_active(), collapse = ", ")), NA),
            ifelse(modified_tipo_entrada, paste0("<b>Tipo de entrada:</b> ", paste(filtro_tipo_entrada_active(), collapse = ", ")), NA),
            ifelse(modified_comorbidades, paste0("<b>Comorbidade:</b> ", paste(filtro_comorbidades_active(), collapse = ", ")), NA),
            ifelse(modified_populacao_especial, paste0("<b>População especial:</b> ", paste(filtro_populacao_especial_active(), collapse = ", ")), NA),
            ifelse(modified_desfecho, paste0("<b>Desfechos:</b> ", paste(filtro_desfecho_active(), collapse = ", ")), NA),
            ifelse(modified_forma, paste0("<b>Forma:</b> ", paste(filtro_forma_active(), collapse = ", ")), NA)) |>
            purrr::discard(is.na),
          collapse = "; "
        )

      )

      map_subtitle

      htmltools::tagList(
        bs4Dash::column(12,
                        htmltools::h6(htmltools::HTML(map_subtitle), style = "font-weight: 400"),
                        align = "center"
        )
      )

    })


    ## Box outputs ----

    ### Box total ----

    output$box_total <- bs4Dash::renderbs4ValueBox({

      casos <- casos_filtered()

      shiny::req(!is.null(casos))

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(nrow(casos), big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Total de casos no período"),
        color = "teal",
        gradient = TRUE,
        icon = shiny::icon("users")

      )
    })

    ### Box em aberto -----

    output$box_aberto_6m <- bs4Dash::renderbs4ValueBox({

      casos_aberto <- casos_filtered() |> dplyr::filter(situacao == "Em aberto")

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(nrow(casos_aberto), big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Casos em aberto"),
        color = "warning",
        gradient = TRUE,
        icon = shiny::icon("warning"),
        footer = htmltools::div(id = ns("box_aberto_6m_click"), style="cursor: pointer;", shiny::icon("external-link"), "Ver todos em aberto")

      )
    })

    ### Box cura -----

    output$box_cura <- bs4Dash::renderbs4ValueBox({

      casos_cura <- casos_filtered() |> dplyr::filter(desfecho == "Cura")

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(nrow(casos_cura), big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Curados"),
        color = "success",
        gradient = TRUE,
        icon = shiny::icon("heart")

      )
    })

    ### Box abandono ----

    output$box_abandono <- bs4Dash::renderbs4ValueBox({

      casos_abandono <- casos_filtered() |> dplyr::filter(desfecho == "Abandono" | desfecho == "Falência" | desfecho == "Abandono primário")

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(nrow(casos_abandono), big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Casos em abandono/falência"),
        color = "orange",
        gradient = TRUE,
        icon = shiny::icon("medkit")

      )
    })

    ### Box mortalidade -----

    output$box_mortalidade <- bs4Dash::renderbs4ValueBox({

      # Obito por TB confirmado (SIM quando pareado, senao desfecho do SINAN
      # -- ver obito_tb_confirmado em fct_db_update.R) + obitos so-SIM sem
      # notificacao correspondente (nao entram como "caso", so aqui).
      casos_obitos <- casos_filtered() |> dplyr::filter(obito_tb_confirmado)
      n_obitos <- nrow(casos_obitos) + nrow(obitos_sim_orfaos_filtrados())

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(n_obitos, big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Óbitos por TB"),
        color = "danger",
        gradient = TRUE,
        icon = shiny::icon("heartbeat")

      )
    })

    ### Box TB-DR ----

    output$box_tbdr <- bs4Dash::renderbs4ValueBox({

      casos_tbdr <- casos_filtered() |> dplyr::filter(desfecho == "TB-DR")

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(nrow(casos_tbdr), big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Casos de TB-DR"),
        color = "purple",
        gradient = TRUE,
        icon = shiny::icon("disease")

      )
    })

    ### Box Situação de rua ----

    output$box_situacao_rua <- bs4Dash::renderbs4ValueBox({

      casos_rua <- casos_filtered() |> dplyr::filter(grepl("Situação de rua", populacao_especial))

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(nrow(casos_rua), big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Situação de rua"),
        color = "indigo",
        gradient = TRUE,
        icon = shiny::icon("street-view")

      )
    })

    ### Box Privado de liberdade ----

    output$box_privado_liberdade <- bs4Dash::renderbs4ValueBox({

      casos_liberdade <- casos_filtered() |> dplyr::filter(grepl("Privado de liberdade", populacao_especial))

      bs4Dash::bs4ValueBox(
        value = htmltools::h3(format(nrow(casos_liberdade), big.mark=".", decimal.mark = ",")),
        subtitle = htmltools::h5("Privado de liberdade"),
        color = "maroon",
        gradient = TRUE,
        icon = shiny::icon("user-lock")

      )
    })

    ## Table output ----

    output$casos_table <- reactable::renderReactable({
      shiny::req(casos_filtered())

      # Inclui os obitos so-SIM aqui (mas em nenhum outro card) -- essa
      # tabela funciona como legenda/filtro do mapa, e os orfaos agora
      # aparecem no mapa (seção 2.1 da documentação de graficos).
      casos <- dplyr::bind_rows(casos_filtered(), orfaos_pontos())

      desfecho_cont <- casos |>
        sf::st_drop_geometry() |>
        dplyr::count(desfecho) |>
        dplyr::right_join(desfecho_ids, by="desfecho") |>
        tidyr::replace_na(list(n=0)) |>
        dplyr::mutate(prop = n/sum(n)) |>
        dplyr::arrange(desfecho_id)

      # Render a bar chart with a label on the left. source: https://glin.github.io/reactable/articles/cookbook/cookbook.html
      bar_chart <- function(label, width = "100%", height = "1rem", fill = "#00bfc4", background = NULL) {
        bar <- htmltools::div(style = list(background = fill, width = width, height = height))
        chart <- htmltools::div(style = list(flexGrow = 1, marginLeft = "0.5rem", background = background), bar)
        htmltools::div(style = list(display = "flex", alignItems = "center", fontWeight = 600), label, chart)
      }

      desfecho_cont |>
        reactable::reactable(
        columns = list(
          desfecho = reactable::colDef(name = "Desfecho"),
          desfecho_id = reactable::colDef(show=F),
          n = reactable::colDef(
            name = "Frequência",
            cell = function(value, index) {
              desf <- desfecho_cont$desfecho[index]
              prop <- desfecho_cont$prop[index]

              bg_color <- dplyr::coalesce(unname(cores_desfecho[desf]), cores_cen$tinta_3)

              width <- paste0(value/max(desfecho_cont$n) * 100, "%")
              bar_chart(paste0(format(value, big.mark=".", decimal.mark = ","), " (",
                               scales::percent(prop, big.mark = ".", decimal.mark = ",", accuracy = 0.1), ")"),
                        fill = bg_color,
                        width = width)
            }
          ),
          prop = reactable::colDef(show=F)
        ),
        defaultSorted = list(n = "desc"),
        defaultPageSize = 15,
        sortable = F,
        selection = "multiple",
        defaultSelected = seq_len(nrow(desfecho_cont)),
        language = reactable_idioma
      )
    })

    output$tabela_casos <- reactable::renderReactable({
      shiny::req(casos_filtered())

      # So' as colunas exibidas -- colunas com show = FALSE iam inteiras pro
      # navegador sem aparecer em lugar nenhum.
      casos_df <- casos_filtered() |>
        sf::st_drop_geometry() |>
        dplyr::select(
          numero_notificacao,
          dt_diagnostico,
          dt_notificacao,
          dt_inicio_tratamento,
          idade,
          sexo,
          raca_cor,
          forma,
          dt_encerramento,
          desfecho,
          tempo_aberto,
          georreferenciado
        )

      # Cores dos desfechos: fonte unica em cores_desfecho (topo do arquivo),
      # aqui como objeto JS pra colorir a etiqueta no navegador
      cores_js <- paste0(
        "{",
        paste0(sprintf("'%s': '%s'", names(cores_desfecho), unname(cores_desfecho)),
               collapse = ", "),
        "}"
      )

      casos_df |>
        dplyr::mutate(georreferenciado = factor(
          georreferenciado,
          levels = c(0,1),
          labels = c("Não", "Sim")
        ), idade = as.integer(floor(idade))
        ) |>
        reactable::reactable(
          columns = list(
            numero_notificacao = reactable::colDef(
              name = "Núm. Notificação", align = "center",
              # As celulas de Num. Notificacao, Desfecho e Georreferenciado sao
              # montadas no navegador (reactable::JS). Montar uma tag HTML por
              # linha no R custava ~58 s e 21 MB de payload no periodo completo
              # (~26 mil casos); em JS vai a ~1 s e 3,7 MB.
              cell = reactable::JS(sprintf(
                "function(cellInfo) {
                   return React.createElement('a', {
                     style: {color: '#0E7BA8', fontWeight: 'bold', textDecoration: 'underline', cursor: 'pointer'},
                     onClick: function() {
                       Shiny.setInputValue('%s', {id: String(cellInfo.value), random: Math.random()});
                     }
                   }, cellInfo.value);
                 }",
                ns("ver_detalhes_casos")
              ))
            ),
            dt_diagnostico = reactable::colDef(
              name = "Diagnóstico",
              format = reactable::colFormat(
                date=T, locales = "pt-BR"
              ),
              style = list(background = "rgba(0, 0, 0, 0.02)")
            ),
            dt_notificacao = reactable::colDef(
              name = "Notificação",
              format = reactable::colFormat(
                date=T, locales = "pt-BR"
              ),
              style = list(background = "rgba(0, 0, 0, 0.02)")
            ),
            dt_inicio_tratamento = reactable::colDef(
              name = "Início do tratamento",
              format = reactable::colFormat(
                date=T, locales = "pt-BR"
              ),
              style = list(background = "rgba(0, 0, 0, 0.02)")
            ),
            idade = reactable::colDef(
              name = "Idade",
              maxWidth = 80
            ),
            sexo = reactable::colDef(
              name = "Sexo",
              maxWidth = 80
            ),
            raca_cor = reactable::colDef(
              name = "Raça/cor"
            ),
            forma = reactable::colDef(
              name = "Forma",
              style = list(background = "rgba(0, 0, 0, 0.02)")
            ),
            dt_encerramento = reactable::colDef(
              name = "Data de encerramento",
              format = reactable::colFormat(
                date=T, locales = "pt-BR"
              )
            ),
            desfecho = reactable::colDef(
              name = "Desfecho",
              cell = reactable::JS(sprintf(
                "function(cellInfo) {
                   var cores = %s;
                   return React.createElement('span', {
                     style: {backgroundColor: cores[cellInfo.value] || '%s', color: 'white',
                             padding: '5px 15px', borderRadius: '20px', display: 'inline-block',
                             fontSize: '12px', fontWeight: 'bold'}
                   }, cellInfo.value);
                 }",
                cores_js, cores_cen$tinta_3
              )),
              minWidth = 140,
              align = "center"
            ),
            tempo_aberto = reactable::colDef(
              name = "Período em aberto",
              format = reactable::colFormat(
                suffix = " dias"
              )
            ),
            georreferenciado = reactable::colDef(
              name = "Georreferenciado",
              style = list(background = "rgba(0, 0, 0, 0.02)"),
              # Simbolo de estado do guia (✓ adequado) no lugar de emoji; o
              # texto continua "Sim"/"Nao" pro filtro da coluna
              cell = reactable::JS(sprintf(
                "function(cellInfo) {
                   return cellInfo.value === 'Sim'
                     ? React.createElement('span', {style: {color: '%s', fontWeight: 700}}, '✓ Sim')
                     : React.createElement('span', {style: {color: '%s'}}, 'Não');
                 }",
                cores_cen$ok, cores_cen$tinta_3
              ))
            )
          ),
          columnGroups = list(
            reactable::colGroup(name = "Datas",
                                columns = c("dt_notificacao", "dt_diagnostico", "dt_inicio_tratamento")),
            reactable::colGroup(name = "Encerramento",
                                columns = c("dt_encerramento", "desfecho", "tempo_aberto"))
          ),
          language = reactable_idioma,
          filterable = TRUE
        )
    })

    ## Map output ----
    #
    # Mapa incremental: o mapa base (fundos, controle de camadas e visao
    # inicial) e' desenhado UMA vez por sessao, e cada camada e' atualizada
    # separadamente por leafletProxy, so' quando o que ela mostra muda:
    #   - casos e obitos so-SIM: filtros, periodo e desfechos marcados na
    #     tabela de distribuicao;
    #   - indicador por bairro/DS (ou contorno de Recife): indicador, recorte,
    #     filtros e periodo;
    #   - unidades de saude (S e ✕): filtros e periodo (o hover traz quantos
    #     casos cada unidade notificou);
    #   - contorno dos DS e areas de abrangencia da APS: fixos, desenhados
    #     uma vez.
    # Antes o mapa inteiro era recriado a cada clique -- reenviando malhas,
    # pontos e popups de todos os casos e voltando o zoom pra visao inicial.
    # Agora o usuario continua no zoom/posicao em que estava, e o popup de um
    # caso so' e' montado quando ele e' clicado.

    grupos_mapa <- c(
      "Casos", "Indicador por território", "Distritos Sanitários",
      "Áreas de abrangência (APS)", "Rede SUS (S)", "Outras notificadoras (✕)"
    )

    proxy_mapa <- function() leaflet::leafletProxy("main_map", session)

    # Com dados ficticios, selo fixo no mapa (aparece em qualquer captura de
    # tela do mapa, mesmo sem a faixa do topo da pagina)
    selo_ficticio_mapa <- function(mapa) {
      if (!ficticio) return(mapa)
      leaflet::addControl(mapa, html = "<div class='selo-ficticio selo-mapa'>DADOS FICTÍCIOS</div>",
                          position = "bottomleft")
    }

    output$main_map <- leaflet::renderLeaflet({
      # preferCanvas: pontos e poligonos desenhados num <canvas> em vez de
      # um elemento SVG por feicao -- com milhares de casos no periodo o
      # navegador desenha e move o mapa bem mais rapido. A ordem de desenho
      # (a mesma dos panes de antes) e' mantida por js_ordena_camadas.
      leaflet::leaflet(options = leaflet::leafletOptions(preferCanvas = TRUE)) |>
        # CartoDB.Positron passou a exigir API key nos tiles gratuitos --
        # trocado por Esri.WorldGrayCanvas (visual parecido: cinza claro,
        # minimalista, sem exigir chave/conta).
        leaflet::addProviderTiles("Esri.WorldGrayCanvas", group = 'Ruas') |>
        leaflet::addProviderTiles("Esri.WorldImagery",
                                  options = leaflet::providerTileOptions(opacity = 0.8),
                                  group = 'Satélite') |>
        # Rotulos fixos das unidades (S e ✕) acima de tudo
        leaflet::addMapPane("topLayer", zIndex = 500) |>
        leaflet::setView(lng = -34.92460844175653, lat = -8.051801525969324, zoom = 12) |>
        leaflet::addLayersControl(
          baseGroups = c("Ruas", "Satélite"),
          options = leaflet::layersControlOptions(collapsed = FALSE),
          overlayGroups = grupos_mapa
        ) |>
        # A abrangencia comeca desligada -- por cima do indicador ela polui a
        # leitura do mapa e captura o hover. Como o mapa nao e' mais
        # recriado, dai' em diante vale o que o usuario escolheu.
        leaflet::hideGroup("Áreas de abrangência (APS)") |>
        selo_ficticio_mapa() |>
        htmlwidgets::onRender("
          function(el, x) {
            var map = this;
            // Camada religada no controle entra no fim da ordem de desenho --
            // refaz a ordem (ver js_ordena_camadas)
            map.on('overlayadd', function() { LeafletWidget.methods.ordenaCamadas.call(map); });
            // Avisa o servidor que o mapa existe: as camadas (leafletProxy)
            // so' sao desenhadas depois disso -- chamada de proxy que chega
            // antes do mapa existir no navegador se perde.
            Shiny.setInputValue(el.id + '_renderizado', Date.now());
          }
        ")
    })

    ### Contorno dos DS e areas da APS (fixos) ----

    shiny::observe({
      shiny::req(input$main_map_renderizado)

      distritos <- distritos_shape() |> sf::st_transform(crs = 4326)

      # Areas de abrangencia da APS (territorializacao oficial da SESAU no
      # ESIG, gerada por dev/build_abrangencia_aps.R) -- desligada por padrao
      # (ver hideGroup acima): por cima do indicador, o hover passa a ser o da
      # area de abrangencia.
      abrangencia <- abrangencia_shape() |> sf::st_transform(crs = 4326)

      hover_abrangencia <- dplyr::case_when(
        abrangencia$situacao == "Coberta" ~ sprintf(
          "<b>Área de abrangência</b><br>%s<br>%s | DS %s",
          htmltools::htmlEscape(abrangencia$unidade), abrangencia$tipo, as.character(utils::as.roman(abrangencia$ds))
        ),
        abrangencia$situacao == "Descoberta" ~ sprintf(
          "<b>Área descoberta</b> (sem equipe de Saúde da Família)<br>Unidade de referência: %s",
          htmltools::htmlEscape(abrangencia$referencia)
        ),
        TRUE ~ "<b>Não se aplica</b> (área sem população adscrita)"
      ) |> lapply(htmltools::HTML)

      proxy_mapa() |>
        leaflet::clearGroup("Distritos Sanitários") |>
        leaflet::clearGroup("Áreas de abrangência (APS)") |>
        # Contorno + nome dos Distritos Sanitarios -- camada propria, liga/
        # desliga independente do indicador (serve de referencia tambem no
        # recorte por bairro). Sem interacao (clickable = FALSE) pra nao
        # roubar o hover dos poligonos de indicador por baixo.
        # Linha navy de Recife sobre um "halo" branco mais largo: continua
        # visivel sobre as paletas quentes (YlOrRd, Oranges) e frias (BuPu)
        # do indicador.
        leaflet::addPolygons(
          data = distritos,
          fill = FALSE,
          weight = 5,
          color = "#FFFFFF",
          opacity = 0.55,
          group = 'Distritos Sanitários',
          options = leaflet::pathOptions(clickable = FALSE)
        ) |>
        leaflet::addPolygons(
          data = distritos,
          fill = FALSE,
          weight = 3,
          color = navy_recife,
          opacity = 0.9,
          group = 'Distritos Sanitários',
          options = leaflet::pathOptions(clickable = FALSE)
        ) |>
        leaflet::addLabelOnlyMarkers(
          # ponto interno calculado na projecao (UTM), nao em lon/lat
          data = sf::st_point_on_surface(sf::st_geometry(distritos_shape())) |> sf::st_transform(4326),
          label = distritos$ds,
          labelOptions = leaflet::labelOptions(
            noHide = TRUE,
            direction = "center",
            textOnly = TRUE,
            style = list(
              "color" = navy_recife,
              "font-weight" = "bold",
              "font-size" = "14px",
              "text-shadow" = "-1px -1px 0 #fff, 1px -1px 0 #fff, -1px 1px 0 #fff, 1px 1px 0 #fff, 0 0 4px #fff"
            )
          ),
          group = 'Distritos Sanitários'
        ) |>
        leaflet::addPolygons(
          data = abrangencia,
          color = dplyr::case_when(abrangencia$situacao == "Coberta" ~ cores_cen$series[3], TRUE ~ cores_cen$tinta_3),
          weight = 1.5,
          opacity = 0.9,
          dashArray = ifelse(abrangencia$situacao == "Não se aplica", "4", NA),
          fillColor = dplyr::case_when(abrangencia$situacao == "Coberta" ~ cores_cen$series[3], TRUE ~ cores_cen$tinta_3),
          # Preenchimento quase transparente nas cobertas so' pra capturar o
          # hover sem esconder o indicador; descobertas em cinza.
          fillOpacity = dplyr::case_when(
            abrangencia$situacao == "Coberta" ~ 0.05,
            abrangencia$situacao == "Descoberta" ~ 0.35,
            TRUE ~ 0
          ),
          highlightOptions = leaflet::highlightOptions(weight = 3, color = cores_cen$tinta, bringToFront = FALSE),
          label = hover_abrangencia,
          labelOptions = leaflet::labelOptions(textsize = "13px", direction = "auto"),
          group = 'Áreas de abrangência (APS)'
        ) |>
        leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    ### Indicador por territorio (bairro / DS) ----

    shiny::observe({
      shiny::req(input$main_map_renderizado)

      m <- proxy_mapa() |>
        leaflet::clearGroup("Indicador por território") |>
        leaflet::clearGroup("Recife") |>
        leaflet::removeControl("legenda_indicador")

      if (isTRUE(input$show_indicador_bairro)) {

        ind_terr <- (if (input$nivel_territorial == "ds") ind_ds() else ind_bair()) |>
          sf::st_transform(crs = 4326)

        # Opacidade do mapa de indicadores (mesma de antes da adequacao ao guia)
        opacidade_ind <- 0.7

        if (input$indicador_bairro == "inc") {

          periodo_anos <- pmax(1, as.numeric(periodo_ativo()[2] - periodo_ativo()[1])/365)

          ind_terr$ind <- ind_terr$ind/periodo_anos

          # Cores por quantil (pedido do coordenador do projeto) -- cada
          # cor cobre a mesma quantidade de bairros/DS, em vez de faixas de
          # valor fixas. Ver pal_quantil() no topo do arquivo.
          pal_ind <- pal_quantil(paletas_indicador[["inc"]], domain = ind_terr$ind, n = 5)

          inc_labels <- sprintf(
            "<strong>%s</strong><br>Casos no período: <b>%s</b><br>População (2022): <b>%s</b><br>Incidência anual: <b>%s</b> casos por 100.000 hab./ano",
            ind_terr$nome_territorio,
            format(ind_terr$casos, big.mark=".", decimal.mark=","),
            format(ind_terr$pop, big.mark=".", decimal.mark=","),
            format(round(ind_terr$ind, 1), big.mark=".", decimal.mark=",")
          ) %>% lapply(htmltools::HTML)

          indicator_title <- "Incidência anual"
          formato_ind <- formato_legenda(digitos = 1)

        } else if (input$indicador_bairro == "mort") {

          periodo_anos <- pmax(1, as.numeric(periodo_ativo()[2] - periodo_ativo()[1])/365)

          ind_terr$ind <- ind_terr$ind/periodo_anos

          bins <- c(0, 10, 50, 75, 100, 200, 500, 1000, Inf)/10
          pal_ind <- leaflet::colorBin(paletas_indicador[["mort"]], domain = ind_terr$ind, bins = bins)

          inc_labels <- sprintf(
            "<strong>%s</strong><br>Óbitos por TB no período: <b>%s</b><br>População (2022): <b>%s</b><br>Mortalidade anual: <b>%s</b> óbitos por 100.000 hab./ano",
            ind_terr$nome_territorio,
            format(ind_terr$obitos, big.mark=".", decimal.mark=","),
            format(ind_terr$pop, big.mark=".", decimal.mark=","),
            format(round(ind_terr$ind, 1), big.mark=".", decimal.mark=",")
          ) %>% lapply(htmltools::HTML)

          indicator_title <- "Mortalidade anual por TB"
          formato_ind <- formato_legenda(digitos = 1)

        } else if (input$indicador_bairro == "let") {

          bins <- c(0, 0.01, 0.025, 0.05, 0.1, 0.15, 0.2, Inf)
          pal_ind <- leaflet::colorBin(paletas_indicador[["let"]], domain = ind_terr$ind, bins = bins)

          inc_labels <- sprintf(
            "<strong>%s</strong><br>Óbitos por TB no período: <b>%s</b><br>Casos encerrados no período: <b>%s</b><br>Letalidade: <b>%s</b>",
            ind_terr$nome_territorio,
            format(ind_terr$obitos, big.mark=".", decimal.mark=","),
            format(ind_terr$encerrados, big.mark=".", decimal.mark=","),
            scales::percent(ind_terr$ind, accuracy = 0.01, big.mark=".", decimal.mark=",")
          ) %>% lapply(htmltools::HTML)

          indicator_title <- "Letalidade (%)"
          formato_ind <- formato_legenda(percentual = TRUE, digitos = 1)


        } else if (input$indicador_bairro == "prop_cura") {

          bins <- c(0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,  Inf)
          pal_ind <- leaflet::colorBin(paletas_indicador[["prop_cura"]], domain = ind_terr$ind, bins = bins)

          inc_labels <- sprintf(
            "<strong>%s</strong><br>Curados: <b>%s</b><br>Casos de TB encerrados no período: <b>%s</b><br>Prop. Cura: <b>%s</b>",
            ind_terr$nome_territorio,
            format(ind_terr$curados, big.mark=".", decimal.mark=","),
            format(ind_terr$encerrados, big.mark=".", decimal.mark=","),
            scales::percent(ind_terr$ind, accuracy = 0.01, big.mark=".", decimal.mark=",")
          ) %>% lapply(htmltools::HTML)

          indicator_title <- "Prop. Cura (%)"
          formato_ind <- formato_legenda(percentual = TRUE, digitos = 0)

        } else if (input$indicador_bairro == "prop_aband") {

          bins <- c(0, 0.1, 0.2, 0.3, 0.4, 0.5, Inf)
          pal_ind <- leaflet::colorBin(paletas_indicador[["prop_aband"]], domain = ind_terr$ind, bins = bins)

          inc_labels <- sprintf(
            "<strong>%s</strong><br>Abandono ou falência: <b>%s</b><br>Casos de TB encerrados no período: <b>%s</b><br>Prop. Abandono: <b>%s</b>",
            ind_terr$nome_territorio,
            format(ind_terr$aband, big.mark=".", decimal.mark=","),
            format(ind_terr$encerrados, big.mark=".", decimal.mark=","),
            scales::percent(ind_terr$ind, accuracy = 0.01, big.mark=".", decimal.mark=",")
          ) %>% lapply(htmltools::HTML)

          indicator_title <- "Prop. Abandono (%)"
          formato_ind <- formato_legenda(percentual = TRUE, digitos = 0)

        }

        m <- m |>
          leaflet::addPolygons(
            data = ind_terr,
            fillColor = pal_ind(ind_terr$ind),
             weight = 1,
             opacity = 1,
             color = "white",
             dashArray = "3",
             fillOpacity = opacidade_ind,
             group = 'Indicador por território',
            highlightOptions = leaflet::highlightOptions(
              weight = 2,
              color = cores_cen$tinta_2,
              dashArray = "",
              fillOpacity = opacidade_ind,
              bringToFront = F),
            label = inc_labels,
            labelOptions = leaflet::labelOptions(
              style = list("font-weight" = "normal", padding = "3px 8px"),
              textsize = "15px",
              direction = "auto")
          ) |>
          leaflet::addLegend(pal = pal_ind, values = ind_terr$ind, opacity = opacidade_ind, title = indicator_title, labFormat = formato_ind,
                             position = "bottomright", layerId = "legenda_indicador")
      } else {
        # Shape

        m <- m |>
          leaflet::addPolygons(
            data = map_shape() |> sf::st_transform(crs = 4326),
            weight = 2,
            color = cores_cen$azul,
            fillOpacity = 0.2,
            group = 'Recife'
          )
      }

      m |> leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    ### Unidades de saude (CNES) ----

    # Unidades de saude (CNES), com contagem de casos notificados no
    # filtro/periodo atual no hover: "S" vermelho pra rede publica/SUS
    # (natureza juridica de administracao publica -- ver
    # dev/build_unidades_cnes.R), inclusive as que nao notificaram nenhum
    # caso; "✕" pras demais unidades notificadoras (privadas,
    # filantropicas, ou de cache antigo sem a classificacao).
    shiny::observe({
      shiny::req(input$main_map_renderizado)

      m <- proxy_mapa() |>
        leaflet::clearGroup("Rede SUS (S)") |>
        leaflet::clearGroup("Outras notificadoras (✕)")

      unidades_geo <- unidades_cnes()

      if (nrow(unidades_geo) > 0) {
        contagem_unidade <- casos_filtered() |>
          sf::st_drop_geometry() |>
          dplyr::filter(!is.na(cod_unidade_notificadora), cod_unidade_notificadora != "") |>
          dplyr::count(cod_unidade_notificadora, name = "n_casos")

        unidades_geo <- unidades_geo |>
          dplyr::left_join(contagem_unidade, by = c("codigo_cnes" = "cod_unidade_notificadora")) |>
          dplyr::mutate(
            n_casos = dplyr::coalesce(n_casos, 0L),
            nome = htmltools::htmlEscape(ifelse(is.na(nome_fantasia) | nome_fantasia == "", razao_social, nome_fantasia)),
            descricao = dplyr::case_when(
              !is.na(tipo_unidade) & !is.na(natureza) ~ paste(tipo_unidade, natureza, sep = " · "),
              TRUE ~ dplyr::coalesce(tipo_unidade, natureza)
            )
          )

        m <- m |>
          adicionar_camada_unidades(
            unidades_geo |> dplyr::filter(publica %in% TRUE),
            simbolo = "S",
            estilo = estilo_unidade_sus,
            grupo = 'Rede SUS (S)'
          ) |>
          adicionar_camada_unidades(
            unidades_geo |> dplyr::filter(!publica %in% TRUE),
            simbolo = "✕",
            estilo = estilo_unidade_outras,
            grupo = 'Outras notificadoras (✕)'
          )
      }

      m |> leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    ### Casos no mapa ----

    # Pontos desenhados no mapa agora (casos e obitos so-SIM), na ordem dos
    # ids "caso_<n>" -- o popup do clique e' montado a partir daqui.
    casos_desenhados <- shiny::reactiveVal(NULL)

    shiny::observe({
      shiny::req(input$main_map_renderizado)

      casos <- casos_points() |>
        dplyr::filter(georreferenciado == 1, !sf::st_is_empty(geometry)) |>
        sf::st_transform(crs = 4326)

      m <- proxy_mapa() |>
        leaflet::clearGroup("Casos")

      if (nrow(casos) > 0) {
        label_info <- sprintf(
          "%s, %s ano%s, %s: <b>%s</b>",
          casos$sexo,
          floor(casos$idade),
          ifelse(floor(casos$idade) == 1, "", "s"),
          casos$raca_cor,
          casos$desfecho
        ) |> lapply(htmltools::HTML)

        # levels explicitos: cor e ordem da legenda seguem cores_desfecho
        # (sem depender da ordenacao alfabetica do locale)
        pal <- leaflet::colorFactor(unname(cores_desfecho), domain = NULL, levels = names(cores_desfecho))

        m <- m |>
          leaflet::addCircleMarkers(
            data = casos,
            # "caso_<n>": linha de casos_desenhados(), pro popup do clique
            layerId = paste0("caso_", seq_len(nrow(casos))),
            radius = 4.5,
            fillColor = pal(casos$desfecho),
            fillOpacity = 0.95,
            # contorno branco fino: destaca o ponto sobre qualquer cor do
            # indicador por baixo (os "Em aberto", azuis, sumiam na escala azul)
            stroke = TRUE,
            color = "#FFFFFF",
            weight = 0.75,
            opacity = 0.6,
            label = label_info,
            group = 'Casos',
            # Sem pane proprio: no Leaflet 1.3 que vem com o pacote leaflet,
            # pane personalizado sempre desenha em SVG (ignora preferCanvas),
            # e SVG por cima do canvas roubaria o hover das camadas de baixo.
            # A ordem entre casos e malhas/unidades e' mantida por
            # js_ordena_camadas.
            options = leaflet::pathOptions()
          ) |> leaflet::addLegend(
            pal = pal, values = casos$desfecho,
            # labFormat = alt_labelFormat(big.mark = ".", digits = 2),
            opacity = 0.7, title = NULL,
            position = "bottomleft",
            layerId = "legenda_casos"
          )
      } else {
        m <- m |> leaflet::removeControl("legenda_casos")
      }

      casos_desenhados(casos)

      # Casos redesenhados entram no fim da ordem -- os circulos das unidades
      # voltam pra cima deles
      m |> leaflet::invokeMethod(NULL, "ordenaCamadas")
    })

    # Popup do caso clicado, montado na hora -- nenhum popup vai junto com os
    # pontos.
    shiny::observeEvent(input$main_map_marker_click, {
      clique <- input$main_map_marker_click
      if (is.null(clique$id) || !startsWith(clique$id, "caso_")) return()

      casos <- casos_desenhados()
      n <- suppressWarnings(as.integer(sub("^caso_", "", clique$id)))
      if (is.null(casos) || is.na(n) || n < 1 || n > nrow(casos)) return()

      proxy_mapa() |>
        leaflet::addPopups(
          lng = clique$lng, lat = clique$lat,
          popup = popup_caso(casos[n, ]),
          layerId = "popup_caso"
        )
    })




  })
}
