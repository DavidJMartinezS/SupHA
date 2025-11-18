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

  # Comprobar si reticulate ya se ha inicializado con OTRO Python.
  # py_config() nos da el estado actual. Si está inicializado y no tiene arcpy,
  # significa que es demasiado tarde para cambiar.
  py_conf <- reticulate::py_config()
  if (py_conf$initialized && !reticulate::py_module_available("arcpy")) {
    # Construir la ruta correcta para el mensaje de error
    arcpy_python_path <- if (!is.null(python_path)) python_path else "la ruta/a/tu/python.exe de ArcGIS"
    
    stop(
      "Reticulate ya ha sido inicializado con un entorno de Python diferente.\n",
      "-> Python actual: ", py_conf$python, "\n\n",
      "SOLUCIÓN: Debes forzar el uso del Python de ArcGIS ANTES de que se inicie reticulate.\n",
      "1. Reinicia tu sesión de R (Session > Restart R).\n",
      "2. Ejecuta el siguiente comando en la consola para establecer la variable de entorno:\n",
      sprintf("   Sys.setenv(RETICULATE_PYTHON = \"%s\")\n", arcpy_python_path),
      "3. Ahora puedes usar las funciones del paquete SupHA normalmente."
    )
  }

  if (is.null(python_path)) {
    # Intento de detección automática solo en Windows
    if (.Platform$OS.type == "windows") {
      message("Intentando detectar automáticamente el entorno Python de ArcGIS...")
      
      # Prioridad 1: Intentar detectar ArcGIS Pro
      tryCatch({
        arcgis_path <- utils::readRegistry("SOFTWARE\\ESRI\\ArcGISPro", "HLM")$InstallDir
        python_path <- file.path(arcgis_path, "bin", "Python", "envs", "arcgispro-py3", "python.exe")
        if (file.exists(python_path)) {
          message("-> ArcGIS Pro detectado.")
        } else {
          python_path <- NULL # Resetear si la ruta no es válida
        }
      }, error = function(e) {
        python_path <<- NULL
      })
      
      # Prioridad 2: Si no se encontró Pro, intentar detectar ArcGIS Desktop (Python 2.7)
      if (is.null(python_path)) {
        tryCatch({
          # La forma más robusta es buscar la clave de registro específica de ESRI para Python 2.7
          py_dir <- utils::readRegistry("SOFTWARE\\ESRI\\Python2.7", "HLM")$PythonDir
          if (!is.null(py_dir) && dir.exists(py_dir)) {
            python_path <- file.path(py_dir, "python.exe")
            if (file.exists(python_path)) {
              message("-> ArcGIS Desktop (Python 2.7) detectado.")
            } else {
              python_path <- NULL # Resetear si python.exe no se encuentra
            }
          }
        }, error = function(e) {
          python_path <<- NULL # No se encontró la clave de registro
        })
      }
    }
  }

  if (!is.null(python_path) && file.exists(python_path)) {
    message("Configurando reticulate para usar: ", python_path)
    reticulate::use_python(python_path, required = TRUE)
  } else {
    stop("No se pudo encontrar el entorno de Python de ArcGIS Pro o Desktop.\n",
         "Por favor, ejecute setup_arcpy_env() especificando la ruta manualmente, por ejemplo:\n",
         '# Para ArcGIS Pro:\n',
         'setup_arcpy_env(python_path = "C:/Program Files/ArcGIS/Pro/bin/Python/envs/arcgispro-py3/python.exe")\n',
         '# Para ArcGIS Desktop:\n',
         'setup_arcpy_env(python_path = "C:/Python27/ArcGIS10.8/python.exe")'
    )
  }
  invisible(TRUE)
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
