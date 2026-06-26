-- Law Connect hybrid sync: Firestore (primary) + Supabase (mirror)
-- Run in Supabase Dashboard → SQL Editor (project obitnetyzyrfzhhvxfnw)

-- ─── cases ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cases (
  id TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  attorney_id TEXT,
  case_title TEXT NOT NULL DEFAULT '',
  case_type TEXT NOT NULL DEFAULT '',
  case_description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  documents JSONB DEFAULT '[]'::jsonb,
  progress JSONB DEFAULT '{}'::jsonb,
  staff_id TEXT,
  staff_assigned JSONB DEFAULT '[]'::jsonb,
  hearing_date TIMESTAMPTZ,
  is_archived BOOLEAN NOT NULL DEFAULT false,
  archived_at TIMESTAMPTZ
);

ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS client_id TEXT;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS attorney_id TEXT;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS case_title TEXT DEFAULT '';
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS case_type TEXT DEFAULT '';
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS case_description TEXT DEFAULT '';
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS documents JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS progress JSONB DEFAULT '{}'::jsonb;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS staff_id TEXT;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS staff_assigned JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS hearing_date TIMESTAMPTZ;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT false;
ALTER TABLE public.cases ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;

-- ─── chats ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chats (
  id TEXT PRIMARY KEY,
  participants JSONB NOT NULL DEFAULT '[]'::jsonb,
  last_message TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  client_id TEXT,
  attorney_id TEXT,
  staff_id TEXT,
  staff_email TEXT,
  deleted_for JSONB DEFAULT '[]'::jsonb
);

ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS participants JSONB DEFAULT '[]'::jsonb;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS last_message TEXT;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS client_id TEXT;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS attorney_id TEXT;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS staff_id TEXT;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS staff_email TEXT;
ALTER TABLE public.chats ADD COLUMN IF NOT EXISTS deleted_for JSONB DEFAULT '[]'::jsonb;

-- ─── chat_messages ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id TEXT PRIMARY KEY,
  chat_id TEXT NOT NULL REFERENCES public.chats(id) ON DELETE CASCADE,
  sender_id TEXT NOT NULL,
  text TEXT NOT NULL DEFAULT '',
  attachment_url TEXT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_seen BOOLEAN NOT NULL DEFAULT false,
  sender_role TEXT,
  reactions JSONB DEFAULT '{}'::jsonb
);

ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS chat_id TEXT;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS sender_id TEXT;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS text TEXT DEFAULT '';
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS attachment_url TEXT;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS timestamp TIMESTAMPTZ DEFAULT now();
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS is_seen BOOLEAN DEFAULT false;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS sender_role TEXT;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS reactions JSONB DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_cases_client_id ON public.cases(client_id);
CREATE INDEX IF NOT EXISTS idx_cases_attorney_id ON public.cases(attorney_id);
CREATE INDEX IF NOT EXISTS idx_cases_status ON public.cases(status);
CREATE INDEX IF NOT EXISTS idx_chats_client_id ON public.chats(client_id);
CREATE INDEX IF NOT EXISTS idx_chats_staff_id ON public.chats(staff_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat_id ON public.chat_messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_timestamp ON public.chat_messages(timestamp);

-- ─── invoices ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.invoices (
  id TEXT PRIMARY KEY,
  client_id TEXT NOT NULL,
  client_name TEXT,
  case_id TEXT,
  case_number TEXT,
  case_title TEXT,
  attorney_id TEXT NOT NULL,
  staff_id TEXT,
  description TEXT,
  total_legal_fee DOUBLE PRECISION NOT NULL DEFAULT 0,
  amount_paid DOUBLE PRECISION NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'unpaid',
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  due_date TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_invoices_client_id ON public.invoices(client_id);
CREATE INDEX IF NOT EXISTS idx_invoices_attorney_id ON public.invoices(attorney_id);
CREATE INDEX IF NOT EXISTS idx_invoices_case_id ON public.invoices(case_id);

-- ─── payments ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payments (
  id TEXT PRIMARY KEY,
  invoice_id TEXT NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  client_id TEXT NOT NULL,
  client_name TEXT,
  case_id TEXT,
  case_number TEXT,
  case_title TEXT,
  attorney_id TEXT NOT NULL,
  amount DOUBLE PRECISION NOT NULL DEFAULT 0,
  method TEXT NOT NULL DEFAULT 'cash',
  status TEXT NOT NULL DEFAULT 'completed',
  reference_no TEXT,
  note TEXT,
  recorded_by TEXT,
  recorded_by_name TEXT,
  recorded_by_role TEXT,
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_invoice_id ON public.payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_payments_client_id ON public.payments(client_id);
CREATE INDEX IF NOT EXISTS idx_payments_attorney_id ON public.payments(attorney_id);

-- ─── API access (required for Flutter anon key) ──────────────────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chats TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_messages TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.invoices TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payments TO anon, authenticated;

ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cases_hybrid_sync" ON public.cases;
CREATE POLICY "cases_hybrid_sync" ON public.cases
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "chats_hybrid_sync" ON public.chats;
CREATE POLICY "chats_hybrid_sync" ON public.chats
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "chat_messages_hybrid_sync" ON public.chat_messages;
CREATE POLICY "chat_messages_hybrid_sync" ON public.chat_messages
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "invoices_hybrid_sync" ON public.invoices;
CREATE POLICY "invoices_hybrid_sync" ON public.invoices
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "payments_hybrid_sync" ON public.payments;
CREATE POLICY "payments_hybrid_sync" ON public.payments
  FOR ALL TO anon, authenticated
  USING (true) WITH CHECK (true);

-- Enable realtime (optional — for future Supabase live listeners)
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.cases;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chats;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.invoices;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
