-- ==============================================================================
-- Supabase Migration: Outstation Booking Toggle RPC & Auto-Disable Trigger
-- ==============================================================================

-- 1. Add outstation_booking column to drivers table
ALTER TABLE public.drivers
ADD COLUMN IF NOT EXISTS outstation_booking BOOLEAN DEFAULT false;

-- 2. Create RPC function to toggle outstation_booking status
CREATE OR REPLACE FUNCTION public.toggle_driver_outstation_booking(p_driver_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_current_status BOOLEAN;
  v_wallet_balance NUMERIC := 0.0;
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

  -- If currently OFF (false), check driver's wallet balance
  SELECT COALESCE(balance, 0.0)
  INTO v_wallet_balance
  FROM public.driver_wallets
  WHERE driver_id::text = p_driver_id::text;

  IF v_wallet_balance IS NULL THEN
    v_wallet_balance := 0.0;
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
    -- Balance is below 100: do not enable and return message
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

-- Grant execution permission on toggle_driver_outstation_booking
GRANT EXECUTE ON FUNCTION public.toggle_driver_outstation_booking(UUID) TO authenticated, anon, service_role;


-- 3. Trigger Function: Automatically disable outstation_booking when wallet balance falls below 100
CREATE OR REPLACE FUNCTION public.check_driver_wallet_balance_for_outstation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- If wallet balance falls below 100, turn off outstation_booking if enabled
  IF NEW.balance < 100 THEN
    UPDATE public.drivers
    SET outstation_booking = false,
        updated_at = NOW()
    WHERE id::text = NEW.driver_id::text
      AND outstation_booking = true;
  END IF;
  RETURN NEW;
END;
$$;

-- 4. Create Trigger on driver_wallets table
DROP TRIGGER IF EXISTS trg_driver_wallet_outstation_check ON public.driver_wallets;
CREATE TRIGGER trg_driver_wallet_outstation_check
AFTER INSERT OR UPDATE OF balance ON public.driver_wallets
FOR EACH ROW
EXECUTE FUNCTION public.check_driver_wallet_balance_for_outstation();
