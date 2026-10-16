PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS stations (
  station_id INTEGER PRIMARY KEY,
  name       TEXT NOT NULL UNIQUE,
  lat        REAL NOT NULL,
  lon        REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS readings (
  station_id    INTEGER NOT NULL REFERENCES stations(station_id),
  ts            TEXT    NOT NULL,          -- ISO 8601, UTC
  temperature_c REAL,
  precip_mm     REAL,
  wind_kmh      REAL,
  PRIMARY KEY (station_id, ts)             -- prevents duplicates on reruns
);

CREATE INDEX IF NOT EXISTS idx_readings_ts ON readings(ts);

CREATE VIEW IF NOT EXISTS daily_stats AS
SELECT station_id,
       date(ts)            AS day,
       ROUND(AVG(temperature_c), 2) AS avg_temp,
       MIN(temperature_c)  AS min_temp,
       MAX(temperature_c)  AS max_temp,
       ROUND(SUM(precip_mm), 2)     AS total_precip
FROM readings
GROUP BY station_id, date(ts);
