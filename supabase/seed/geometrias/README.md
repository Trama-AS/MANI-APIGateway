# Geometrías territoriales del catálogo de QA (SCRUM-1396)

Polígonos reales de las veinte localidades de Bogotá y de los seis barrios del
catálogo de QA, para la visualización cartográfica de HU-M04-07. **No son
aproximaciones ni centroides ni rectángulos**: son los límites publicados por
el Catastro Distrital.

| Archivo | Contenido | Peso |
|---|---|---|
| `localidades_catastro.geojson` | Las 20 localidades | 2,1 MB |
| `barrios_catastro.geojson` | Seis sectores catastrales de Chapinero y Suba | 40,5 KB |

## Procedencia y licencia

| | |
|---|---|
| Fuente | Unidad Administrativa Especial de Catastro Distrital (UAECD): capa **Sector Catastral** para los barrios y capa **Localidad** para las localidades |
| Servicio de barrios | `https://serviciosgis.catastrobogota.gov.co/arcgis/rest/services/catastro/sectorcatastral/MapServer/0` |
| Servicio de localidades | `https://serviciosgis.catastrobogota.gov.co/arcgis/rest/services/ordenamientoterritorial/localidad/MapServer/0` |
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

Las localidades salen de otra capa del mismo servidor, con los mismos
parámetros y los campos `LOCCODIGO` y `LOCNOMBRE`. Se piden **las veinte**, no
un subconjunto: el selector del mapa lista lo que haya en el catálogo, y
sembrar solo dos obligaba a explicar por qué faltaban las demás.

```sh
curl -s -G "https://serviciosgis.catastrobogota.gov.co/arcgis/rest/services/ordenamientoterritorial/localidad/MapServer/0/query" \
  --data-urlencode "where=1=1" \
  --data-urlencode "outFields=LOCCODIGO,LOCNOMBRE" \
  --data-urlencode "returnGeometry=true" \
  --data-urlencode "outSR=4326" \
  --data-urlencode "f=geojson" \
  -o localidades_catastro.geojson
```

Las veinte localidades, por peso del polígono:

| Localidad | Código | Vértices | Peso |
|---|---|---|---|
| Santa Fe | `03` | 16053 | 590,6 KB |
| Candelaria | `17` | 13201 | 485,7 KB |
| Usme | `05` | 7059 | 259,9 KB |
| Ciudad Bolívar | `19` | 6040 | 222,3 KB |
| San Cristóbal | `04` | 3523 | 129,7 KB |
| Chapinero | `02` | 2293 | 84,6 KB |
| Sumapaz | `20` | 2013 | 74,6 KB |
| Usaquén | `01` | 1822 | 67,2 KB |
| Rafael Uribe Uribe | `18` | 941 | 34,7 KB |
| Suba | `11` | 913 | 33,6 KB |
| Tunjuelito | `06` | 906 | 33,4 KB |
| Kennedy | `08` | 863 | 31,9 KB |
| Bosa | `07` | 779 | 28,9 KB |
| Fontibón | `09` | 593 | 21,9 KB |
| Engativá | `10` | 467 | 17,3 KB |
| Los Mártires | `14` | 129 | 4,9 KB |
| Barrios Unidos | `12` | 71 | 2,7 KB |
| Antonio Nariño | `15` | 64 | 2,5 KB |
| Puente Aranda | `16` | 56 | 2,2 KB |
| Teusaquillo | `13` | 54 | 2,1 KB |

El centroide de Chapinero cae más al oriente de lo que sugiere su parte
urbana porque la localidad incluye los cerros orientales. No es un error de
proyección: el polígono es el límite administrativo completo. Por lo mismo,
las localidades del borde sur y oriental (Santa Fe, Candelaria, Usme, Ciudad
Bolívar) son las pesadas: su límite recorre el relieve de los cerros.

## Carga

`scripts/cargar-geometrias.js` genera el SQL y no abre ninguna conexión, así
que las credenciales quedan en manos de quien aplica migraciones en cada
ambiente (ver «Quién ejecuta las migraciones en cada ambiente» en el README del
repositorio):

```sh
node scripts/cargar-geometrias.js | psql "$DATABASE_URL"
```

Empareja **por nombre y nivel**, sin distinguir tildes ni mayúsculas, porque el
catastro publica «USAQUEN» y el catálogo guarda «Usaquén». Un nombre que no
exista en `zona` no se inventa: el script lo reporta al final y su límite no se
carga. Con `--crear-zonas` da de alta las localidades que falten colgando de la
zona `CIUDAD`, que es lo que hace falta en una base local recién migrada.

Requiere la migración `0036` de `MANI-Node`, que crea `geometria_territorial`.

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

## Tamaño, medido

| | Polígonos | Vértices | Peso |
|---|---|---|---|
| Barrios | 6 | 42 a 370 | 40,5 KB |
| Localidades | 20 | 54 a 16053 | 2,1 MB |

**No se simplificó ninguno.** El archivo pesa 2,1 MB, pero **no es lo que viaja
por la red**: el mapa pide una localidad y sus barrios, no el conjunto. El caso
típico (Chapinero con sus tres barrios) son unos 105 KB; el peor caso medido es
Santa Fe sola, 590 KB, porque su límite recorre los cerros orientales.

Simplificar reduciría el peso, pero el criterio aprobado pide **no fijar
umbrales arbitrarios**: si QA mide lentitud en el mapa, ahí se decide la
tolerancia con el dato de la medición, y se regenera con la consulta de
arriba. Mientras no haya esa medición, se entregan los límites exactos.

Tampoco hay motivo para introducir PostGIS: no existe ninguna consulta
espacial en el alcance, solo transporte y dibujo.

## Lo que falta

- **La ciudad (Bogotá D.C.) no tiene polígono.** No hace falta para el mapa:
  la vista se encuadra sobre la localidad y sus barrios. Si se quisiera, la
  capa `ordenamientoterritorial/entidadterritorial` del mismo servidor es el
  sitio por donde empezar.
- La carga a la base de QA depende de la tabla de geometrías, cuyo diseño
  corresponde a Core (ADR-0030 §1), y de que DevOps aplique la migración
  (`README.md` del repositorio, «Quién ejecuta las migraciones en cada
  ambiente»). **Eso es posterior a la aprobación del PR, no un requisito para
  cerrarlo.**
