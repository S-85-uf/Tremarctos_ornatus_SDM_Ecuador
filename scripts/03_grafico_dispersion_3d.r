
library(plot3D)

datos <- read.csv("puntos_oso_3d.csv")

x_km <- datos[, 1] / 1000
y_km <- datos[, 2] / 1000
z_alt <- datos[, ncol(datos)]

png("dispersion_3d_oso.png", width = 1400, height = 1100, res = 220, bg = "transparent")

par(mar = c(2, 3.5, 2, 2))

scatter3D(
  x = x_km,
  y = y_km,
  z = z_alt,
  pch = 19,
  cex = 0.85,
  colvar = z_alt,
  col = jet.col(100),
  theta = 35,
  phi = 22,
  bty = "g",
  xlab = "\nEste (km)",
  ylab = "\nNorte (km)",
  zlab = "", # Dejamos vacio aqui para no chocar con 2000 y 3000
  ticktype = "detailed",
  nticks = 4,
  cex.axis = 0.72,
  cex.lab = 0.85,
  colkey = list(
    length = 0.65,
    width = 0.7,
    dist = -0.05,
    cex.axis = 0.75,
    cex.clab = 0.85,
    clab = "Altitud (m)"
  )
)

# Colocar "Altitud (msnm)" bien separado a la izquierda del eje Z
mtext("Altitud (msnm)", side = 2, line = 1.6, cex = 0.85, las = 0)

dev.off()
