#' Configura el entorno de Python para usar arcpy
#'
#' @description
#' Esta función de ayuda busca y configura el entorno de Python que incluye
#' el paquete `arcpy` de ArcGIS Pro. Facilita la inicialización de `reticulate`
#' para que las funciones que dependen de `arcpy` funcionen correctamente.
#'
#' @details
#' La función opera de la siguiente manera:
#' 1. Si se proporciona un `python_path`, intentará usar esa ruta directamente.
#' 2. Si `python_path` es `NULL` (por defecto), la función intentará detectar
#'    automáticamente la instalación de ArcGIS Pro en sistemas Windows
#'    buscando en el registro del sistema.
#' 3. Si la detección automática falla, mostrará un mensaje de error con
#'    instrucciones para que el usuario proporcione la ruta manualmente.
#'
#' Esta función solo necesita ejecutarse una vez por sesión de R, antes de
#' llamar a cualquier función que dependa de `arcpy`.
#'
#' @param python_path (Opcional) Una cadena de texto con la ruta completa al
#'   ejecutable de Python de ArcGIS Pro (p. ej., `python.exe`). Si es `NULL`,
#'   se intentará la detección automática.
#'
#' @return Imprime mensajes de estado en la consola. Devuelve `TRUE` (invisiblemente)
#'   si la configuración fue exitosa, y lanza un error si falla.
#' @export
#' @examples
#' \dontrun{
#'   # Opción 1: Detección automática (recomendado en Windows)
#'   setup_arcpy_env()
#'
#'   # Opción 2: Especificar la ruta manualmente
#'   setup_arcpy_env(
#'     python_path = "C:/Program Files/ArcGIS/Pro/bin/Python/envs/arcgispro-py3/python.exe"
#'   )
#' }
setup_arcpy_env <- function(python_path = NULL) {
  # Si ya se ha inicializado reticulate con arcpy, no hacer nada.
  if (reticulate::py_module_available("arcpy")) {
    message("El entorno de Python con 'arcpy' ya está configurado y disponible.")
    return(invisible(TRUE))
  }

  if (is.null(python_path)) {
    # Intento de detección automática solo en Windows
    if (.Platform$OS.type == "windows") {
      message("Intentando detectar automáticamente el entorno Python de ArcGIS Pro...")
      tryCatch({
        arcgis_path <- utils::readRegistry("SOFTWARE\\ESRI\\ArcGISPro", "HLM")$InstallDir
        python_path <- file.path(arcgis_path, "bin", "Python", "envs", "arcgispro-py3", "python.exe")
        message("ArcGIS Pro detectado en: ", dirname(dirname(arcgis_path)))
      }, error = function(e) {
        # No hacer nada si la clave del registro no se encuentra
      })
    }
  }

  if (!is.null(python_path) && file.exists(python_path)) {
    message("Configurando reticulate para usar: ", python_path)
    reticulate::use_python(python_path, required = TRUE)
  } else {
    stop("No se pudo encontrar el entorno de Python de ArcGIS Pro.\n",
         "Por favor, ejecute setup_arcpy_env() especificando la ruta manualmente, por ejemplo:\n",
         'setup_arcpy_env(python_path = "C:/Program Files/ArcGIS/Pro/bin/Python/envs/arcgispro-py3/python.exe")')
  }
  invisible(TRUE)
}

#' Procesar y calcular superficie en hectáreas para una capa espacial
#'
#' @description
#' Esta función es un envoltorio (wrapper) para una herramienta de geoprocesamiento en Python
#' para preservar el orden de los campos y aplica el formato correcto. Finalmente,
#' calcula o recalcula el área.
#'
#' @section Configuración del Entorno:
#' Antes de usar esta función, es **imprescindible** configurar el entorno de Python
#' para que apunte a la instalación de ArcGIS Pro. Utilice la función de ayuda `setup_arcpy_env()`:
#'
#' ```R
#' # Ejecutar una vez por sesión de R
#' setup_arcpy_env()
#' ```
#'
#' Se recomienda ejecutar este comando al inicio de tu script o sesión de R.
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
st_trans_sup_ha <- function(shapefile_path, campo_superficie = "Sup_ha", precision = 8L, escala = 2L) {

  if (!reticulate::py_module_available("arcpy")) {
    stop(
      "El módulo 'arcpy' no se encuentra en el entorno de Python configurado.\n",
      "Por favor, ejecuta la función 'setup_arcpy_env()' antes de llamar a esta función.\n",
      "Consulta la ayuda (?setup_arcpy_env) para más detalles."
    )
  }

  # 3. Encontrar la ruta del script de Python dentro del paquete instalado
  python_script_path <- system.file("python", "trans_sup_ha.py", package = "SupHA", mustWork = TRUE)

  # 4. Cargar el script de Python en la sesión de reticulate
  # py_run_file crea un entorno donde se definen las funciones del script
  reticulate::py_run_file(python_script_path)

  # 5. Llamar a la función de Python desde R
  # reticulate se encarga de la conversión de tipos (R -> Python)
  # La función 'st_trans_sup_ha' ahora existe en el diccionario principal de Python de reticulate
  resultado <- reticulate::py$st_trans_sup_ha(
    shapefile_path = shapefile_path,
    campo_superficie = campo_superficie,
    precision = as.integer(precision), # Aseguramos que sea entero
    escala = as.integer(escala)
  )

  # 6. Devolver el resultado (Python -> R)
  return(resultado)
}