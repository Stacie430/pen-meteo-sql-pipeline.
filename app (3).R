# install.packages(c("shiny", "DBI", "RSQLite", "ggplot2"))
library(shiny)
library(DBI)
library(RSQLite)
library(ggplot2)

resolve_db_path <- function() {
  cwd_path <- file.path(getwd(), "wetter.sqlite")
  arg_file <- commandArgs(trailingOnly = FALSE)
  arg_file <- arg_file[grepl("^--file=", arg_file)]
  script_path <- if (length(arg_file) > 0) sub("^--file=", "", arg_file[1]) else ""
  script_path <- normalizePath(script_path, mustWork = FALSE)
  script_db_path <- if (nzchar(script_path)) file.path(dirname(script_path), "wetter.sqlite") else ""

  if (file.exists(cwd_path)) {
    return(cwd_path)
  }
  if (nzchar(script_db_path) && file.exists(script_db_path)) {
    return(script_db_path)
  }

  cwd_path
}

db_path <- resolve_db_path()

query <- function(sql, params = list()) {
  if (!file.exists(db_path)) {
    stop(
      "Datenbank nicht gefunden: ",
      normalizePath(db_path, mustWork = FALSE),
      call. = FALSE
    )
  }

  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con), add = TRUE)
  dbGetQuery(con, sql, params = params)
}

load_metadata <- function() {
  stations <- query("SELECT station_id, name FROM stations ORDER BY name")
  bounds <- query("SELECT MIN(date(ts)) AS d_min, MAX(date(ts)) AS d_max FROM readings")

  if (nrow(stations) == 0) {
    stop("Keine Stationen in der Datenbank gefunden.", call. = FALSE)
  }
  if (nrow(bounds) == 0 || is.na(bounds$d_min[1]) || is.na(bounds$d_max[1])) {
    stop("Keine Messdaten für den Datumsbereich gefunden.", call. = FALSE)
  }

  list(stations = stations, bounds = bounds)
}

meta <- load_metadata()

ui <- fluidPage(
  titlePanel("Wetter-Pipeline"),
  sidebarLayout(
    sidebarPanel(
      selectInput("station", "Station",
                  choices = setNames(meta$stations$station_id, meta$stations$name)),
      dateRangeInput("range", "Zeitraum",
                     start = meta$bounds$d_min, end = meta$bounds$d_max,
                     min = meta$bounds$d_min, max = meta$bounds$d_max),
      sliderInput("z", "Anomalie-Schwelle (z-Score)", min = 1, max = 4,
                  value = 2, step = 0.5),
      actionButton("refresh", "Daten neu laden")
    ),
    mainPanel(
      plotOutput("daily_plot"),
      h4("Anomalien (stündlich)"),
      tableOutput("anomalies")
    )
  )
)

server <- function(input, output, session) {

  metadata <- eventReactive(input$refresh, {
    load_metadata()
  }, ignoreNULL = FALSE)

  observeEvent(metadata(), {
    m <- metadata()
    choices <- setNames(m$stations$station_id, m$stations$name)
    selected_station <- isolate(input$station)
    choice_values <- as.character(unname(choices))
    if (!isTruthy(selected_station) || !as.character(selected_station) %in% choice_values) {
      selected_station <- choice_values[1]
    }

    updateSelectInput(
      session,
      "station",
      choices = choices,
      selected = selected_station
    )

    min_day <- as.Date(m$bounds$d_min[1])
    max_day <- as.Date(m$bounds$d_max[1])
    selected_range <- isolate(input$range)

    start_day <- min_day
    end_day <- max_day
    if (!is.null(selected_range) && length(selected_range) == 2) {
      start_day <- as.Date(selected_range[1])
      end_day <- as.Date(selected_range[2])
      start_day <- min(max(start_day, min_day), max_day)
      end_day <- min(max(end_day, min_day), max_day)
      if (start_day > end_day) {
        start_day <- min_day
        end_day <- max_day
      }
    }

    updateDateRangeInput(
      session,
      "range",
      start = start_day,
      end = end_day,
      min = min_day,
      max = max_day
    )
  }, ignoreInit = FALSE)

  daily <- eventReactive(list(input$refresh, input$station, input$range), {
    req(input$station, input$range)
    start_day <- format(as.Date(input$range[1]), "%Y-%m-%d")
    end_day <- format(as.Date(input$range[2]), "%Y-%m-%d")
    query(
      "SELECT day, avg_temp, min_temp, max_temp
       FROM daily_stats
       WHERE station_id = ? AND day BETWEEN ? AND ?
       ORDER BY day",
      params = list(input$station,
                    start_day,
                    end_day)
    )
  }, ignoreNULL = FALSE)

  output$daily_plot <- renderPlot({
    d <- daily()
    d$avg_temp <- suppressWarnings(as.numeric(d$avg_temp))
    d$min_temp <- suppressWarnings(as.numeric(d$min_temp))
    d$max_temp <- suppressWarnings(as.numeric(d$max_temp))
    validate(
      need(nrow(d) > 0, "Keine Daten im gewählten Zeitraum."),
      need(any(is.finite(d$avg_temp)), "Keine gültigen Temperaturdaten verfügbar.")
    )
    d$day <- as.Date(d$day)
    d$ma7 <- as.numeric(stats::filter(d$avg_temp, rep(1 / 7, 7), sides = 1))
    ggplot(d, aes(day)) +
      geom_ribbon(aes(ymin = min_temp, ymax = max_temp), alpha = 0.2, na.rm = TRUE) +
      geom_line(aes(y = avg_temp), linewidth = 1, na.rm = TRUE) +
      geom_line(aes(y = ma7), linetype = "dashed", na.rm = TRUE) +
      labs(x = NULL, y = "Temperatur (°C)",
           subtitle = "Linie = Tagesmittel, Band = Min/Max, gestrichelt = 7-Tage-Mittel") +
      theme_minimal()
  })

  anomalies <- eventReactive(list(input$refresh, input$station, input$range, input$z), {
    req(input$station, input$range, input$z)
    start_day <- format(as.Date(input$range[1]), "%Y-%m-%d")
    end_day <- format(as.Date(input$range[2]), "%Y-%m-%d")
    r <- query(
      "SELECT ts, temperature_c FROM readings
       WHERE station_id = ? AND date(ts) BETWEEN ? AND ? AND temperature_c IS NOT NULL
       ORDER BY ts",
      params = list(input$station, start_day, end_day)
    )
    r$temperature_c <- suppressWarnings(as.numeric(r$temperature_c))
    validate(
      need(nrow(r) > 2, "Zu wenige Daten für die Anomalieanalyse."),
      need(any(is.finite(r$temperature_c)), "Keine gültigen Temperaturdaten für die Anomalieanalyse.")
    )
    mu <- mean(r$temperature_c, na.rm = TRUE)
    s <- stats::sd(r$temperature_c, na.rm = TRUE)
    validate(need(is.finite(s) && s > 0, "Keine Anomalien möglich: Die Temperaturwerte sind konstant oder ungültig."))
    r$z_score <- round((r$temperature_c - mu) / s, 2)
    out <- r[is.finite(r$z_score) & abs(r$z_score) > input$z, , drop = FALSE]
    out <- out[order(-abs(out$z_score)), , drop = FALSE]
    if (nrow(out) == 0) {
      return(data.frame(Hinweis = "Keine Anomalien im gewählten Zeitraum gefunden."))
    }
    head(out, 10)
  }, ignoreNULL = FALSE)

  output$anomalies <- renderTable({
    anomalies()
  })
}

shinyApp(ui, server)
