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

  # 1. Detectar ruta de Python si no se provee ----------------------------
  if (is.null(python_path)) {

    if (is_arcpy_config()) {
      message("El entorno de Python con 'arcpy' ya esta configurado y disponible.")
      return(invisible(TRUE))
    }

    python_path <- .detect_arcgis_python()

    if (is.null(python_path)) {
      stop(
        "No se pudo encontrar automaticamente el entorno de Python de ArcGIS.\n\n",
        "Especifique la ruta manualmente segun su version:\n\n",
        "  # ArcGIS Pro:\n",
        '  setup_arcpy_env("C:/Program Files/ArcGIS/Pro/bin/Python/envs/arcgispro-py3/python.exe")\n\n',
        "  # ArcGIS Desktop (ejemplo con 10.8):\n",
        '  setup_arcpy_env("C:/Python27/ArcGIS10.8/python.exe")'
      )
    }
  }

  # 2. Validar que el ejecutable exista -----------------------------------
  if (!file.exists(python_path)) {
    stop(
      "La ruta de Python especificada no existe:\n  ", python_path, "\n\n",
      "Verifique que ArcGIS este instalado y que la ruta sea correcta."
    )
  }

  # 3. Advertencia si es Python 2 (ArcGIS Desktop) ------------------------
  if (.is_python2(python_path)) {
    warning(
      "Se detecto Python 2.7 (ArcGIS Desktop).\n",
      "El soporte de 'reticulate' para Python 2 es limitado en versiones recientes.\n",
      "Se recomienda migrar a ArcGIS Pro (Python 3) para mayor compatibilidad.",
      call. = FALSE
    )
  }

  # 4. Detectar conflicto de sesion de reticulate -------------------------
  py_conf      <- suppressMessages(reticulate::py_config())
  already_init <- !is.null(py_conf) && nzchar(py_conf$python)
  wrong_env    <- already_init && !is_arcpy_config()

  if (wrong_env) {
    .write_reticulate_python(python_path)
    stop(
      "Reticulate ya fue inicializado con un entorno diferente al de ArcGIS.\n",
      "  Python actual   : ", py_conf$python, "\n",
      "  Python requerido: ", python_path, "\n\n",
      "Se escribio automaticamente la configuracion en ~/.Renviron.\n",
      "SOLUCION: Solo debes reiniciar la sesion de R (Session > Restart R)\n",
      "y volver a llamar a setup_arcpy_env()."
    )
  }

  # 5. Configurar entorno -------------------------------------------------
  reticulate::use_python(python_path, required = TRUE)
  invisible(TRUE)
}


# Helpers internos (no exportados) ----------------------------------------

#' Busca Python en entornos conda con 'arcgis' en el nombre (ArcGIS Pro)
#' y en rutas tipicas de instalacion de ArcGIS Desktop (Python 2.7).
#' @return Ruta al ejecutable o NULL si no se encuentra ninguno.
#' @noRd
.detect_arcgis_python <- function() {

  # -- Busqueda en entornos conda (ArcGIS Pro) ----------------------------
  envs <- tryCatch(reticulate::conda_list(), error = function(e) NULL)

  if (!is.null(envs) && nrow(envs) > 0L) {
    matches <- envs[grepl("arcgis", envs$name, ignore.case = TRUE), , drop = FALSE]
    for (path in matches$python) {
      if (nzchar(path) && file.exists(path)) return(path)
    }
  }

  # -- Busqueda en rutas tipicas de ArcGIS Desktop ------------------------
  # Cubre versiones 10.1 a 10.9 en las unidades C y D
  desktop_candidates <- .desktop_python_candidates()
  for (path in desktop_candidates) {
    if (file.exists(path)) return(path)
  }

  NULL
}

#' Genera rutas candidatas para instalaciones tipicas de ArcGIS Desktop.
#' @return Character vector con rutas a python.exe ordenadas de mayor a menor version.
#' @noRd
.desktop_python_candidates <- function() {
  drives   <- c("C:", "D:")
  versions <- paste0("10.", 9:1)   # de mayor a menor para preferir la mas reciente
  combos   <- expand.grid(drive = drives, ver = versions, stringsAsFactors = FALSE)

  file.path(combos$drive, "Python27", paste0("ArcGIS", combos$ver), "python.exe")
}

#' Determina si un ejecutable de Python corresponde a la version 2.
#' Usa solo el nombre de la ruta para evitar ejecutar el proceso.
#' @param path Ruta al ejecutable de Python.
#' @return TRUE si se infiere Python 2, FALSE en caso contrario.
#' @noRd
.is_python2 <- function(path) {
  grepl("Python27", path, ignore.case = TRUE)
}


#' Escribe RETICULATE_PYTHON en el .Renviron del usuario.
#' Si ya existe una entrada, la reemplaza. Evita duplicados.
#' @param python_path Ruta al ejecutable de Python de ArcGIS.
#' @return invisible(NULL)
#' @noRd
.write_reticulate_python <- function(python_path) {
  renviron_path <- file.path(Sys.getenv("HOME"), ".Renviron")

  lines <- if (file.exists(renviron_path)) readLines(renviron_path, warn = FALSE) else character(0)

  # Reemplazar entrada existente o agregar al final
  lines <- lines[!grepl("^RETICULATE_PYTHON\\s*=", lines)]
  lines <- c(lines, sprintf('RETICULATE_PYTHON="%s"', python_path))

  writeLines(lines, renviron_path)
  message("Se actualizo ~/.Renviron con RETICULATE_PYTHON=", python_path)
}


#' Verifica si arcpy está disponible
#'
#' @description
#' Comprueba si el módulo `arcpy` de ArcGIS está configurado y accesible
#' en el entorno de Python que `reticulate` está utilizando actualmente.
#'
#' @return Un valor lógico: `TRUE` si `arcpy` está disponible, `FALSE` en caso contrario.
#' @export
is_arcpy_config <- function() {
  reticulate::py_module_available("arcpy")
}

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
st_trans_sup_ha <- function(shapefile_path, campo_superficie = "Sup_ha", precision = 8L, escala = 2L) {

  # 1. Validar que arcpy está disponible. Esta es la única comprobación necesaria.
  # py_module_available inicializará reticulate si es necesario, respetando RETICULATE_PYTHON.
  if (!reticulate::py_module_available("arcpy")) {
    stop(
      "El módulo 'arcpy' no se encuentra en el entorno de Python configurado.\n",
      "Por favor, reinicia R y ejecuta 'setup_arcpy_env()' o configura la variable de entorno RETICULATE_PYTHON."
    )
  }

  # 2. Encontrar la ruta del script de Python dentro del paquete instalado
  python_script_path <- system.file("python", "trans_sup_ha.py", package = "SupHA", mustWork = TRUE)

  # 3. Cargar el script de Python en la sesión de reticulate
  # py_run_file crea un entorno donde se definen las funciones del script
  reticulate::py_run_file(python_script_path)

  # 4. Llamar a la función de Python desde R
  # reticulate se encarga de la conversión de tipos (R -> Python)
  # Usamos py_capture_output para asegurarnos de ver cualquier mensaje de error de Python.
  output <- reticulate::py_capture_output({
    resultado <- reticulate::py$st_trans_sup_ha(
      shapefile_path = tools::file_path_as_absolute(shapefile_path),
      campo_superficie = campo_superficie,
      precision = as.integer(precision),
      escala = as.integer(escala)
    )
  })
  
  # Imprimir cualquier salida capturada (mensajes de estado o error de Python)
  cat(output)
  
  # El resultado de la última expresión dentro del bloque es lo que se devuelve.
  # Necesitamos extraer el valor de 'resultado' del entorno de la captura.
  resultado <- get("resultado", envir = environment())

  # 5. Devolver el resultado (Python -> R)
  return(resultado)
}
