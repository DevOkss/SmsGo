-- Run this in Supabase SQL Editor (Dashboard > SQL Editor)
-- Checks if an email already exists in auth.users
CREATE OR REPLACE FUNCTION public.check_email_exists(email_to_check TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM auth.users WHERE email = email_to_check
  );
END;
$$;

-- Allow anonymous/authenticated users to call it
GRANT EXECUTE ON FUNCTION public.check_email_exists(TEXT) TO anon, authenticated;
