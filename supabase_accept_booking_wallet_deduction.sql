-- ==========================================
-- EZMOOV: DEDUCT ₹100 FROM DRIVER WALLET ON BOOKING ACCEPTANCE
-- ==========================================

-- 1. Create Dedicated RPC Function: deduct_driver_wallet_for_booking
CREATE OR REPLACE FUNCTION public.deduct_driver_wallet_for_booking(
    p_driver_id UUID,
    p_booking_id TEXT,
    p_amount NUMERIC DEFAULT 100.00
)
RETURNS JSONB AS $$
DECLARE
    v_current_bal NUMERIC(10, 2);
    v_new_bal NUMERIC(10, 2);
    v_booking_idx TEXT;
BEGIN
    -- Ensure driver wallet exists
    INSERT INTO public.driver_wallets (driver_id, balance)
    VALUES (p_driver_id, 0.00)
    ON CONFLICT (driver_id) DO NOTHING;

    -- Lock and fetch current balance
    SELECT balance INTO v_current_bal
    FROM public.driver_wallets
    WHERE driver_id = p_driver_id
    FOR UPDATE;

    v_new_bal := COALESCE(v_current_bal, 0.00) - p_amount;

    -- Update balance
    UPDATE public.driver_wallets
    SET balance = v_new_bal,
        updated_at = now()
    WHERE driver_id = p_driver_id;

    -- Record transaction in wallet_transactions
    INSERT INTO public.wallet_transactions (
        driver_id,
        amount,
        type,
        description,
        reference_id,
        created_at
    ) VALUES (
        p_driver_id,
        -p_amount,
        'booking_acceptance',
        'Booking Acceptance Fee for Ride #' || p_booking_id,
        p_booking_id,
        now()
    );

    -- Insert in-app notification
    INSERT INTO public.driver_notifications (
        driver_id,
        title,
        message,
        type,
        created_at
    ) VALUES (
        p_driver_id,
        'Booking Fee Deducted (₹' || p_amount::INT || ') 💳',
        '₹' || p_amount::INT || ' was deducted from your wallet for accepting ride #' || p_booking_id || '. New balance: ₹' || v_new_bal,
        'wallet_deduction_success',
        now()
    );

    RETURN jsonb_build_object(
        'success', true,
        'previous_balance', v_current_bal,
        'balance', v_new_bal,
        'deducted_amount', p_amount,
        'message', '₹' || p_amount || ' deducted from driver wallet for booking #' || p_booking_id
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'message', SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.deduct_driver_wallet_for_booking TO anon, authenticated, service_role;
