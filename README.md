
<!-- README.md is generated from README.Rmd. Please edit that file -->

# SupHA

<!-- badges: start -->

<!-- badges: end -->

El paquete SupHA está pensado para recalcular la superficie del campo
‘Sup_ha’ con la escala y precision deseada, que suele ser requisito en
capas vectoriales de tipo polígono solicitadas por CONAF, donde se
solicita dejar las superficies en hectáreas y con dos decimales. Dado
que los parámetros de escala y precision no son posibles de ajustar al
trabajar con capas vectoriales con el paquete ‘sf’, las funciones
utilizadas en este paquete provienen del paquete de python ‘arcpy’, por
lo que se requiere tener instalado el software ArcGIS en su computadora.

Si trabaja directamente con ArcGIS el paquete podria no serle de mucha
utilidad, sin embargo, si suele generar sus capas con R, como por
ejemplo usando los paquetes para elaborar insumos para los informes de
experto de los [PAS 150](https://github.com/DavidJMartinezS/PAS.150) o
los [PAS 148 y 151](https://github.com/DavidJMartinezS/PAS148y151). Y
puede aplicar la función a una o más capas como se muestran en los
ejemplos más adelante.

## Instalación

Puede instalar el paquete con cualquiera de las siguientes maneras:

``` r
# install.packages("pak")
pak::pak("DavidJMartinezS/SupHA")

# install.packages("remotes")
remotes::install_github("DavidJMartinezS/SupHA")
```

## Ejemplos

``` r
library(SupHA)

# Para un archivo
path <- "Ruta/Shapefile.shp"
st_trans_sup_ha(path)

# Para varios archivos
dir <- getwd() # Ingresar directorio donde se encuentran los shapefiles
paths <- list.files(dir, pattern = ".shp$", full_names = T) 
paths <- list.files(dir, pattern = ".shp$", full_names = T, recursive = T) # recursive = TRUE para buscar archivos dentro de otras carpetas
paths <- tools::list_files_with_exts(dir, exts = "shp", full.names = T)

lapply(paths, st_trans_sup_ha)
```
