# pen-meteo-sql-pipeline.
Automated ETL pipeline: Open-Meteo weather data → SQLite, analyzed with SQL window functions, visualized in Shiny.  
# Open-Meteo SQL Pipeline

An automated ETL pipeline that pulls hourly weather data from the [Open-Meteo API](https://open-meteo.com/) into a SQLite database, analyzes it with SQL (window functions, CTEs, views), and visualizes it in a Shiny dashboard.

## Features

- **Extract:** hourly temperature, precipitation and wind for several cities via the Open-Meteo API
- **Load:** idempotent upserts (`ON CONFLICT DO UPDATE`), so reruns never create duplicates
- **Transform / analyze:** daily aggregates (view), 7-day moving averages, rankings, z-score anomaly detection
- **Automate:** daily scheduled run with GitHub Actions (or Windows Task Scheduler locally)
- **Visualize:** Shiny dashboard with station selection, date range and anomaly threshold

## Data model

```mermaid
erDiagram
    stations ||--o{ readings : has
    stations {
        INTEGER station_id PK
        TEXT name
        REAL lat
        REAL lon
    }
    readings {
        INTEGER station_id PK, FK
        TEXT ts PK
        REAL temperature_c
        REAL precip_mm
        REAL wind_kmh
    }
```

`daily_stats` is a view over `readings` (daily mean, min, max temperature and total precipitation per station).

## Project structure

| File | Purpose |
|---|---|
| `schema.sql` | Tables, index and the `daily_stats` view |
| `ingest.R` | Fetches data from the API and upserts it into `wetter.sqlite` |
| `queries.sql` | Example analyses: moving average, warmest station per day, anomalies |
| `app.R` | Shiny dashboard |
| `run_ingest.bat` | Launcher for Windows Task Scheduler |
| `.github/workflows/ingest.yml` | Daily automated run on GitHub Actions |

## Getting started

```r
install.packages(c("DBI", "RSQLite", "httr2", "shiny", "ggplot2"))
source("ingest.R")        # creates wetter.sqlite and loads the data
shiny::runApp("app.R")    # starts the dashboard
```

## Example queries

```sql
-- 7-day moving average per station
SELECT station_id, day, avg_temp,
       ROUND(AVG(avg_temp) OVER (
         PARTITION BY station_id ORDER BY day
         ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma_7d
FROM daily_stats;
```

More in [`queries.sql`](queries.sql).

## Automation

The workflow in `.github/workflows/ingest.yml` runs daily at 06:00 UTC, executes `ingest.R` and commits the updated `wetter.sqlite` back to the repository. It can also be started manually from the **Actions** tab.

## Tech stack

R · SQLite · SQL (window functions, CTEs, views) · Shiny · GitHub Actions

## Data source

Weather data by [Open-Meteo](https://open-meteo.com/) (CC BY 4.0).
