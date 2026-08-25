## 20260825

Sin cambios en el módulo: misma corrección del corte de DNS, ahora compilada y
publicada desde este repo.

- Repo propio e independiente (`Aliyerki/AdGuardHomeRoot`) en vez de un fork de
  GitHub, con su propio `updateJson`; los módulos ya instalados se actualizan
  desde aquí.
- `brand.sh` pone el nombre, el autor y la URL de actualización al **compilar**.
  `src/module.prop` y `version.json` quedan idénticos a los del original, así
  sus subidas de versión mensuales ya no chocan al sincronizar.
- Nuevo `update.json` en la raíz: es el manifiesto que consultan los módulos
  instalados. Lo reescribe el workflow al publicar cada release.
- El workflow de compilación comprueba **a diario** si AdGuardTeam publicó un
  AdGuardHome nuevo y, si es así, compila las dos arquitecturas y publica solo.
- Nuevo job **semanal** que abre un issue aquí cuando el proyecto original saca
  cambios; recogerlos sigue siendo manual con `./sync-upstream.sh`.
- `iptables.sh` registraba "DROP IPv6 DNS traffic" cuando las reglas ya usaban
  `REJECT`; corregido el texto del log.

## 20260824

Correcciones para el corte de DNS al arrancar.

- `tool.sh` espera a que AdGuardHome escuche de verdad en `redir_port` antes de
  aplicar las reglas iptables. Antes se redirigía el puerto 53 en el mismo
  segundo en que se lanzaba el binario, dejando el dispositivo sin DNS durante
  todo el arranque del resolutor (~40 s en un Redmi Note 11). Esa ventana hacía
  fallar la comprobación de conectividad de Android, que marcaba la red como
  "sin internet"; el navegador y Google Play se negaban a usarla hasta forzar
  una revalidación a mano con el modo avión.
- Si el listener no llega a tiempo (`startup_timeout`, 120 s por defecto), se
  omiten las reglas iptables en lugar de dejar el dispositivo sin DNS.
- El bloqueo de DNS IPv6 usa `REJECT` en vez de `DROP`, para que el cliente
  caiga a IPv4 de inmediato en vez de esperar el timeout completo (issue #71).
- Upstreams por defecto: Cloudflare y Google sobre DoH con IP literal, sin
  depender del bootstrap.
- Zona horaria por defecto `America/Mexico_City`.
