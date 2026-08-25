# AdGuardHome for Root — fork de Aliyerki

[English](README.md) | Español

![arm-64](https://img.shields.io/badge/arm--64-soportado-ef476f?logo=linux&logoColor=white)
![arm-v7](https://img.shields.io/badge/arm--v7-soportado-ffa500?logo=linux&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-9b5de5?logo=opensourceinitiative&logoColor=white)

Fork de [twoone-3/AdGuardHomeForRoot](https://github.com/twoone-3/AdGuardHomeForRoot)
con correcciones al corte de DNS que sufría el módulo en cada arranque.

Todo el mérito del módulo original es de [twoone3](https://github.com/twoone-3);
este fork solo añade los parches descritos abajo. Esta página trata de **lo que
cambia el fork**; la documentación del módulo en sí está en el README original en
[inglés](README_en.md) o [chino](README_zh.md), y en la
[guía](docs/index.md).

---

## Por qué existe este fork

Tras cada reinicio el teléfono se quedaba **sin internet en el navegador y en
Google Play**, mientras otras apps sí funcionaban. Poner y quitar el modo avión
lo arreglaba hasta el siguiente reinicio.

Diagnosticando los logs aparecieron tres causas distintas.

### 1. Carrera de arranque (la principal)

`tool.sh` comprobaba `ps | grep AdGuardHome` y acto seguido redirigía el
puerto 53 con iptables. Pero esa comprobación solo demuestra que **el proceso
nació**, no que el servidor DNS ya esté escuchando. El servidor tarda mucho más:
primero carga las listas de filtros y sondea los upstreams.

En un Redmi Note 11 la ventana era de **40 segundos**:

```
21:31:45.804  starting adguard home
21:31:45      Applied iptables rules successfully   <- history.log
21:32:25.988  dnsproxy: listening to udp addr=127.0.0.1:5591
```

Durante esos 40 s **todo el DNS del dispositivo se redirigía a un puerto donde
no había nadie escuchando**. Android hace justo ahí su comprobación de
conectividad, falla, y marca la red como "sin internet". El navegador y Play
Store respetan esa bandera y se niegan a usar la red; las apps que la ignoran
seguían funcionando — de ahí que pareciera un problema de apps y no de DNS.
El modo avión forzaba una revalidación cuando el servidor ya estaba listo.

### 2. Upstreams inalcanzables desde América

La configuración de fábrica apuntaba a servidores DoH chinos con bootstrap
también chino. Desde una red mexicana cada consulta agotaba **20 s de timeout**,
incluidos los dominios que Android necesita para validar la conexión:

```
exchange failed ... question=";www.gstatic.com. IN AAAA"  timeout exceeded
```

### 3. `DROP` del DNS IPv6 en una red IPv6 nativa

El módulo descartaba en silencio las consultas DNS por IPv6. Al no recibir
respuesta, el cliente espera su timeout completo antes de reintentar por IPv4.
Es el mecanismo que describe el
[issue #71](https://github.com/twoone-3/AdGuardHomeForRoot/issues/71) del
original.

---

## Qué cambia respecto al original

| Archivo | Cambio |
|---|---|
| `src/scripts/tool.sh` | Espera a que el DNS escuche de verdad antes de aplicar iptables, leyendo `/proc/net/udp{,6}`. Si no llega en `startup_timeout`, **omite** las reglas en vez de dejar el equipo sin DNS. |
| `src/scripts/iptables.sh` | `REJECT` en lugar de `DROP` para el DNS IPv6, para que el cliente caiga a IPv4 al instante. Vuelve a `DROP` si el kernel no soporta `REJECT`. |
| `src/settings.conf` | Nueva clave `startup_timeout` (120 s). Zona horaria `America/Mexico_City`. |
| `src/bin/AdGuardHome.yaml` | Upstreams Cloudflare y Google por DoH con **IP literal**, así no hace falta resolver nada por bootstrap al arrancar. |
| `fork-brand.sh` | Pone el nombre, el autor y la URL de actualización del fork en `module.prop` **al compilar**. Así `src/module.prop` y `version.json` quedan idénticos a los del original en git y sus subidas de versión mensuales ya no chocan al sincronizar. |
| `pack.sh` | Compilar en Linux (el original solo trae `pack.ps1` de PowerShell). |
| `sync-upstream.sh` | Traer las novedades del repo original sin perder estos parches. |
| `.github/workflows/upstream-check.yml` | Abre un issue aquí cuando el original saca cambios; GitHub no avisa a los forks por su cuenta. |

### Resultado medido, en arranque en frío

| | Antes | Después |
|---|---|---|
| Apagón de DNS | **40.2 s** | **0 s** |
| Arranque del servidor DNS | 40 s | 1.26 s |
| Timeouts en el log | decenas | 0 |
| Red validada sin modo avión | no | **sí** |

El bloqueo de anuncios no se ve afectado: `doubleclick.net` sigue devolviendo
dirección nula y los dominios normales resuelven.

---

## Instalación

1. Descarga el zip de tu arquitectura desde
   [Releases](https://github.com/Aliyerki/AdGuardHomeRoot/releases/latest)
   (`arm64` para la mayoría de teléfonos actuales).
2. Comprueba que **DNS privado esté desactivado**: Ajustes → Red e internet →
   DNS privado. Si está activo, se salta el módulo.
3. Instálalo desde tu gestor root (Magisk, KernelSU o APatch) y reinicia.
4. Panel de control en <http://127.0.0.1:3000>, usuario y contraseña `root`/`root`.

Al **actualizar**, el instalador pregunta si conservar la configuración anterior
(volumen arriba = sí, abajo = no, 30 s sin tocar nada = sí). Conservarla mantiene
tus filtros y estadísticas, pero también **mantiene tu `AdGuardHome.yaml` y tu
`settings.conf` viejos**: los cambios de upstreams o de zona horaria hay que
aplicarlos a mano al archivo del teléfono.

## Compilar

```bash
./pack.sh arm64     # o armv7
```

Descarga el binario oficial de AdGuardHome, lo mete en `src/` y genera el zip
flasheable. Usa `zip` si está instalado y `python3` si no.

## Publicar una versión

Empujar un tag de 8 dígitos es todo el proceso: GitHub Actions compila las dos
arquitecturas, publica la release y actualiza `update.json`, que es el
archivo que consultan los módulos ya instalados:

```bash
git tag 20260901 && git push origin 20260901
```

## Actualizar desde el repo original

Nada trae los cambios del original solo; un job semanal únicamente abre un issue
aquí cuando hay algo que recoger. Para hacerlo:

```bash
./sync-upstream.sh          # revisar los cambios
./sync-upstream.sh --push   # publicarlos
```

Rebasa los parches locales sobre `upstream/main`, muestra qué cambió arriba y
qué se replica, y avisa si hay conflicto. Los conflictos son esperables cuando
el original toca `tool.sh`, `iptables.sh`, `settings.conf`, `pack.yml` o los
README — pero ya no con `module.prop` ni `version.json`, que era donde chocaba
cada release suya.

---

## Estado en el proyecto original

Los dos arreglos genéricos se enviaron como pull requests separados, sin las
partes específicas de este fork (mis DNS, mi zona horaria, mi `updateJson`):

- [#77](https://github.com/twoone-3/AdGuardHomeForRoot/pull/77) — la carrera de arranque
- [#78](https://github.com/twoone-3/AdGuardHomeForRoot/pull/78) — el `REJECT` de IPv6

Si el mantenedor los acepta, `sync-upstream.sh` los absorberá en el rebase y
esos parches locales dejarán de ser necesarios.

## Créditos

Módulo original de [twoone3](https://github.com/twoone-3/AdGuardHomeForRoot).
Licencia MIT, igual que el original.

- [AdGuardHome](https://github.com/AdguardTeam/AdGuardHome)
- [AWAvenue Ads Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule)
