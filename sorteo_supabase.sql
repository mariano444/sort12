-- ══════════════════════════════════════════════════════════════
--  SORTEO ÉLITE — Schema completo para Supabase
--  Listo para desplegar en el SQL Editor de Supabase
-- ══════════════════════════════════════════════════════════════

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ══════════════════════════════════════════════════════════════
--  TABLA: editions
--  Una fila por cada edición del sorteo
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.editions (
  id              SERIAL PRIMARY KEY,
  edition_number  INTEGER NOT NULL DEFAULT 1,
  status          TEXT NOT NULL DEFAULT 'open'    -- 'open' | 'full' | 'drawing' | 'completed'
                  CHECK (status IN ('open','full','drawing','completed')),
  max_chances     INTEGER NOT NULL DEFAULT 100,
  prize_total     BIGINT NOT NULL DEFAULT 10010000,
  started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insertar la primera edición
INSERT INTO public.editions (edition_number, status, max_chances, prize_total)
VALUES (1, 'open', 100, 10010000)
ON CONFLICT DO NOTHING;


-- ══════════════════════════════════════════════════════════════
--  TABLA: packages
--  Paquetes de participación disponibles
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.packages (
  id          SERIAL PRIMARY KEY,
  label       TEXT NOT NULL,
  chances     INTEGER NOT NULL,
  price       INTEGER NOT NULL,   -- en pesos ARS
  badge       TEXT,               -- ej: 'Popular', 'Mejor valor'
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.packages (label, chances, price, badge, sort_order) VALUES
  ('1 Chance',   1,  2000, NULL,          1),
  ('3 Chances',  3,  5000, 'Popular',     2),
  ('6 Chances',  6, 10000, NULL,          3),
  ('10 Chances', 10,12000, 'Mejor valor', 4)
ON CONFLICT DO NOTHING;


-- ══════════════════════════════════════════════════════════════
--  TABLA: prizes
--  Premios de cada edición
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.prizes (
  id          SERIAL PRIMARY KEY,
  edition_id  INTEGER NOT NULL REFERENCES public.editions(id) ON DELETE CASCADE,
  place       INTEGER NOT NULL,     -- 1, 2, 3, 4 (sorpresa)
  label       TEXT NOT NULL,        -- '1er Premio'
  amount      BIGINT NOT NULL,      -- valor en pesos
  amount_text TEXT NOT NULL,        -- '$6.000.000'
  icon        TEXT NOT NULL DEFAULT '🏆',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Premios para la edición 1
INSERT INTO public.prizes (edition_id, place, label, amount, amount_text, icon) VALUES
  (1, 1, '1er Premio',      6000000, '$6.000.000', '🏆'),
  (1, 2, '2do Premio',      3000000, '$3.000.000', '🥈'),
  (1, 3, '3er Premio',      1000000, '$1.000.000', '🥉'),
  (1, 4, 'Premio Sorpresa',   10000, '$10.000',    '⚡')
ON CONFLICT DO NOTHING;


-- ══════════════════════════════════════════════════════════════
--  TABLA: participants
--  Inscriptos al sorteo
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.participants (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  edition_id      INTEGER NOT NULL REFERENCES public.editions(id) ON DELETE CASCADE,
  package_id      INTEGER REFERENCES public.packages(id),

  -- Datos personales
  first_name      TEXT NOT NULL,
  last_name_initial TEXT NOT NULL,  -- solo la inicial del apellido (privacidad)
  display_name    TEXT NOT NULL,    -- 'Lucía M.'
  whatsapp        TEXT NOT NULL,    -- número completo (privado, no expuesto)
  province        TEXT NOT NULL,
  city            TEXT NOT NULL,
  message         TEXT,             -- sueño/mensaje opcional
  photo_url       TEXT,             -- URL en Supabase Storage (opcional)

  -- Chances
  chances_bought  INTEGER NOT NULL DEFAULT 1,
  bonus_chances   INTEGER NOT NULL DEFAULT 0,
  total_chances   INTEGER GENERATED ALWAYS AS (chances_bought + bonus_chances) STORED,

  -- Pago
  payment_status  TEXT NOT NULL DEFAULT 'pending'
                  CHECK (payment_status IN ('pending','confirmed','rejected')),
  payment_method  TEXT,             -- 'mercadopago' | 'transferencia' | 'cbu'
  payment_ref     TEXT,             -- referencia del pago

  -- Ruleta bonus
  wheel_result    TEXT,             -- resultado de la ruleta (tipo de premio)
  wheel_activated BOOLEAN NOT NULL DEFAULT FALSE,

  registered_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  confirmed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_participants_edition ON public.participants(edition_id);
CREATE INDEX IF NOT EXISTS idx_participants_payment ON public.participants(payment_status);
CREATE INDEX IF NOT EXISTS idx_participants_registered ON public.participants(registered_at DESC);


-- ══════════════════════════════════════════════════════════════
--  TABLA: winners
--  Ganadores por edición y lugar
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.winners (
  id              SERIAL PRIMARY KEY,
  edition_id      INTEGER NOT NULL REFERENCES public.editions(id) ON DELETE CASCADE,
  participant_id  UUID NOT NULL REFERENCES public.participants(id),
  prize_id        INTEGER NOT NULL REFERENCES public.prizes(id),
  place           INTEGER NOT NULL,
  drawn_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payment_status  TEXT NOT NULL DEFAULT 'pending'
                  CHECK (payment_status IN ('pending','paid','partial')),
  paid_at         TIMESTAMPTZ,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (edition_id, place)  -- solo un ganador por lugar por edición
);

CREATE INDEX IF NOT EXISTS idx_winners_edition ON public.winners(edition_id);


-- ══════════════════════════════════════════════════════════════
--  TABLA: archive
--  Historial de ediciones completadas (desnormalizado para display rápido)
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.archive (
  id              SERIAL PRIMARY KEY,
  edition_id      INTEGER NOT NULL REFERENCES public.editions(id),
  edition_number  INTEGER NOT NULL,
  completed_date  DATE NOT NULL,
  participant_count INTEGER NOT NULL,
  total_distributed BIGINT NOT NULL,
  results_json    JSONB,  -- snapshot [{place, prize, winner_name, amount}]
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ══════════════════════════════════════════════════════════════
--  TABLA: wheel_spins
--  Log de cada giro de la ruleta bonus
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.wheel_spins (
  id              SERIAL PRIMARY KEY,
  session_id      TEXT NOT NULL,          -- ID de sesión anónima del visitante
  edition_id      INTEGER REFERENCES public.editions(id),
  segment_type    TEXT NOT NULL,          -- 'mid1' | 'mid3' | 'big' | 'jackpot' | 'legend' | 'mega'
  chances_won     INTEGER NOT NULL DEFAULT 0,
  cash_won        INTEGER NOT NULL DEFAULT 0,
  activated       BOOLEAN NOT NULL DEFAULT FALSE,
  spun_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wheel_spins_session ON public.wheel_spins(session_id);


-- ══════════════════════════════════════════════════════════════
--  VISTA: v_public_participants
--  Solo datos públicos — seguro para exponer sin RLS
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW public.v_public_participants AS
SELECT
  p.id,
  p.edition_id,
  p.display_name,
  p.province,
  p.city,
  p.total_chances,
  p.chances_bought,
  p.bonus_chances,
  p.message,
  p.photo_url,
  p.registered_at,
  CASE WHEN w.id IS NOT NULL THEN TRUE ELSE FALSE END AS is_winner
FROM public.participants p
LEFT JOIN public.winners w ON w.participant_id = p.id
WHERE p.payment_status = 'confirmed';


-- ══════════════════════════════════════════════════════════════
--  VISTA: v_edition_status
--  Estado rápido de la edición activa
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW public.v_edition_status AS
SELECT
  e.id,
  e.edition_number,
  e.status,
  e.max_chances,
  COALESCE(SUM(p.chances_bought), 0)::INTEGER AS chances_sold,
  COALESCE(COUNT(p.id), 0)::INTEGER           AS participant_count,
  (e.max_chances - COALESCE(SUM(p.chances_bought), 0))::INTEGER AS chances_remaining
FROM public.editions e
LEFT JOIN public.participants p
  ON p.edition_id = e.id AND p.payment_status = 'confirmed'
GROUP BY e.id, e.edition_number, e.status, e.max_chances;


-- ══════════════════════════════════════════════════════════════
--  FUNCIÓN: get_active_edition()
--  Retorna la edición activa con su estado
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_active_edition()
RETURNS TABLE (
  edition_id       INTEGER,
  edition_number   INTEGER,
  status           TEXT,
  max_chances      INTEGER,
  chances_sold     INTEGER,
  chances_remaining INTEGER,
  participant_count INTEGER
)
LANGUAGE SQL STABLE AS $$
  SELECT
    id,
    edition_number,
    status,
    max_chances,
    chances_sold,
    chances_remaining,
    participant_count
  FROM public.v_edition_status
  WHERE status IN ('open', 'full', 'drawing')
  ORDER BY edition_number DESC
  LIMIT 1;
$$;


-- ══════════════════════════════════════════════════════════════
--  FUNCIÓN: register_participant()
--  Inscribir un participante con validación de cupos
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.register_participant(
  p_edition_id      INTEGER,
  p_package_id      INTEGER,
  p_first_name      TEXT,
  p_last_name_init  TEXT,
  p_whatsapp        TEXT,
  p_province        TEXT,
  p_city            TEXT,
  p_message         TEXT DEFAULT NULL,
  p_photo_url       TEXT DEFAULT NULL,
  p_bonus_chances   INTEGER DEFAULT 0,
  p_payment_method  TEXT DEFAULT 'mercadopago'
)
RETURNS UUID
LANGUAGE plpgsql AS $$
DECLARE
  v_package       public.packages%ROWTYPE;
  v_edition       public.editions%ROWTYPE;
  v_chances_sold  INTEGER;
  v_participant_id UUID;
BEGIN
  -- Traer paquete
  SELECT * INTO v_package FROM public.packages WHERE id = p_package_id AND is_active = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Paquete no válido: %', p_package_id;
  END IF;

  -- Traer edición y bloquear fila para evitar race condition
  SELECT * INTO v_edition FROM public.editions WHERE id = p_edition_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Edición no encontrada: %', p_edition_id;
  END IF;
  IF v_edition.status NOT IN ('open', 'full') THEN
    RAISE EXCEPTION 'La edición no está abierta para inscripciones';
  END IF;

  -- Verificar cupos disponibles
  SELECT COALESCE(SUM(chances_bought), 0) INTO v_chances_sold
  FROM public.participants
  WHERE edition_id = p_edition_id AND payment_status = 'confirmed';

  IF (v_chances_sold + v_package.chances) > v_edition.max_chances THEN
    RAISE EXCEPTION 'No hay suficientes cupos disponibles. Quedan: %', (v_edition.max_chances - v_chances_sold);
  END IF;

  -- Insertar participante
  INSERT INTO public.participants (
    edition_id, package_id,
    first_name, last_name_initial, display_name,
    whatsapp, province, city, message, photo_url,
    chances_bought, bonus_chances,
    payment_status, payment_method,
    wheel_activated
  ) VALUES (
    p_edition_id, p_package_id,
    p_first_name, p_last_name_init,
    p_first_name || ' ' || p_last_name_init || '.',
    p_whatsapp, p_province, p_city, p_message, p_photo_url,
    v_package.chances, p_bonus_chances,
    'pending', p_payment_method,
    FALSE
  )
  RETURNING id INTO v_participant_id;

  RETURN v_participant_id;
END;
$$;


-- ══════════════════════════════════════════════════════════════
--  FUNCIÓN: confirm_payment()
--  Confirmar pago y marcar si la edición quedó completa
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.confirm_payment(
  p_participant_id UUID,
  p_payment_ref    TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
  v_part          public.participants%ROWTYPE;
  v_chances_sold  INTEGER;
  v_edition       public.editions%ROWTYPE;
BEGIN
  SELECT * INTO v_part FROM public.participants WHERE id = p_participant_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Participante no encontrado';
  END IF;

  -- Confirmar pago
  UPDATE public.participants
  SET payment_status = 'confirmed',
      payment_ref    = COALESCE(p_payment_ref, payment_ref),
      confirmed_at   = NOW()
  WHERE id = p_participant_id;

  -- Recalcular cupos
  SELECT COALESCE(SUM(chances_bought), 0) INTO v_chances_sold
  FROM public.participants
  WHERE edition_id = v_part.edition_id AND payment_status = 'confirmed';

  SELECT * INTO v_edition FROM public.editions WHERE id = v_part.edition_id;

  -- Actualizar estado si se completó
  IF v_chances_sold >= v_edition.max_chances AND v_edition.status = 'open' THEN
    UPDATE public.editions SET status = 'full' WHERE id = v_part.edition_id;
    RETURN 'full';
  END IF;

  RETURN 'confirmed';
END;
$$;


-- ══════════════════════════════════════════════════════════════
--  ROW LEVEL SECURITY (RLS)
-- ══════════════════════════════════════════════════════════════

ALTER TABLE public.editions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prizes        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.participants  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.winners       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.archive       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wheel_spins   ENABLE ROW LEVEL SECURITY;

-- Políticas de lectura pública (anon puede leer datos no sensibles)
CREATE POLICY "editions_public_read"   ON public.editions     FOR SELECT USING (TRUE);
CREATE POLICY "packages_public_read"   ON public.packages     FOR SELECT USING (is_active = TRUE);
CREATE POLICY "prizes_public_read"     ON public.prizes       FOR SELECT USING (TRUE);
CREATE POLICY "archive_public_read"    ON public.archive      FOR SELECT USING (TRUE);

-- winners: solo los campos públicos (sin datos de contacto)
CREATE POLICY "winners_public_read"    ON public.winners      FOR SELECT USING (TRUE);

-- participants: cualquiera puede insertar (inscribirse), solo service_role lee todo
CREATE POLICY "participants_insert"    ON public.participants  FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "participants_read_own"  ON public.participants  FOR SELECT
  USING (auth.uid() IS NOT NULL);  -- requiere auth para leer — ajustar si se necesita anon

-- wheel_spins: insert libre, select propio
CREATE POLICY "wheel_spins_insert"     ON public.wheel_spins  FOR INSERT WITH CHECK (TRUE);
CREATE POLICY "wheel_spins_read_own"   ON public.wheel_spins  FOR SELECT
  USING (session_id = current_setting('request.headers', TRUE)::JSON->>'x-session-id');

-- service_role bypasses RLS automáticamente en Supabase (para admin)


-- ══════════════════════════════════════════════════════════════
--  STORAGE BUCKET para fotos de perfil
--  Ejecutar esto o crearlo desde el Dashboard de Supabase
-- ══════════════════════════════════════════════════════════════

-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('profile-photos', 'profile-photos', TRUE)
-- ON CONFLICT DO NOTHING;

-- CREATE POLICY "profile_photos_upload"
--   ON storage.objects FOR INSERT
--   WITH CHECK (bucket_id = 'profile-photos' AND octet_length(content) < 2097152);  -- máx 2MB

-- CREATE POLICY "profile_photos_public_read"
--   ON storage.objects FOR SELECT
--   USING (bucket_id = 'profile-photos');


-- ══════════════════════════════════════════════════════════════
--  DATOS DE DEMO — participantes iniciales (edición 1)
--  Chances totales = 85 → faltan 15 para completar 100
-- ══════════════════════════════════════════════════════════════

INSERT INTO public.participants (
  edition_id, package_id, first_name, last_name_initial, display_name,
  whatsapp, province, city, message,
  chances_bought, bonus_chances,
  payment_status, confirmed_at, registered_at
) VALUES
  (1, 3, 'Lucía',    'M', 'Lucía M.',     '3510000001', 'Córdoba',       'Córdoba',          'Compraría un auto 0km para llevar a mis hijos al colegio sin depender de nadie.',   6, 1,  'confirmed', NOW() - INTERVAL '5h', NOW() - INTERVAL '5h'),
  (1, 4, 'Martín',   'R', 'Martín R.',    '3510000002', 'Buenos Aires',  'La Plata',         'Pagaría la deuda de mi casa y empezaría un pequeño negocio con mi hermano.',       10, 3, 'confirmed', NOW() - INTERVAL '4h 55m', NOW() - INTERVAL '4h 55m'),
  (1, 2, 'Sofía',    'G', 'Sofía G.',     '3510000003', 'Santa Fe',      'Rosario',          NULL,                                                                               3,  1,  'confirmed', NOW() - INTERVAL '4h 52m', NOW() - INTERVAL '4h 52m'),
  (1, 3, 'Diego',    'F', 'Diego F.',     '3510000004', 'Mendoza',       'Mendoza',          'Me compraría una moto y ahorraría el resto para la universidad de mi hija.',        6,  0,  'confirmed', NOW() - INTERVAL '4h 49m', NOW() - INTERVAL '4h 49m'),
  (1, 3, 'Valentina','P', 'Valentina P.', '3510000005', 'CABA',          'Buenos Aires',     'Viajaría con mi familia a Europa, algo que siempre soñamos y nunca pudimos.',       6,  3,  'confirmed', NOW() - INTERVAL '4h 45m', NOW() - INTERVAL '4h 45m'),
  (1, 2, 'Carlos',   'T', 'Carlos T.',    '3510000006', 'Tucumán',       'San Miguel',       NULL,                                                                               3,  0,  'confirmed', NOW() - INTERVAL '4h 42m', NOW() - INTERVAL '4h 42m'),
  (1, 3, 'Ana',      'L', 'Ana L.',       '3510000007', 'Salta',         'Salta',            'Remodelaría la casa de mis padres que está muy deteriorada. Se lo merecen todo.',   6,  1,  'confirmed', NOW() - INTERVAL '4h 38m', NOW() - INTERVAL '4h 38m'),
  (1, 3, 'Federico', 'S', 'Federico S.',  '3510000008', 'Córdoba',       'Villa Carlos Paz', 'Abriría un local de ropa con mi pareja. Tenemos el proyecto hace 3 años.',          6,  3,  'confirmed', NOW() - INTERVAL '4h 34m', NOW() - INTERVAL '4h 34m'),
  (1, 2, 'Camila',   'B', 'Camila B.',    '3510000009', 'Entre Ríos',    'Paraná',           'Compraría los libros y equipos para terminar mi carrera de enfermería.',            3,  1,  'confirmed', NOW() - INTERVAL '4h 30m', NOW() - INTERVAL '4h 30m'),
  (1, 3, 'Rodrigo',  'V', 'Rodrigo V.',   '3510000010', 'Buenos Aires',  'Mar del Plata',    NULL,                                                                               6,  0,  'confirmed', NOW() - INTERVAL '4h 26m', NOW() - INTERVAL '4h 26m'),
  (1, 2, 'Florencia','A', 'Florencia A.', '3510000011', 'Neuquén',       'Neuquén',          'Pagaría el tratamiento médico que necesita mi mamá y que no cubre la obra social.', 3,  3,  'confirmed', NOW() - INTERVAL '4h 22m', NOW() - INTERVAL '4h 22m'),
  (1, 2, 'Pablo',    'N', 'Pablo N.',     '3510000012', 'Chaco',         'Resistencia',      NULL,                                                                               3,  0,  'confirmed', NOW() - INTERVAL '4h 19m', NOW() - INTERVAL '4h 19m'),
  (1, 2, 'Milagros', 'C', 'Milagros C.',  '3510000013', 'San Juan',      'San Juan',         'Terminaría de construir el cuarto de mi bebé que está por nacer. 🍼',              3,  1,  'confirmed', NOW() - INTERVAL '4h 15m', NOW() - INTERVAL '4h 15m'),
  (1, 1, 'Tomás',    'H', 'Tomás H.',     '3510000014', 'Misiones',      'Posadas',          NULL,                                                                               1,  0,  'confirmed', NOW() - INTERVAL '4h 12m', NOW() - INTERVAL '4h 12m'),
  (1, 2, 'Romina',   'D', 'Romina D.',    '3510000015', 'Santa Cruz',    'Río Gallegos',     'Invertiría en dólares y usaría las ganancias para vivir un poco más tranquila.',    3,  0,  'confirmed', NOW() - INTERVAL '4h 08m', NOW() - INTERVAL '4h 08m')
ON CONFLICT DO NOTHING;

-- ══════════════════════════════════════════════════════════════
--  VERIFICACIÓN FINAL
-- ══════════════════════════════════════════════════════════════

-- Debería mostrar: chances_sold=85, chances_remaining=15
SELECT * FROM public.v_edition_status;
