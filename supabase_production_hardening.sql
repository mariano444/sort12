-- Production hardening for Supabase + Galiopay
-- Run this after sorteo_supabase.sql

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

ALTER TABLE public.participants
  ADD COLUMN IF NOT EXISTS payout_account TEXT,
  ADD COLUMN IF NOT EXISTS payment_provider TEXT,
  ADD COLUMN IF NOT EXISTS payment_link_url TEXT,
  ADD COLUMN IF NOT EXISTS payment_metadata JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE TABLE IF NOT EXISTS public.payment_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_id UUID NOT NULL REFERENCES public.participants(id) ON DELETE CASCADE,
  edition_id INTEGER NOT NULL REFERENCES public.editions(id) ON DELETE CASCADE,
  package_id INTEGER NOT NULL REFERENCES public.packages(id),
  provider TEXT NOT NULL DEFAULT 'galiopay',
  reference_id TEXT NOT NULL UNIQUE,
  provider_reference TEXT UNIQUE,
  provider_payment_id TEXT UNIQUE,
  proof_token TEXT,
  checkout_url TEXT NOT NULL,
  amount INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'ARS',
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected', 'expired', 'cancelled', 'refunded')),
  provider_status TEXT,
  notification_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_sessions_participant
  ON public.payment_sessions(participant_id);

CREATE INDEX IF NOT EXISTS idx_payment_sessions_reference
  ON public.payment_sessions(reference_id);

CREATE INDEX IF NOT EXISTS idx_payment_sessions_provider_payment
  ON public.payment_sessions(provider_payment_id);

CREATE INDEX IF NOT EXISTS idx_payment_sessions_status
  ON public.payment_sessions(status, created_at DESC);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_sessions_updated_at ON public.payment_sessions;
CREATE TRIGGER trg_payment_sessions_updated_at
BEFORE UPDATE ON public.payment_sessions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.public_get_active_edition()
RETURNS TABLE (
  edition_id INTEGER,
  edition_number INTEGER,
  status TEXT,
  max_chances INTEGER,
  chances_sold INTEGER,
  chances_remaining INTEGER,
  participant_count INTEGER,
  prize_total BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    e.id,
    e.edition_number,
    e.status,
    e.max_chances,
    COALESCE(v.chances_sold, 0)::INTEGER,
    COALESCE(v.chances_remaining, e.max_chances)::INTEGER,
    COALESCE(v.participant_count, 0)::INTEGER,
    e.prize_total
  FROM public.editions e
  LEFT JOIN public.v_edition_status v ON v.id = e.id
  WHERE e.status IN ('open', 'full', 'drawing')
  ORDER BY e.edition_number DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.public_list_participants(p_edition_id INTEGER)
RETURNS TABLE (
  id UUID,
  display_name TEXT,
  province TEXT,
  city TEXT,
  chances_bought INTEGER,
  bonus_chances INTEGER,
  total_chances INTEGER,
  message TEXT,
  photo_url TEXT,
  registered_at TIMESTAMPTZ,
  is_winner BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.display_name,
    p.province,
    p.city,
    p.chances_bought,
    p.bonus_chances,
    p.total_chances,
    p.message,
    p.photo_url,
    p.registered_at,
    EXISTS (
      SELECT 1
      FROM public.winners w
      WHERE w.participant_id = p.id
    ) AS is_winner
  FROM public.participants p
  WHERE p.edition_id = p_edition_id
    AND p.payment_status = 'confirmed'
  ORDER BY p.registered_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.mark_galiopay_payment(
  p_reference_id TEXT,
  p_provider_payment_id TEXT DEFAULT NULL,
  p_provider_status TEXT DEFAULT NULL,
  p_payload JSONB DEFAULT '{}'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.payment_sessions%ROWTYPE;
  v_new_status TEXT;
BEGIN
  SELECT *
  INTO v_session
  FROM public.payment_sessions
  WHERE reference_id = p_reference_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment session not found for reference %', p_reference_id;
  END IF;

  v_new_status := CASE
    WHEN LOWER(COALESCE(p_provider_status, '')) IN ('approved', 'paid', 'confirmed', 'success', 'succeeded') THEN 'approved'
    WHEN LOWER(COALESCE(p_provider_status, '')) IN ('rejected', 'failed') THEN 'rejected'
    WHEN LOWER(COALESCE(p_provider_status, '')) IN ('expired') THEN 'expired'
    WHEN LOWER(COALESCE(p_provider_status, '')) IN ('cancelled', 'canceled') THEN 'cancelled'
    WHEN LOWER(COALESCE(p_provider_status, '')) IN ('refunded') THEN 'refunded'
    ELSE v_session.status
  END;

  UPDATE public.payment_sessions
  SET
    provider_payment_id = COALESCE(p_provider_payment_id, provider_payment_id),
    provider_status = COALESCE(p_provider_status, provider_status),
    status = v_new_status,
    notification_payload = COALESCE(p_payload, notification_payload),
    paid_at = CASE
      WHEN v_new_status = 'approved' THEN COALESCE(paid_at, NOW())
      ELSE paid_at
    END
  WHERE id = v_session.id;

  IF v_new_status = 'approved' THEN
    PERFORM public.confirm_payment(
      v_session.participant_id,
      COALESCE(p_provider_payment_id, v_session.provider_payment_id, v_session.reference_id)
    );

    UPDATE public.participants
    SET
      payment_provider = 'galiopay',
      payment_ref = COALESCE(p_provider_payment_id, payment_ref, v_session.reference_id),
      payment_link_url = COALESCE(payment_link_url, v_session.checkout_url),
      payment_metadata = COALESCE(payment_metadata, '{}'::JSONB) || jsonb_build_object(
        'provider_reference', COALESCE(v_session.provider_reference, ''),
        'last_provider_status', COALESCE(p_provider_status, '')
      )
    WHERE id = v_session.participant_id;
  END IF;

  RETURN v_session.participant_id;
END;
$$;

ALTER TABLE public.payment_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payment_sessions_service_only ON public.payment_sessions;
CREATE POLICY payment_sessions_service_only
  ON public.payment_sessions
  FOR ALL
  USING (FALSE)
  WITH CHECK (FALSE);

DROP POLICY IF EXISTS participants_read_own ON public.participants;
DROP POLICY IF EXISTS participants_insert ON public.participants;

GRANT EXECUTE ON FUNCTION public.public_get_active_edition() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.public_list_participants(INTEGER) TO anon, authenticated;

COMMENT ON FUNCTION public.public_get_active_edition IS
  'Safe public RPC for active edition status.';

COMMENT ON FUNCTION public.public_list_participants(INTEGER) IS
  'Safe public RPC that exposes only confirmed participant data already intended for display.';
