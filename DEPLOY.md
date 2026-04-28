# Producción: Supabase + Galiopay

## 1. Variables de entorno

Configurar en Netlify:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_PROFILE_BUCKET`
- `GALIOPAY_CLIENT_ID`
- `GALIOPAY_API_KEY`
- `GALIOPAY_BASE_URL`
- `GALIOPAY_SANDBOX`
- `PUBLIC_SITE_URL`

El navegador ya usa la clave pública de Supabase desde [production.js](/C:/Users/manza/Downloads/files%20(5)/production.js). La `SERVICE_ROLE_KEY` y la API key de Galiopay deben quedar sólo en el servidor.

## 2. SQL

Ejecutar primero:

- [sorteo_supabase.sql](/C:/Users/manza/Downloads/files%20(5)/sorteo_supabase.sql)

Después ejecutar:

- [supabase_production_hardening.sql](/C:/Users/manza/Downloads/files%20(5)/supabase_production_hardening.sql)

## 3. Storage

Crear el bucket público `profile-photos` en Supabase Storage si todavía no existe.

## 4. Flujo de pago

La landing hace esto:

1. Lee edición activa y participantes públicos desde Supabase.
2. Envía el formulario a `/api/create-payment`.
3. La función crea el participante pendiente, genera el link de Galiopay y redirige al checkout.
4. Galiopay notifica a `/api/galiopay-webhook`.
5. La función confirma el pago en Supabase y el frontend refresca el estado al volver.

## 5. Seguridad

- No subir `.env` al proyecto.
- Rotar la API key de Galiopay si estuvo expuesta fuera del panel seguro.
- Usar `GALIOPAY_SANDBOX=true` en pruebas y `false` en producción real.
