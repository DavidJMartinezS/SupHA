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

    # Evitar que el chequeo inicial dispare el error de arquitectura antes de tiempo
    if (suppressWarnings(tryCatch(is_arcpy_config(), error = function(e) FALSE))) {
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

  # 2b. Validar arquitectura (especialmente para ArcGIS Desktop) ----------
  is_r_64bit  <- .Machine$sizeof.pointer == 8
  is_py_64bit <- grepl("ArcGISx64",  python_path, ignore.case = TRUE) ||
                grepl("ArcGIS/Pro", python_path, ignore.case = TRUE) ||
                grepl("arcgispro",  python_path, ignore.case = TRUE)

  if (is_r_64bit && .is_python2(python_path) && !is_py_64bit) {
    stop(
      "Conflicto de arquitectura: R es de 64 bits pero el Python detectado es de 32 bits.\n",
      "Ruta detectada: ", python_path, "\n\n",
      "SOLUCIONES:\n",
      "1. Instale 'ArcGIS for Desktop Background Geoprocessing (64-bit)' y vuelva a\n",
      "   ejecutar setup_arcpy_env() para que detecte automaticamente el Python de 64 bits.\n",
      "2. O especifique la ruta manualmente, por ejemplo:\n",
      '   setup_arcpy_env("C:/Python27/ArcGISx6410.8/python.exe")',
      "3. Si lo anterior no resulta, se recomienda migrar a 'ArcGIS Pro (64-bit)'.",
      call. = FALSE
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
  # Capturamos error por si reticulate ya esta amarrado a un python incompatible
  py_conf <- tryCatch(
    suppressMessages(reticulate::py_config()),
    error = function(e) NULL
  )
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
  versions <- paste0("10.", 9:1)
  combos   <- expand.grid(drive = drives, ver = versions, stringsAsFactors = FALSE)

  # 64 bits primero (ArcGISx64), luego 32 bits (ArcGIS) como fallback
  c(
    file.path(combos$drive, "Python27", paste0("ArcGISx64", combos$ver), "python.exe"),
    file.path(combos$drive, "Python27", paste0("ArcGIS",    combos$ver), "python.exe")
  )
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
