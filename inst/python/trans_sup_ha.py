from __future__ import print_function, unicode_literals

import os
import arcpy


def st_trans_sup_ha(shapefile_path, campo_superficie="Sup_ha", precision=8, escala=2):
    """
    Procesa un shapefile o clase de entidad para asegurar un campo de superficie.

    Si el campo ya existe con el tipo y precisión correctos, solo recalcula la
    geometría. En caso contrario, recrea el campo preservando el orden original
    de columnas y recalcula la superficie en hectáreas.

    Compatible con Python 2.7 (ArcMap) y Python 3.x (ArcGIS Pro).

    Args:
        shapefile_path (str): Ruta al shapefile o clase de entidad.
        campo_superficie (str): Nombre del campo de superficie. Por defecto "Sup_ha".
        precision (int): Precisión del campo DOUBLE (dígitos totales).
        escala (int): Escala del campo DOUBLE (dígitos después del decimal).

    Returns:
        True si el proceso finalizó correctamente.

    Raises:
        FileNotFoundError: Si shapefile_path no existe.
        RuntimeError: Si ocurre un error de ArcPy o un error inesperado.
    """

    # 1. Verificar existencia del archivo -----------------------------------
    if not arcpy.Exists(shapefile_path):
        raise IOError(
            "El archivo no existe en la ruta especificada: {}".format(shapefile_path)
        )

    try:
        # 2. Configurar entorno de arcpy ------------------------------------
        arcpy.env.overwriteOutput = True
        desc        = arcpy.Describe(shapefile_path)
        spatial_ref = desc.spatialReference
        arcpy.env.outputCoordinateSystem = spatial_ref

        # 3. Detectar tipo de geometría -------------------------------------
        geometry_type = desc.shapeType.upper()

        # 4. Buscar el campo de superficie ---------------------------------
        original_fields = arcpy.ListFields(shapefile_path)
        field_obj = next(
            (f for f in original_fields
             if f.name.lower() == campo_superficie.lower()),
            None
        )

        # 5. Caso rápido: campo correcto, solo recalcular -------------------
        campo_correcto = (
            field_obj is not None
            and field_obj.type == "Double"
            and field_obj.precision == precision
            and field_obj.scale == escala
        )

        if campo_correcto:
            arcpy.management.CalculateGeometryAttributes(
                in_features       = shapefile_path,
                geometry_property = [[campo_superficie, "AREA"]],
                area_unit         = "HECTARES",
                coordinate_format = "SAME_AS_INPUT"
            )
            print("Campo '{}' recalculado correctamente (sin cambios de estructura).".format(campo_superficie))
            return True

        # 6. Caso completo: recrear el campo preservando el orden ----------
        temp_shapefile = arcpy.CreateUniqueName("temp_output.shp", arcpy.env.scratchFolder)

        arcpy.management.CreateFeatureclass(
            os.path.dirname(temp_shapefile),
            os.path.basename(temp_shapefile),
            geometry_type,
            spatial_reference=spatial_ref
        )

        # Añadir campos en el orden original, reemplazando el de superficie
        for field in original_fields:
            if field.type in ("OID", "Geometry"):
                continue
            if field.name.lower() == campo_superficie.lower():
                arcpy.management.AddField(temp_shapefile, campo_superficie, "DOUBLE", precision, escala)
            else:
                arcpy.management.AddField(
                    temp_shapefile, field.name, field.type,
                    field.precision, field.scale, field.length,
                    field.aliasName, field.isNullable, field.required, field.domain
                )

        # Si el campo no existía, añadirlo al final
        if field_obj is None:
            arcpy.management.AddField(temp_shapefile, campo_superficie, "DOUBLE", precision, escala)

        # 7. Copiar geometría y atributos con cursores ---------------------
        temp_fields    = set(f.name for f in arcpy.ListFields(temp_shapefile)
                            if f.type not in ("OID", "Geometry"))
        fields_to_copy = [f.name for f in original_fields
                          if f.name in temp_fields
                          and f.name.lower() != campo_superficie.lower()]

        with arcpy.da.SearchCursor(shapefile_path, ["SHAPE@"] + fields_to_copy) as s_cur:
            with arcpy.da.InsertCursor(temp_shapefile, ["SHAPE@"] + fields_to_copy) as i_cur:
                for row in s_cur:
                    i_cur.insertRow(row)

        # 8. Calcular superficie en la capa temporal -----------------------
        arcpy.management.CalculateGeometryAttributes(
            temp_shapefile,
            geometry_property = [[campo_superficie, "AREA"]],
            area_unit         = "HECTARES",
            coordinate_format = "SAME_AS_INPUT"
        )

        # 9. Eliminar campo "Id" si fue creado por CreateFeatureclass ------
        if any(f.name == "Id" for f in arcpy.ListFields(temp_shapefile)):
            arcpy.management.DeleteField(temp_shapefile, "Id")

        # 10. Reemplazar el archivo original --------------------------------
        arcpy.management.Delete(shapefile_path)
        arcpy.management.CopyFeatures(temp_shapefile, shapefile_path)
        arcpy.management.Delete(temp_shapefile)

        print("Campo '{}' creado y calculado correctamente.".format(campo_superficie))
        return True

    except arcpy.ExecuteError:
        raise RuntimeError("Error de ArcPy:\n{}".format(arcpy.GetMessages(2)))
    except IOError:
        raise
    except Exception as e:
        raise RuntimeError("Error inesperado: {}".format(e))