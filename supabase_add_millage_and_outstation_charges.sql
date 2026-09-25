-- ============================================================================
-- EZMOOV: SAFE ADD MILLAGE_COST AND OUTSTATION_CHARGES TO VEHICLE_TYPES
-- (Safely updates rows without altering vehicle names or violating vehicles FK constraint)
-- ============================================================================

-- 1. Add extra columns to public.vehicle_types
ALTER TABLE public.vehicle_types ADD COLUMN IF NOT EXISTS millage_cost NUMERIC(10, 2) DEFAULT 0.00;
ALTER TABLE public.vehicle_types ADD COLUMN IF NOT EXISTS outstation_charges NUMERIC(10, 2) DEFAULT 0.00;

-- Optional alias columns
ALTER TABLE public.vehicle_types ADD COLUMN IF NOT EXISTS mileage_cost NUMERIC(10, 2) DEFAULT 0.00;
ALTER TABLE public.vehicle_types ADD COLUMN IF NOT EXISTS outstation_charge NUMERIC(10, 2) DEFAULT 0.00;

-- 2. Update existing vehicle types in place by id (Preserves 'name' to satisfy FK constraint)
-- • 2 Wheeler (id: 1): millage_cost = 0.00, outstation_charges = 0.00
-- • 3 Wheeler (id: 2): millage_cost = 3.50, outstation_charges = 27.00
-- • 4 Wheeler / Tata Ace (id: 4): millage_cost = 4.00, outstation_charges = 35.50
-- • 8 Ft Vehicle (id: 5): millage_cost = 7.00, outstation_charges = 35.71
-- • 9 Ft Vehicle (id: 6): millage_cost = 7.00, outstation_charges = 42.90
-- • 10 Ft Vehicle (id: 7): millage_cost = 7.00, outstation_charges = 45.00

UPDATE public.vehicle_types
SET 
    millage_cost = 0.00,
    mileage_cost = 0.00,
    outstation_charges = 0.00,
    outstation_charge = 0.00
WHERE id = 1 OR LOWER(name) LIKE '%2%wheel%';

UPDATE public.vehicle_types
SET 
    millage_cost = 3.50,
    mileage_cost = 3.50,
    outstation_charges = 27.00,
    outstation_charge = 27.00
WHERE id = 2 OR LOWER(name) LIKE '%3%wheel%';

UPDATE public.vehicle_types
SET 
    millage_cost = 4.00,
    mileage_cost = 4.00,
    outstation_charges = 35.50,
    outstation_charge = 35.50
WHERE id = 4 OR LOWER(name) LIKE '%4%wheel%' OR LOWER(name) LIKE '%ace%';

UPDATE public.vehicle_types
SET 
    millage_cost = 7.00,
    mileage_cost = 7.00,
    outstation_charges = 35.71,
    outstation_charge = 35.71
WHERE id = 5 OR LOWER(name) LIKE '%8%ft%' OR capacity_kg = 1200.00;

UPDATE public.vehicle_types
SET 
    millage_cost = 7.00,
    mileage_cost = 7.00,
    outstation_charges = 42.90,
    outstation_charge = 42.90
WHERE id = 6 OR LOWER(name) LIKE '%9%ft%' OR capacity_kg = 1700.00;

UPDATE public.vehicle_types
SET 
    millage_cost = 7.00,
    mileage_cost = 7.00,
    outstation_charges = 45.00,
    outstation_charge = 45.00
WHERE id = 7 OR LOWER(name) LIKE '%10%ft%' OR capacity_kg = 2000.00;

-- 3. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

-- 4. Verify updated vehicle types dataset
SELECT 
    id, 
    name, 
    capacity, 
    capacity_kg, 
    base_fare, 
    daily_fee,
    grace_time,
    waittime,
    millage_cost, 
    outstation_charges
FROM public.vehicle_types 
ORDER BY id;
