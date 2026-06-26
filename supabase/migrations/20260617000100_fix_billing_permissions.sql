-- Fix billing mirror permissions for anon/authenticated clients.
-- Run in Supabase SQL Editor for project: obitnetyzyrfzhhvxfnw

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.invoices TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO anon, authenticated;

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "invoices_hybrid_sync" ON public.invoices;
CREATE POLICY "invoices_hybrid_sync" ON public.invoices
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "payments_hybrid_sync" ON public.payments;
CREATE POLICY "payments_hybrid_sync" ON public.payments
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);
