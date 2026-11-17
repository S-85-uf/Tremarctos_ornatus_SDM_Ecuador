# ==============================================================================
# SCRIPT MAESTRO DE PREPARACIÓN AMBIENTAL Y SELECCIÓN DE VARIABLES v1.0
# Compatible con salidas de: Script Maestro de Ocurrencias (GBIF / Polígono M)
# ==============================================================================

library(terra)
library(sf)
library(geodata)
library(dplyr)

# ==============================================================================
# BLOQUE CERO: PARÁMETROS DEL PROYECTO (SOLO EDITAR ESTA SECCIÓN)
# ==============================================================================
especie          <- "Tremarctos ornatus"   # Nombre científico exacto
pais_iso         <- "ECU"                  # Código ISO3 del país para el DEM (ej. "ECU", "PER", "COL")
ruta_base        <- "/run/media/alexc/HDD/TRABAJO/R" # Carpeta raíz donde están tus proyectos
ruta_chelsa      <- "/run/media/alexc/HDD/TRABAJO/BIOCLIMA/CHELSA/CHELSA_BIOCLIM_1981-2010"

# Interruptores (Switches) de control
incluir_dem      <- TRUE   # ¿Incluir elevación SRTM (~1 km)?
incluir_pendiente<- TRUE   # ¿Calcular pendiente en grados?
incluir_tpi      <- TRUE   # ¿Calcular Índice de Posición Topográfica (crestas/valles)?
umbral_cor       <- 0.7    # Umbral de correlación de Pearson (|r| <= 0.7)
# ==============================================================================

# 1. CONSTRUCCIÓN AUTOMÁTICA DE RUTAS Y ARCHIVOS --------------------------------
nombre_archivo <- gsub(" ", "_", especie)
ruta_proyecto  <- file.path(ruta_base, nombre_archivo)
setwd(ruta_proyecto)

carpeta_salida <- paste0("capas_maxent_", nombre_archivo)
dir.create(carpeta_salida, showWarnings = FALSE)
dir.create("datos_clima", showWarnings = FALSE)

# Cargar automáticamente los archivos generados por el Script Maestro de Ocurrencias
puntos_sf  <- readRDS(paste0(nombre_archivo, "_puntos_finales.rds"))
pol_vect   <- readRDS(paste0(nombre_archivo, "_poligono_M.rds"))
pts_vect   <- vect(puntos_sf, geom = c("decimalLongitude", "decimalLatitude"), crs = "EPSG:4326")

# 2. CARGA DE CLIMA (CHELSA) Y DESCARGA OPCIONAL DE TOPOGRAFÍA -----------------
archivos_bio <- list.files(ruta_chelsa, pattern = "\\.tif$", full.names = TRUE)
cat("Cargando", length(archivos_bio), "capas climáticas de CHELSA...\n")
chelsa_stack <- rast(archivos_bio)
variables_m  <- mask(crop(chelsa_stack, pol_vect), pol_vect)

if (incluir_dem == TRUE) {
  cat("Descargando/cargando DEM SRTM para", pais_iso, "...\n")
  dem_pais <- geodata::elevation_30s(country = pais_iso, path = "datos_clima/")
  names(dem_pais) <- "elevacion_dem"
  
  capas_topo <- dem_pais
  if (incluir_pendiente == TRUE) {
    pend <- terrain(dem_pais, v = "slope", unit = "degrees")
    names(pend) <- "pendiente"
    capas_topo <- c(capas_topo, pend)
  }
  if (incluir_tpi == TRUE) {
    tpi <- terrain(dem_pais, v = "TPI")
    names(tpi) <- "tpi"
    capas_topo <- c(capas_topo, tpi)
  }
  
  topo_m        <- mask(crop(capas_topo, pol_vect), pol_vect)
  topo_alineado <- resample(topo_m, variables_m[[1]], method = "bilinear")
  variables_m   <- c(variables_m, topo_alineado)
}

# 3. FILTRO ESTADÍSTICO DE MULTICOLINEALIDAD (CORRELACIÓN DE PEARSON) ----------
valores_pts <- na.omit(terra::extract(variables_m, pts_vect, ID = FALSE))
matriz_cor  <- cor(valores_pts, method = "pearson")

seleccionar_variables <- function(mat_cor, umbral = 0.7) {
  vars <- colnames(mat_cor)
  while (TRUE) {
    abs_cor <- abs(mat_cor)
    diag(abs_cor) <- 0
    if (max(abs_cor) <= umbral) break
    peor_var <- names(which.max(colMeans(abs_cor)))
    vars     <- setdiff(vars, peor_var)
    mat_cor  <- mat_cor[vars, vars, drop = FALSE]
  }
  return(vars)
}

vars_seleccionadas <- seleccionar_variables(matriz_cor, umbral = umbral_cor)
cat("\n=== VARIABLES SELECCIONADAS PARA", toupper(especie), "===\n")
print(vars_seleccionadas)

# 4. EXPORTAR CAPAS FINALES Y REPORTE HTML -------------------------------------
capas_finales <- variables_m[[vars_seleccionadas]]
for (v in names(capas_finales)) {
  writeRaster(capas_finales[[v]], filename = file.path(carpeta_salida, paste0(v, ".tif")), overwrite = TRUE)
}

n_total  <- ncol(matriz_cor)
img_name <- paste0(nombre_archivo, "_correlacion.png")

png(img_name, width = 1100, height = 550)
par(mfrow = c(1, 2))
image(1:n_total, 1:n_total, t(matriz_cor)[, n_total:1], col = hcl.colors(20, "Blue-Red 3"),
      axes = FALSE, main = paste0("Matriz Pearson (", n_total, " candidatas)"), xlab = "", ylab = "")
axis(1, at = 1:n_total, labels = colnames(matriz_cor), las = 2, cex.axis = 0.6)
axis(2, at = 1:n_total, labels = rev(rownames(matriz_cor)), las = 2, cex.axis = 0.6)
plot(capas_finales[[1]], main = paste("Capa recortada:", names(capas_finales)[1]))
plot(pts_vect, add = TRUE, pch = 16, cex = 0.6, col = "black")
dev.off()
# Texto dinámico para la viñeta de Topografía según tus switches del Bloque Cero
capas_activas <- c(
  if(incluir_dem) "Modelo Digital de Elevación (DEM SRTM 30s)",
  if(incluir_pendiente) "Pendiente (grados)",
  if(incluir_tpi) "Índice de Posición Topográfica (TPI)"
)
texto_topo <- if(length(capas_activas) > 0) {
  paste(paste(capas_activas, collapse = ", "), "alineados a la grilla climática.")
} else {
  "Solo variables bioclimáticas (sin capas topográficas)."
}

html_out <- paste0(
  "<html><head><meta charset='UTF-8'><title>Selección Ambiental - ", especie, "</title>",
  "<style>body{font-family:Arial,sans-serif;max-width:900px;margin:auto;padding:20px;line-height:1.6;}",
  "h1,h2{color:#2c5e3b;} .box{background:#f4f7f5;padding:15px;border-left:5px solid #2c5e3b;}</style></head><body>",
  "<h1>Preparación Ambiental y Selección de Variables: <i>", especie, "</i></h1>",
  "<p><b>Fecha:</b> ", Sys.Date(), " | <b>Área de estudio:</b> Polígono M (", pais_iso, ") | <b>Registros independientes:</b> ", nrow(valores_pts), "</p>",
  "<div class='box'><h2>Metodología Aplicada</h2><ul>",
  "<li><b>Datos Climáticos:</b> 19 variables bioclimáticas CHELSA (1981–2010) a resolución 30s (~1 km).</li>",
  "<li><b>Topografía:</b> ", texto_topo, "</li>",
  "<li><b>Recorte espacial:</b> Enmascarado estricto al área accesible (Polígono M).</li>",
  "<li><b>Filtro de multicolinealidad:</b> Correlación de Pearson con umbral |r| &le; ", umbral_cor, ".</li></ul></div>",
  "<h2>Variables Seleccionadas para MaxEnt (", length(vars_seleccionadas), " de ", n_total, ")</h2>",
  "<p><code>", paste(vars_seleccionadas, collapse = ", "), "</code></p>",
  "<h2>Diagnóstico Visual</h2><img src='", img_name, "' style='width:100%;border:1px solid #ccc;'/>",
  "</body></html>"
)

reporte_name <- paste0(nombre_archivo, "_variables_reporte.html")
writeLines(html_out, reporte_name)
cat("\n¡Proceso completado! Reporte guardado como:", reporte_name, "\n")
