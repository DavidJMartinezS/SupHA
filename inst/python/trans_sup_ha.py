import arcpy
import os
import sys

def st_trans_sup_ha(shapefile_path, campo_superficie="Sup_ha", precision=8, escala=2):
    """
    Procesa un shapefile (o clase de entidad) para asegurar un campo de superficie.

    Verifica si el campo 'Sup_ha' existe. Si existe, lo elimina y lo vuelve a crear
    con la precisión y escala especificadas, luego calcula la superficie en hectáreas.
    Si no existe, lo crea y calcula la superficie.

    Args:
        shapefile_path (str): Ruta completa al shapefile o clase de entidad a procesar.
        campo_superficie (str): Nombre del campo para la superficie (por defecto "Sup_ha").
        precision (int): Precisión del campo DOUBLE (dígitos totales).
        escala (int): Escala del campo DOUBLE (dígitos después del decimal).
    """

    # --- Verificar si el shapefile existe ---
    if not arcpy.Exists(shapefile_path):
        print(f"Error: El archivo no existe en la ruta especificada: {shapefile_path}", file=sys.stderr)
        return False

    print(f"Iniciando procesamiento para: {os.path.basename(shapefile_path)}")

    try:
        # Habilitar la sobrescritura de salidas (útil si creas archivos temporales, aunque aquí no aplica directamente)
        arcpy.env.overwriteOutput = True

        # Al ejecutar fuera de ArcGIS Pro, el entorno de geoprocesamiento debe definirse explícitamente.
        # Obtenemos el sistema de coordenadas de la capa de entrada y lo establecemos en el entorno.
        spatial_ref = arcpy.Describe(shapefile_path).spatialReference
        arcpy.env.outputCoordinateSystem = spatial_ref

        # Obtener una lista de los campos existentes
        original_fields = arcpy.ListFields(shapefile_path)
        field_obj = next((f for f in original_fields if f.name.lower() == campo_superficie.lower()), None)

        # --- 1. Lógica para manejar el campo existente ---
        if field_obj:
            print(f"Campo '{campo_superficie}' detectado. Verificando propiedades...")
            # Comprobar si el campo tiene el tipo, precisión y escala correctos.
            if (field_obj.type == "Double" and 
                field_obj.precision == precision and 
                field_obj.scale == escala):
                print("El campo ya tiene el formato correcto. Se procederá a recalcular su valor.")
                # Si el formato es correcto, solo calculamos la geometría y terminamos.
                # Esto es rápido y no altera el orden de los campos.
                arcpy.management.CalculateGeometryAttributes(
                    in_features=shapefile_path,
                    geometry_property=[[campo_superficie, 'AREA']],
                    area_unit="HECTARES",
                    coordinate_format="SAME_AS_INPUT"
                )
                print("Superficie calculada y campo actualizado exitosamente.")
                return True
            else:
                print(f"El formato del campo es incorrecto (Tipo: {field_obj.type}, Precisión: {field_obj.precision}).")
                print("Se recreará la capa para preservar el orden de los campos.")
        
        # --- 2. Proceso de Recreación de la Capa para Preservar el Orden ---
        # Crear una ruta para la capa temporal
        temp_shapefile = arcpy.CreateUniqueName("temp_output.shp", arcpy.env.scratchFolder)
        print(f"Creando capa temporal en: {temp_shapefile}")

        # Crear la capa temporal vacía con el mismo sistema de coordenadas
        arcpy.management.CreateFeatureclass(
            os.path.dirname(temp_shapefile),
            os.path.basename(temp_shapefile),
            "POLYGON", # Asumiendo polígonos, se puede hacer más genérico si es necesario
            spatial_reference=spatial_ref
        )

        # Añadir los campos a la capa temporal en el orden original
        for field in original_fields:
            # Omitir campos que no se pueden transferir (como OID, Shape) y el campo a modificar
            if field.type not in ('OID', 'Geometry') and field.name.lower() != campo_superficie.lower():
                arcpy.management.AddField(temp_shapefile, field.name, field.type, field.precision, field.scale, field.length, field.aliasName, field.isNullable, field.required, field.domain)
            # Si encontramos la posición del campo a modificar, lo creamos con las propiedades correctas
            elif field.name.lower() == campo_superficie.lower():
                arcpy.management.AddField(temp_shapefile, campo_superficie, "DOUBLE", precision, escala)

        # Si el campo no existía, lo añadimos al final
        # if not field_obj:
        #     arcpy.management.AddField(temp_shapefile, campo_superficie, "DOUBLE", precision, escala)

        # --- 3. Copiar los atributos de la capa original a la temporal ---
        print("Copiando datos a la capa temporal...")
        # Crear una lista de los nombres de campo de la capa temporal (excluyendo el campo de superficie)
        temp_fields = [f.name for f in arcpy.ListFields(temp_shapefile) if f.type not in ('OID', 'Geometry')]
        # Crear una lista de campos originales que existen en la capa temporal
        original_fields_to_copy = [f.name for f in original_fields if f.name in temp_fields and f.name.lower() != campo_superficie.lower()]
        
        # Usar cursores para una copia eficiente
        with arcpy.da.SearchCursor(shapefile_path, ['SHAPE@'] + original_fields_to_copy) as s_cursor:
            with arcpy.da.InsertCursor(temp_shapefile, ['SHAPE@'] + original_fields_to_copy) as i_cursor:
                for row in s_cursor:
                    i_cursor.insertRow(row)

        # --- 4. Calcular la geometría en la capa temporal (AHORA que tiene datos) ---
        print(f"Calculando la superficie en el campo '{campo_superficie}'...")
        arcpy.management.CalculateGeometryAttributes(
            temp_shapefile,
            geometry_property=[[campo_superficie, 'AREA']],
            area_unit="HECTARES",
            coordinate_format="SAME_AS_INPUT"
        )

        # --- 5. Reemplazar el archivo original ---
        print("Reemplazando el archivo original con la versión procesada...")
        
        arcpy.management.DeleteField(temp_shapefile, "Id")
        arcpy.management.Delete(shapefile_path)
        arcpy.management.CopyFeatures(temp_shapefile, shapefile_path)
        arcpy.management.Delete(temp_shapefile)
        
        print("Proceso completado. El orden de los campos ha sido preservado.")
        return True

    except arcpy.ExecuteError:
        print("\nError de ArcPy:", file=sys.stderr)
        print(arcpy.GetMessages(2), file=sys.stderr) # Muestra mensajes de error detallados de ArcPy
        return False
    except Exception as e:
        print(f"\nOcurrió un error inesperado: {e}", file=sys.stderr)
        return False

# Esto permite que el script se ejecute directamente para pruebas
# if __name__ == "__main__":
#     # Ejemplo de uso si ejecutas este script directamente
#     shapefile_path = r"C:\Users\\dmartinez\\Documents\\datos_temp\\KIM753_A2\\Cartografia_digital_CHOAPA\\Rangos_pend_CHOAPA_KIMAL.shp"
#     if st_trans_sup_ha(shapefile_path):
#         print("Procesamiento de prueba exitoso.")
#     else:
#         print("Procesamiento de prueba fallido.")
