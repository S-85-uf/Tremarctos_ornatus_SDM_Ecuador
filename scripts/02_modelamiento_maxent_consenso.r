# ==============================================================================
# SCRIPT MAESTRO DE MODELAMIENTO Y EVALUACIÓN DE NICHO ECOLÓGICO (v1.0)
# Fase 3: Calibración (ENMeval) + Ejecución Oficial (maxent.jar) + Mapa Final
# ==============================================================================

library(terra)
library(sf)
library(dismo)
library(rJava)
library(ENMeval)
library(dplyr)

# ==============================================================================
# BLOQUE CERO: PARÁMETROS DEL MODELO (SOLO EDITAR ESTA SECCIÓN)
# ==============================================================================
especie        <- "Tremarctos ornatus"
ruta_base      <- "/run/media/alexc/HDD/TRABAJO/R"
ruta_maxent    <- "/run/media/alexc/HDD/TRABAJO/MAXENT/maxent.jar"

# Interruptor de Validación: "block" (4 bloques espaciales) o "randomkfold" (aleatorio)
metodo_val     <- "block"   
k_folds        <- 5         # Solo se usa si metodo_val = "randomkfold"

# Parámetros de calibración de MaxEnt
n_background   <- 10000     # Puntos de fondo dentro del Polígono M
reg_mult       <- c(0.5, 1, 2, 3)               # Multiplicadores de regularización
feat_classes   <- c("L", "LQ", "H", "LQH")      # Clases de respuesta (Features)
# ==============================================================================

# 1. PREPARACIÓN DE RUTAS Y ENLACE CON MAXENT.JAR -------------------------------
nombre_archivo <- gsub(" ", "_", especie)
ruta_proyecto  <- file.path(ruta_base, nombre_archivo)
setwd(ruta_proyecto)

carpeta_capas  <- paste0("capas_maxent_", nombre_archivo)
carpeta_salida <- paste0("resultados_maxent_", nombre_archivo)
dir.create(carpeta_salida, showWarnings = FALSE)

# Copiar maxent.jar a la carpeta interna de dismo si aún no está ahí
destino_jar <- file.path(system.file("java", package = "dismo"), "maxent.jar")
if (!file.exists(destino_jar)) {
  file.copy(ruta_maxent, destino_jar)
  cat("maxent.jar vinculado exitosamente a R.\n")
}

# 2. CARGA DE OCURRENCIAS, POLÍGONO M Y VARIABLES SELECCIONADAS ----------------
puntos_sf <- readRDS(paste0(nombre_archivo, "_puntos_finales.rds"))
pol_vect  <- readRDS(paste0(nombre_archivo, "_poligono_M.rds"))

occs_coords <- as.data.frame(puntos_sf)[, c("decimalLongitude", "decimalLatitude")]
colnames(occs_coords) <- c("longitude", "latitude")

archivos_vars <- list.files(carpeta_capas, pattern = "\\.tif$", full.names = TRUE)
envs_stack    <- rast(archivos_vars)
names(envs_stack) <- gsub("CHELSA_|_1981-2010_V\\.2\\.1", "", names(envs_stack))
cat("Variables cargadas para el modelo:", paste(names(envs_stack), collapse = ", "), "\n")

set.seed(42)
bg_vect   <- spatSample(envs_stack[[1]], size = n_background, method = "random", 
                        na.rm = TRUE, xy = TRUE, values = FALSE)
bg_coords <- as.data.frame(bg_vect)
colnames(bg_coords) <- c("longitude", "latitude")

# 3. CALIBRACIÓN Y EVALUACIÓN CON ENMeval --------------------------------------
cat("\nIniciando calibración de", length(reg_mult) * length(feat_classes), 
    "modelos candidatos con validación:", metodo_val, "...\n")

eval_res <- ENMeval::ENMevaluate(
  occs       = occs_coords,
  envs       = envs_stack,
  bg         = bg_coords,
  algorithm  = "maxent.jar",
  partitions = metodo_val,
  partition.settings = if (metodo_val == "randomkfold") {
    list(kfolds = k_folds)
  } else {
    list(orientation = "lat_lon")
  },
  tune.args  = list(fc = feat_classes, rm = reg_mult),
  parallel   = FALSE
)

tabla_resultados <- eval_res@results
write.csv(tabla_resultados, file.path(carpeta_salida, "tabla_calibracion_ENMeval.csv"), row.names = FALSE)

# 4. SELECCIÓN DEL MEJOR MODELO (DELTA AICc = 0) -------------------------------
mejor_idx   <- which(tabla_resultados$delta.AICc == 0)[1]
mejor_fila  <- tabla_resultados[mejor_idx, ]
mejor_fc    <- as.character(mejor_fila$fc)
mejor_rm    <- as.numeric(mejor_fila$rm)

cat("\n=== MODELO ÓPTIMO SELECCIONADO ===\n")
cat("Feature Class (fc):", mejor_fc, "| Regularización (rm):", mejor_rm, "\n")
cat("AUC Validación:", round(mejor_fila$auc.val.avg, 3), "| AICc:", round(mejor_fila$AICc, 1), "\n")

# 5. EJECUCIÓN FINAL EN MAXENT.JAR PARA GENERAR EL REPORTE HTML OFICIAL --------
cat("\nGenerando reporte HTML oficial de MaxEnt y mapa de idoneidad...\n")
envs_raster_pkg <- raster::stack(envs_stack)

args_maxent <- c(
  paste0("betamultiplier=", mejor_rm),
  "responsecurves=true",
  "jackknife=true",
  "outputformat=cloglog",
  "randomseed=true"
)
if (!grepl("L", mejor_fc)) args_maxent <- c(args_maxent, "nolinear")
if (!grepl("Q", mejor_fc)) args_maxent <- c(args_maxent, "noquadratic")
if (!grepl("H", mejor_fc)) args_maxent <- c(args_maxent, "nohinge")
if (!grepl("P", mejor_fc)) args_maxent <- c(args_maxent, "noproduct")
args_maxent <- c(args_maxent, "nothreshold")

modelo_final <- dismo::maxent(
  x    = envs_raster_pkg,
  p    = occs_coords,
  a    = bg_coords,
  path = file.path(carpeta_salida, "reporte_oficial_maxent"),
  args = args_maxent
)

mapa_idoneidad <- predict(envs_stack, modelo_final, na.rm = TRUE)
writeRaster(mapa_idoneidad, file.path(carpeta_salida, paste0(nombre_archivo, "_idoneidad_cloglog.tif")), overwrite = TRUE)

png(file.path(carpeta_salida, paste0(nombre_archivo, "_mapa_final.png")), width = 900, height = 800, res = 150)
plot(mapa_idoneidad, main = paste0("Idoneidad de Hábitat (Cloglog): ", especie, "\n(FC: ", mejor_fc, " | RM: ", mejor_rm, " | AUC: ", round(mejor_fila$auc.val.avg, 3), ")"),
     col = hcl.colors(100, "YlOrRd", rev = TRUE))
plot(pol_vect, add = TRUE, border = "black", lwd = 1.2)
points(occs_coords, pch = 16, cex = 0.5, col = rgb(0, 0, 0, 0.6))
dev.off()

cat("\n¡PROCESO COMPLETADO CON ÉXITO!\n")
cat("1. Abre el reporte clásico de MaxEnt en:", file.path(carpeta_salida, "reporte_oficial_maxent", "maxent.html"), "\n")
cat("2. Revisa tu mapa listo para publicar en:", file.path(carpeta_salida, paste0(nombre_archivo, "_mapa_final.png")), "\n")
