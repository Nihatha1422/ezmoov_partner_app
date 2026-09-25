-- ============================================================================
-- EZMOOV PARTNER APP: BACKEND AUTOMATIC OFFLINE GUARD & PASS EXPIRY TRIGGER
-- Enforces 24-Hour Daily Pass at Database Level with Proper Record Ordering
-- ============================================================================

-- 1. Ensure driver_daily_status has pass_expires_at column
ALTER TABLE public.driver_daily_status ADD COLUMN IF NOT EXISTS pass_expires_at TIMESTAMPTZ;

-- 2. Drop existing functions to allow update cleanly
DROP FUNCTION IF EXISTS public.check_expired_daily_passes();
DROP FUNCTION IF EXISTS public.prevent_online_without_pass() CASCADE;

-- Function to auto-offline drivers with expired passes (respects free login mode in highest app version)
CREATE OR REPLACE FUNCTION public.check_expired_daily_passes()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_is_free_login BOOLEAN := false;
BEGIN
    -- 1. Check if free driver login is active in the latest/highest partner_app_config
    SELECT COALESCE(is_free_driver_login, false) INTO v_is_free_login
    FROM public.partner_app_config
    ORDER BY 
        CASE 
            WHEN version ~ '^[0-9]+(\.[0-9]+)*$' THEN string_to_array(version, '.')::int[] 
            ELSE ARRAY[0] 
        END DESC, 
        id DESC
    LIMIT 1;

    -- If free login is active, bypass auto-offline
    IF v_is_free_login = true THEN
        RETURN 0;
    END IF;

    UPDATE public.drivers d
    SET is_online = false, updated_at = now()
    FROM (
        SELECT DISTINCT ON (driver_id) driver_id, pass_expires_at, fee_deducted, is_blocked
        FROM public.driver_daily_status
        ORDER BY driver_id, status_date DESC, created_at DESC
    ) s
    WHERE d.id = s.driver_id
      AND d.is_online = true
      AND (
          s.is_blocked = true 
          OR (s.fee_deducted = false AND (s.pass_expires_at IS NULL OR s.pass_expires_at <= now()))
          OR (s.pass_expires_at IS NOT NULL AND s.pass_expires_at <= now())
      );
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 3. Database BEFORE UPDATE Trigger on public.drivers to check active pass (respects free login mode in highest app version)
CREATE OR REPLACE FUNCTION public.prevent_online_without_pass()
RETURNS TRIGGER AS $$
DECLARE
    v_pass_expires_at TIMESTAMPTZ;
    v_is_blocked BOOLEAN := false;
    v_fee_deducted BOOLEAN := false;
    v_rejections INTEGER := 0;
    v_has_record BOOLEAN := false;
    v_is_free_login BOOLEAN := false;
BEGIN
    IF NEW.is_online = true THEN
        -- Check if free driver login is active in the highest partner_app_config version
        SELECT COALESCE(is_free_driver_login, false) INTO v_is_free_login
        FROM public.partner_app_config
        ORDER BY 
            CASE 
                WHEN version ~ '^[0-9]+(\.[0-9]+)*$' THEN string_to_array(version, '.')::int[] 
                ELSE ARRAY[0] 
            END DESC, 
            id DESC
        LIMIT 1;

        -- If free driver login is active, bypass daily pass / fee check
        IF v_is_free_login = true THEN
            SELECT 
                COALESCE(is_blocked, false), 
                COALESCE(rejections_count, 0)
            INTO 
                v_is_blocked, 
                v_rejections
            FROM public.driver_daily_status
            WHERE driver_id = NEW.id
            ORDER BY status_date DESC, created_at DESC
            LIMIT 1;

            IF v_is_blocked = true OR v_rejections >= 2 THEN
                NEW.is_online := false;
                RAISE NOTICE 'Guard: Blocked driver % from going online due to rejection limit / block.', NEW.id;
            END IF;
            
            RETURN NEW;
        END IF;

        -- Fetch the LATEST daily status record for this driver
        SELECT 
            pass_expires_at, 
            COALESCE(is_blocked, false), 
            COALESCE(fee_deducted, false),
            COALESCE(rejections_count, 0),
            true
        INTO 
            v_pass_expires_at, 
            v_is_blocked, 
            v_fee_deducted,
            v_rejections,
            v_has_record
        FROM public.driver_daily_status
        WHERE driver_id = NEW.id
        ORDER BY status_date DESC, created_at DESC
        LIMIT 1;

        -- If driver has an active pass (pass_expires_at in future OR fee_deducted = true for today)
        IF v_has_record = true THEN
            -- Rejections block
            IF v_is_blocked = true OR v_rejections >= 2 THEN
                NEW.is_online := false;
                RAISE NOTICE 'Guard: Blocked driver % from going online due to rejection limit / block.', NEW.id;
            -- Valid pass check
            ELSIF (v_pass_expires_at IS NOT NULL AND v_pass_expires_at > now()) OR (v_fee_deducted = true) THEN
                -- Pass valid! Allow driver to go online
                NULL;
            ELSE
                -- Pass expired & fee not deducted
                NEW.is_online := false;
                RAISE NOTICE 'Guard: Blocked driver % from going online (Pass expired / fee unpaid).', NEW.id;
            END IF;
        ELSE
            -- No daily status record exists yet. Allow driver to go online (first time user setup)
            NULL;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger to public.drivers table
DROP TRIGGER IF EXISTS trg_prevent_online_without_pass ON public.drivers;

CREATE TRIGGER trg_prevent_online_without_pass
BEFORE INSERT OR UPDATE OF is_online ON public.drivers
FOR EACH ROW
EXECUTE FUNCTION public.prevent_online_without_pass();

GRANT EXECUTE ON FUNCTION public.check_expired_daily_passes TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prevent_online_without_pass TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
