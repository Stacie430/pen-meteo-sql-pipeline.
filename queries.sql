-- 1) 7-day moving average of daily temperature
SELECT station_id, day, avg_temp,
       ROUND(AVG(avg_temp) OVER (
         PARTITION BY station_id ORDER BY day
         ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS ma_7d
FROM daily_stats;

-- 2) Warmest station per day
SELECT day, name, avg_temp
FROM (
  SELECT d.day, s.name, d.avg_temp,
         RANK() OVER (PARTITION BY d.day ORDER BY d.avg_temp DESC) AS rnk
  FROM daily_stats d JOIN stations s USING (station_id)
)
WHERE rnk = 1;

-- 3) Anomalies: hourly readings > 2 standard deviations from the station mean
WITH stats AS (
  SELECT station_id,
         AVG(temperature_c) AS mu,
         SQRT(AVG(temperature_c * temperature_c) - AVG(temperature_c) * AVG(temperature_c)) AS sigma
  FROM readings GROUP BY station_id
)
SELECT r.station_id, r.ts, r.temperature_c,
       ROUND((r.temperature_c - s.mu) / s.sigma, 2) AS z_score
FROM readings r JOIN stats s USING (station_id)
WHERE s.sigma > 0 AND ABS(r.temperature_c - s.mu) > 2 * s.sigma
ORDER BY ABS(z_score) DESC;
