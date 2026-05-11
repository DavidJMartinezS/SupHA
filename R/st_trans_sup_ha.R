#' Procesar y calcular superficie en hectáreas para una capa espacial
#'
#' @description
#' Esta función es un envoltorio (wrapper) para una herramienta de geoprocesamiento en Python
#' que utiliza `arcpy`. Asegura que una capa de entidades (shapefile, feature class)
#' tenga un campo de superficie con un formato específico y calcula el área en hectáreas.
#'
#' La función original de Python verifica si el campo de superficie existe. Si no, lo crea.
#' Si existe pero con un formato incorrecto (tipo, precisión, escala), recrea la capa
#' para preservar el orden de los campos y aplica el formato correcto. Finalmente,
#' calcula o recalcula el área.
#'
#' @section Configuración del Entorno:
#' Antes de usar esta función, es **imprescindible** configurar el entorno de Python
#' para que apunte a la instalación de ArcGIS Pro o Desktop. Utilice la función de ayuda `setup_arcpy_env()`:
#'
#' ```R
#' # Ejecutar una vez por sesión de R
#' setup_arcpy_env()
#' ```
#'
#' Se recomienda ejecutar este comando al inicio de tu script o sesión de R.
#'
#' @param shapefile_path (cadena de texto) Ruta completa a la capa de entidades a procesar.
#' @param campo_superficie (cadena de texto) Nombre del campo para la superficie. Por defecto es `"Sup_ha"`.
#' @param precision (entero) Precisión total del campo numérico (tipo DOUBLE). Por defecto es `8`.
#' @param escala (entero) Número de dígitos decimales del campo numérico. Por defecto es `2`.
#'
#' @return
#' Devuelve `TRUE` si el proceso fue exitoso, o `FALSE` si ocurrió un error.
#' Los mensajes de estado o error se imprimirán en la consola.
#'
#' @export
#' @import reticulate
#'
#' @examples
#' \dontrun{
#'   # Paso 1: Configurar el entorno de Python con arcpy
#'   setup_arcpy_env()
#'
#'   # Paso 2: Ejecutar la función en una capa
#'   ruta_capa <- "C:/ruta/a/tus/datos/mi_capa.shp"
#'   st_trans_sup_ha(shapefile_path = ruta_capa)
#'
#'   # También se puede usar con lapply para procesar una lista de capas
#'   lista_capas <- list.files("C:/ruta/a/tus/datos/", pattern = ".shp$", full.names = TRUE)
#'   lapply(lista_capas, st_trans_sup_ha)
#' }
st_trans_sup_ha <- function(shapefile_path, campo_superficie = "Sup_ha", precision = 8L, escala = 2L
) {
  # 1. Validar entradas ---------------------------------------------------
  if (!file.exists(shapefile_path)) {
    stop("El shapefile no existe: ", shapefile_path)
  }

  if (!is.numeric(precision) || precision < 1L) {
    stop("'precision' debe ser un entero positivo.")
  }

  if (!is.numeric(escala) || escala < 0L) {
    stop("'escala' debe ser un entero no negativo.")
  }

  # 2. Verificar que arcpy está disponible --------------------------------
  if (!reticulate::py_module_available("arcpy")) {
    stop(
      "El módulo 'arcpy' no está disponible en el entorno de Python configurado.\n",
      "Reinicia R y ejecuta 'setup_arcpy_env()' antes de usar esta función."
    )
  }

  # 3. Verificar que el módulo Python fue cargado al iniciar el paquete ---
  if (is.null(.supHA_env$trans_sup_ha)) {
    stop(
      "El script de Python no fue cargado correctamente.\n",
      "Reinstala el paquete o contacta al mantenedor."
    )
  }

  # 4. Llamar a la función de Python --------------------------------------
  resultado <- tryCatch(
    .supHA_env$trans_sup_ha(
      shapefile_path = tools::file_path_as_absolute(shapefile_path),
      campo_superficie = campo_superficie,
      precision = as.integer(precision),
      escala = as.integer(escala)
    ),
    error = function(e) {
      stop(
        "Error al ejecutar 'st_trans_sup_ha' en Python:\n",
        conditionMessage(e)
      )
    }
  )

  invisible(resultado)
}
