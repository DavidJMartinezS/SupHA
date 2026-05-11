# Entorno interno del paquete — almacena objetos Python entre llamadas
.supHA_env <- new.env(parent = emptyenv())

.onLoad <- function(libname, pkgname) {
  script <- system.file(
    "python", "trans_sup_ha.py",
    package  = "SupHA",
    mustWork = TRUE
  )

  # source_python con envir = NULL devuelve un módulo con las funciones
  # definidas en el script, sin contaminar el entorno global de R.
  module <- tryCatch(
    reticulate::source_python(script, envir = NULL),
    error = function(e) NULL
  )

  # Si el módulo cargó correctamente, extraer la función directamente.
  # Esto evita tener que llamar a reticulate::py$... en cada uso.
  .supHA_env$trans_sup_ha <- if (!is.null(module)) module$trans_sup_ha else NULL
}