# Geometrías territoriales de los barrios de QA (SCRUM-1396)

Polígonos reales de los seis barrios del catálogo de QA, para la visualización
cartográfica de HU-M04-07. **No son aproximaciones ni centroides**: son los
límites publicados por el Catastro Distrital.

## Procedencia y licencia

| | |
|---|---|
| Fuente | Sector Catastral, Bogotá D.C. — Unidad Administrativa Especial de Catastro Distrital (UAECD) |
| Servicio | `https://serviciosgis.catastrobogota.gov.co/arcgis/rest/services/catastro/sectorcatastral/MapServer/0` |
| Portal | https://datosabiertos.bogota.gov.co/dataset/sector-catastral |
| Licencia | **CC BY 4.0** — exige atribución a la UAECD en cualquier interfaz que muestre estos límites |
| Actualización del dato en la fuente | 30/11/2025 |
| Fecha de extracción | 2026-11-03 |
| Sistema de referencia | **WGS84, EPSG 4326**, tal como lo entrega el servicio: no hubo reproyección |
| Formato | GeoJSON RFC 7946, `FeatureCollection`, coordenadas en orden **longitud, latitud** |

## Procedimiento reproducible

El servicio responde GeoJSON directamente, así que no hace falta descargar el
conjunto completo ni convertir nada:

```sh
curl -s -G "https://serviciosgis.catastrobogota.gov.co/arcgis/rest/services/catastro/sectorcatastral/MapServer/0/query" \
  --data-urlencode "where=SCACODIGO IN ('008201','008307','008214','009123','009109','009212')" \
  --data-urlencode "outFields=SCACODIGO,SCANOMBRE" \
  --data-urlencode "returnGeometry=true" \
  --data-urlencode "outSR=4326" \
  --data-urlencode "f=geojson" \
  -o barrios_catastro.geojson
```

`SCACODIGO` es el identificador del sector catastral y `SCANOMBRE` su nombre.
El servicio admite hasta 2000 registros por consulta; aquí se piden seis.

## Correspondencia con el catálogo, y por qué cambia

**Cuatro de los seis barrios sembrados en QA no existen con ese nombre en el
catastro, y uno de ellos es una trampa:** «La Campina» sí existe como sector
real (`004506`), pero está en el suroccidente de la ciudad, no en Suba. Casar
por nombre habría puesto un barrio de Suba a 15 km de su localidad.

Cada polígono se verificó por centroide contra la ubicación conocida de su
localidad (Chapinero ≈ -74.05, 4.65; Suba ≈ -74.08, 4.74).

| Zona de QA | Nombre sembrado | Sector catastral propuesto | Código | Centroide | Vértices |
|---|---|---|---|---|---|
| `…5001` | Chapinero Alto | CHAPINERO NORTE | `008214` | -74.06103, 4.64966 | 47 |
| `…5002` | Quinta Camacho | QUINTA CAMACHO | `008201` | -74.05951, 4.65483 | 42 |
| `…5003` | Chico Norte | CHICO NORTE | `008307` | -74.04674, 4.67888 | 370 |
| `…5004` | Niza | NIZA NORTE | `009123` | -74.07864, 4.71152 | 207 |
| `…5005` | Suba Centro | SUBA URBANO | `009212` | -74.07985, 4.73970 | 219 |
| `…5006` | La Campina | NIZA SUR | `009109` | -74.07845, 4.70508 | 91 |

Las tres primeras filas quedan bajo Chapinero y las tres últimas bajo Suba, que
es la jerarquía que ya tiene `seed_qa_sprint5.sql`. **Los identificadores de las
zonas no cambian**: solo el nombre, para que corresponda a un sector real.

«Chapinero Alto», «Niza» y «Suba Centro» son nombres de uso corriente que el
catastro no reconoce como sector: Niza, por ejemplo, está dividida en NIZA
NORTE, NIZA SUR y NIZA SUBA. Renombrar la semilla es decisión del dueño del
dato de QA; mientras no se tome, estos polígonos no se pueden asociar a esas
tres zonas.

## Tamaño

40,5 KB para los seis polígonos juntos, entre 42 y 370 vértices cada uno. **No
hace falta simplificar** con este volumen, y no hay motivo para introducir
PostGIS: no hay ninguna consulta espacial, solo transporte y dibujo.

## Lo que falta

- **Las localidades (Chapinero y Suba) y la ciudad no tienen polígono.** La capa
  de límites de localidad no está en el servicio de Sector Catastral; el
  conjunto «Localidad. Bogotá D.C.» es de la Secretaría Distrital de
  Planeación y hay que ubicar su servicio. Mientras no esté, el C1 se puede
  acreditar a nivel de barrio y de sitio, no de zona.
- La carga a la base de QA depende de la tabla de geometrías, cuyo diseño
  corresponde a Core (ADR-0030 §1), y de que DevOps aplique la migración
  (`README.md` del repositorio, «Quién ejecuta las migraciones en cada
  ambiente»).
