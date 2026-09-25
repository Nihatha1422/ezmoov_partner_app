-- ==============================================================================
-- Supabase Migration: Outstanding / Outstation Monthly Fee (₹2,000 / month) & Free Flag
-- ==============================================================================

-- 1. Add is_free_driver_outstation column to partner_app_config table
ALTER TABLE public.partner_app_config 
ADD COLUMN IF NOT EXISTS is_free_driver_outstation BOOLEAN DEFAULT false;

-- 2. Add outstation_pass_expires_at to driver_wallets table
ALTER TABLE public.driver_wallets 
ADD COLUMN IF NOT EXISTS outstation_pass_expires_at TIMESTAMPTZ;

ALTER TABLE public.driver_wallets 
ADD COLUMN IF NOT EXISTS outstanding_pass_expires_at TIMESTAMPTZ;

-- 3. RPC Function: Pay Driver Outstation Monthly Fee from Wallet (₹2,000 / month)
CREATE OR REPLACE FUNCTION public.pay_driver_outstation_monthly_fee(
    p_driver_id UUID,
    p_amount NUMERIC DEFAULT 2000.00
)
RETURNS JSONB AS $$
DECLARE
    v_balance NUMERIC(10, 2);
    v_pass_expires_at TIMESTAMPTZ;
    v_current_expiry TIMESTAMPTZ;
BEGIN
    -- Ensure driver wallet exists
    INSERT INTO public.driver_wallets (driver_id, balance) 
    VALUES (p_driver_id, 0.00) 
    ON CONFLICT (driver_id) DO NOTHING;

    -- Lock and fetch current balance & existing pass expiry
    SELECT balance, outstation_pass_expires_at 
    INTO v_balance, v_current_expiry 
    FROM public.driver_wallets 
    WHERE driver_id = p_driver_id 
    FOR UPDATE;

    IF v_balance < p_amount THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Insufficient wallet balance. Minimum ₹' || p_amount::INT || ' required in wallet to purchase 1-month Outstation Pass.',
            'required_amount', p_amount,
            'current_balance', v_balance
        );
    END IF;

    -- Calculate 1-month / 30-day expiry extending existing active pass if any
    IF v_current_expiry IS NOT NULL AND v_current_expiry > now() THEN
        v_pass_expires_at := v_current_expiry + INTERVAL '30 days';
    ELSE
        v_pass_expires_at := now() + INTERVAL '30 days';
    END IF;

    -- Deduct fee and update pass expiration
    UPDATE public.driver_wallets
    SET balance = balance - p_amount,
        outstation_pass_expires_at = v_pass_expires_at,
        outstanding_pass_expires_at = v_pass_expires_at,
        updated_at = now()
    WHERE driver_id = p_driver_id
    RETURNING balance INTO v_balance;

    -- Record transaction in wallet_transactions
    INSERT INTO public.wallet_transactions (
        driver_id, amount, type, description, payment_method, created_at
    ) VALUES (
        p_driver_id,
        -p_amount,
        'outstation_monthly_fee',
        'Outstation Platform Fee (1 Month Pass)',
        'Wallet',
        now()
    );

    -- Insert in-app notification
    INSERT INTO public.driver_notifications (
        driver_id, title, message, type, created_at
    ) VALUES (
        p_driver_id,
        '1-Month Outstation Pass Active 🚀',
        '₹' || p_amount::INT || ' deducted. Your 1-Month Outstation Pass is valid until ' || to_char(v_pass_expires_at, 'Mon DD, YYYY HH:MI AM') || '.',
        'outstation_pass_activated',
        now()
    );

    RETURN jsonb_build_object(
        'success', true,
        'balance', v_balance,
        'outstation_pass_expires_at', v_pass_expires_at,
        'message', '1-Month Outstation Pass activated successfully!'
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.pay_driver_outstation_monthly_fee TO anon, authenticated, service_role;

-- 4. RPC Function: Activate Outstation Pass Directly via Razorpay
CREATE OR REPLACE FUNCTION public.activate_driver_outstation_pass_direct(
    p_driver_id UUID,
    p_payment_id TEXT,
    p_amount NUMERIC DEFAULT 2000.00
)
RETURNS JSONB AS $$
DECLARE
    v_pass_expires_at TIMESTAMPTZ;
    v_current_expiry TIMESTAMPTZ;
    v_balance NUMERIC(10, 2);
BEGIN
    INSERT INTO public.driver_wallets (driver_id, balance) 
    VALUES (p_driver_id, 0.00) 
    ON CONFLICT (driver_id) DO NOTHING;

    SELECT balance, outstation_pass_expires_at 
    INTO v_balance, v_current_expiry 
    FROM public.driver_wallets 
    WHERE driver_id = p_driver_id 
    FOR UPDATE;

    IF v_current_expiry IS NOT NULL AND v_current_expiry > now() THEN
        v_pass_expires_at := v_current_expiry + INTERVAL '30 days';
    ELSE
        v_pass_expires_at := now() + INTERVAL '30 days';
    END IF;

    UPDATE public.driver_wallets
    SET outstation_pass_expires_at = v_pass_expires_at,
        outstanding_pass_expires_at = v_pass_expires_at,
        updated_at = now()
    WHERE driver_id = p_driver_id;

    INSERT INTO public.wallet_transactions (
        driver_id, amount, type, description, reference_id, payment_method, created_at
    ) VALUES (
        p_driver_id,
        -p_amount,
        'outstation_monthly_fee_direct',
        'Outstation Platform Fee (Direct Razorpay 1-Month Pass)',
        p_payment_id,
        'Razorpay',
        now()
    );

    INSERT INTO public.driver_notifications (
        driver_id, title, message, type, created_at
    ) VALUES (
        p_driver_id,
        '1-Month Outstation Pass Active 🚀',
        'Payment successful (Ref: ' || p_payment_id || '). Your 1-Month Outstation Pass is valid until ' || to_char(v_pass_expires_at, 'Mon DD, YYYY HH:MI AM') || '.',
        'outstation_pass_activated',
        now()
    );

    RETURN jsonb_build_object(
        'success', true,
        'outstation_pass_expires_at', v_pass_expires_at,
        'message', '1-Month Outstation Pass activated successfully via direct payment!'
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.activate_driver_outstation_pass_direct TO anon, authenticated, service_role;

-- 5. Updated toggle_driver_outstation_booking with is_free_driver_outstation & monthly pass check
CREATE OR REPLACE FUNCTION public.toggle_driver_outstation_booking(p_driver_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_status BOOLEAN;
  v_wallet_balance NUMERIC := 0.0;
  v_is_free_outstation BOOLEAN := false;
  v_outstation_pass_expiry TIMESTAMPTZ;
BEGIN
  -- Fetch current outstation_booking status
  SELECT COALESCE(outstation_booking, false)
  INTO v_current_status
  FROM public.drivers
  WHERE id = p_driver_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'outstation_booking', false,
      'message', 'Driver not found'
    );
  END IF;

  -- If currently ON (true), turn it OFF (false) unconditionally
  IF v_current_status = true THEN
    UPDATE public.drivers
    SET outstation_booking = false,
        updated_at = NOW()
    WHERE id = p_driver_id;

    RETURN jsonb_build_object(
      'success', true,
      'outstation_booking', false,
      'message', 'Outstation bookings disabled'
    );
  END IF;

  -- Fetch app config free driver outstation flag
  SELECT COALESCE(is_free_driver_outstation, is_free_driver_outstanding, false)
  INTO v_is_free_outstation
  FROM public.partner_app_config
  ORDER BY id DESC LIMIT 1;

  -- Fetch driver wallet balance and pass expiry
  SELECT COALESCE(balance, 0.0), outstation_pass_expires_at
  INTO v_wallet_balance, v_outstation_pass_expiry
  FROM public.driver_wallets
  WHERE driver_id::text = p_driver_id::text;

  IF v_wallet_balance IS NULL THEN
    v_wallet_balance := 0.0;
  END IF;

  -- If outstation fee is NOT free, verify active monthly pass
  IF v_is_free_outstation IS NOT TRUE THEN
    IF v_outstation_pass_expiry IS NULL OR v_outstation_pass_expiry <= NOW() THEN
      RETURN jsonb_build_object(
        'success', false,
        'outstation_booking', false,
        'pass_required', true,
        'message', 'Monthly Outstation Pass required (₹2,000 / month) to accept outstation bookings. Please activate your pass in Wallet.',
        'current_balance', v_wallet_balance
      );
    END IF;
  END IF;

  -- Check if wallet balance is >= 100
  IF v_wallet_balance >= 100 THEN
    UPDATE public.drivers
    SET outstation_booking = true,
        updated_at = NOW()
    WHERE id = p_driver_id;

    RETURN jsonb_build_object(
      'success', true,
      'outstation_booking', true,
      'message', 'Outstation bookings enabled successfully',
      'wallet_balance', v_wallet_balance
    );
  ELSE
    RETURN jsonb_build_object(
      'success', false,
      'outstation_booking', false,
      'message', 'Minimum ₹100 is required in your wallet to enable outstation bookings',
      'current_balance', v_wallet_balance,
      'required_balance', 100
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.toggle_driver_outstation_booking(UUID) TO authenticated, anon, service_role;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
