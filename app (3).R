# install.packages(c("shiny", "DBI", "RSQLite", "ggplot2"))
library(shiny)
library(DBI)
library(RSQLite)
library(ggplot2)

db_path <- "wetter.sqlite"

query <- function(sql, params = NULL) {
  con <- dbConnect(SQLite(), db_path)
  on.exit(dbDisconnect(con))
  dbGetQuery(con, sql, params = params)
}

stations <- query("SELECT station_id, name FROM stations ORDER BY name")
bounds   <- query("SELECT MIN(date(ts)) AS d_min, MAX(date(ts)) AS d_max FROM readings")

ui <- fluidPage(
  titlePanel("Wetter-Pipeline"),
  sidebarLayout(
    sidebarPanel(
      selectInput("station", "Station",
                  choices = setNames(stations$station_id, stations$name)),
      dateRangeInput("range", "Zeitraum",
                     start = bounds$d_min, end = bounds$d_max,
                     min = bounds$d_min, max = bounds$d_max),
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

  daily <- reactive({
    input$refresh
    query(
      "SELECT day, avg_temp, min_temp, max_temp, total_precip
       FROM daily_stats
       WHERE station_id = ? AND day BETWEEN ? AND ?
       ORDER BY day",
      params = list(input$station,
                    as.character(input$range[1]),
                    as.character(input$range[2]))
    )
  })

  output$daily_plot <- renderPlot({
    d <- daily()
    validate(need(nrow(d) > 0, "Keine Daten im gewählten Zeitraum."))
    d$day <- as.Date(d$day)
    d$ma7 <- stats::filter(d$avg_temp, rep(1 / 7, 7), sides = 1)
    ggplot(d, aes(day)) +
      geom_ribbon(aes(ymin = min_temp, ymax = max_temp), alpha = 0.2) +
      geom_line(aes(y = avg_temp), linewidth = 1) +
      geom_line(aes(y = ma7), linetype = "dashed", na.rm = TRUE) +
      labs(x = NULL, y = "Temperatur (°C)",
           subtitle = "Linie = Tagesmittel, Band = Min/Max, gestrichelt = 7-Tage-Mittel") +
      theme_minimal()
  })

  output$anomalies <- renderTable({
    input$refresh
    r <- query(
      "SELECT ts, temperature_c FROM readings
       WHERE station_id = ? AND temperature_c IS NOT NULL",
      params = list(input$station)
    )
    validate(need(nrow(r) > 2, "Zu wenige Daten."))
    mu <- mean(r$temperature_c); s <- sd(r$temperature_c)
    r$z_score <- round((r$temperature_c - mu) / s, 2)
    out <- r[abs(r$z_score) > input$z, ]
    out[order(-abs(out$z_score)), ][seq_len(min(10, nrow(out))), ]
  })
}

shinyApp(ui, server)
