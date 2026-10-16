@echo off
REM Ordner dieser Datei als Arbeitsverzeichnis, damit schema.sql und wetter.sqlite gefunden werden
cd /d "%~dp0"
"C:\Program Files\R\R-4.4.1\bin\Rscript.exe" ingest.R >> ingest_log.txt 2>&1
