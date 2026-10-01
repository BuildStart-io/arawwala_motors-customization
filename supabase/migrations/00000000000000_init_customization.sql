
-- 1. Create the new schema
CREATE SCHEMA IF NOT EXISTS arawwala_motors_customization;

-- 2. Grant usage
GRANT USAGE ON SCHEMA arawwala_motors_customization TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA arawwala_motors_customization TO postgres;

-- 3. Schema dump
--
-- PostgreSQL database dump
--

\restrict R7DDBNPoHg5lW0iYAdBMe4mz1SgnbHcqcOIhD2KuCe0RvVYu7897aSIdT9HpYmk

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA arawwala_motors_customization;


ALTER SCHEMA arawwala_motors_customization OWNER TO pg_database_owner;

--
-- Name: SCHEMA arawwala_motors_customization; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA arawwala_motors_customization IS 'standard public schema';


--
-- Name: app_role; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE arawwala_motors_customization.app_role AS ENUM (
    'super_admin',
    'business_user'
);


ALTER TYPE arawwala_motors_customization.app_role OWNER TO postgres;

--
-- Name: plan_tier; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE arawwala_motors_customization.plan_tier AS ENUM (
    'free',
    'pro',
    'enterprise'
);


ALTER TYPE arawwala_motors_customization.plan_tier OWNER TO postgres;

--
-- Name: can_read_usage(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.can_read_usage(_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT auth.uid() IS NULL
      OR auth.uid() = _user_id
      OR arawwala_motors_customization.has_role(auth.uid(), 'super_admin'::app_role)
      OR arawwala_motors_customization.is_staff_of(auth.uid(), _user_id)
$$;


ALTER FUNCTION arawwala_motors_customization.can_read_usage(_user_id uuid) OWNER TO postgres;

--
-- Name: enforce_order_limit(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.enforce_order_limit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  current_count INT;
  max_allowed INT;
  tier TEXT;
  addon INT;
  plan_max INT;
  platform_limits JSONB;
  billing_start TIMESTAMPTZ;
  month_start TIMESTAMPTZ;
  next_date TIMESTAMPTZ;
  user_paused BOOLEAN;
BEGIN
  SELECT p.plan_tier, p.addon_orders, p.billing_cycle_start, p.is_paused
  INTO tier, addon, billing_start, user_paused
  FROM profiles p WHERE p.user_id = NEW.user_id;

  IF user_paused = true THEN
    RAISE EXCEPTION 'Account is paused. Cannot create orders.';
  END IF;

  IF tier IS NULL THEN
    tier := 'free';
    addon := 0;
  END IF;

  -- Calculate billing month start
  IF billing_start IS NOT NULL THEN
    month_start := billing_start;
    LOOP
      next_date := month_start + INTERVAL '1 month';
      EXIT WHEN next_date > NOW();
      month_start := next_date;
    END LOOP;
  ELSE
    month_start := date_trunc('month', NOW());
  END IF;

  SELECT ps.value INTO platform_limits
  FROM platform_settings ps WHERE ps.key = 'plan_limits';

  IF platform_limits IS NOT NULL AND platform_limits->tier IS NOT NULL THEN
    plan_max := COALESCE((platform_limits->tier->>'max_orders_per_month')::INT, 50);
  ELSE
    plan_max := CASE tier WHEN 'pro' THEN 500 WHEN 'enterprise' THEN 9999 ELSE 50 END;
  END IF;

  max_allowed := plan_max + COALESCE(addon, 0);

  SELECT COUNT(*) INTO current_count
  FROM orders WHERE user_id = NEW.user_id AND created_at >= month_start;

  IF current_count >= max_allowed THEN
    RAISE EXCEPTION 'Monthly order limit reached (% of %). Upgrade your plan to process more orders.', current_count, max_allowed;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION arawwala_motors_customization.enforce_order_limit() OWNER TO postgres;

--
-- Name: get_ai_message_usage(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.get_ai_message_usage(_user_id uuid, _since timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE c integer;
BEGIN
  IF NOT arawwala_motors_customization.can_read_usage(_user_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT COUNT(*) INTO c
  FROM arawwala_motors_customization.ai_usage_logs
  WHERE user_id = _user_id AND created_at >= _since;
  RETURN COALESCE(c, 0);
END;
$$;


ALTER FUNCTION arawwala_motors_customization.get_ai_message_usage(_user_id uuid, _since timestamp with time zone) OWNER TO postgres;

--
-- Name: get_contact_usage(uuid, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.get_contact_usage(_user_id uuid, _since timestamp with time zone) RETURNS integer
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE c integer;
BEGIN
  IF NOT arawwala_motors_customization.can_read_usage(_user_id) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  SELECT COUNT(DISTINCT phone_number) INTO c
  FROM arawwala_motors_customization.contact_usage
  WHERE user_id = _user_id AND created_at >= _since;
  RETURN COALESCE(c, 0);
END;
$$;


ALTER FUNCTION arawwala_motors_customization.get_contact_usage(_user_id uuid, _since timestamp with time zone) OWNER TO postgres;

--
-- Name: get_staff_owner_id(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.get_staff_owner_id(_user_id uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT owner_id FROM arawwala_motors_customization.staff_accounts
  WHERE staff_user_id = _user_id AND is_active = true
  LIMIT 1
$$;


ALTER FUNCTION arawwala_motors_customization.get_staff_owner_id(_user_id uuid) OWNER TO postgres;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.profiles (user_id, email, full_name)
  VALUES (NEW.id, NEW.email, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email));
  RETURN NEW;
END;
$$;


ALTER FUNCTION arawwala_motors_customization.handle_new_user() OWNER TO postgres;

--
-- Name: handle_new_user_role(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.handle_new_user_role() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.user_roles (user_id, role)
  VALUES (NEW.id, 'business_user');
  RETURN NEW;
END;
$$;


ALTER FUNCTION arawwala_motors_customization.handle_new_user_role() OWNER TO postgres;

--
-- Name: handle_new_user_settings(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.handle_new_user_settings() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.settings (user_id, key, value) VALUES
    (NEW.id, 'welcome_message', '{"text": "Welcome! How can I help you today?"}'::jsonb),
    (NEW.id, 'payment_info', '{"bank_name": "", "account_number": "", "account_name": ""}'::jsonb),
    (NEW.id, 'auto_responses', '{"enabled": true}'::jsonb);
  RETURN NEW;
END;
$$;


ALTER FUNCTION arawwala_motors_customization.handle_new_user_settings() OWNER TO postgres;

--
-- Name: has_role(uuid, arawwala_motors_customization.app_role); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.has_role(_user_id uuid, _role arawwala_motors_customization.app_role) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM arawwala_motors_customization.user_roles
    WHERE user_id = _user_id AND role = _role
  )
$$;


ALTER FUNCTION arawwala_motors_customization.has_role(_user_id uuid, _role arawwala_motors_customization.app_role) OWNER TO postgres;

--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.is_admin() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM arawwala_motors_customization.profiles
    WHERE user_id = auth.uid()
  );
END;
$$;


ALTER FUNCTION arawwala_motors_customization.is_admin() OWNER TO postgres;

--
-- Name: is_staff_of(uuid, uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.is_staff_of(_staff_user_id uuid, _owner_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM arawwala_motors_customization.staff_accounts
    WHERE staff_user_id = _staff_user_id
      AND owner_id = _owner_id
      AND is_active = true
  )
$$;


ALTER FUNCTION arawwala_motors_customization.is_staff_of(_staff_user_id uuid, _owner_id uuid) OWNER TO postgres;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION arawwala_motors_customization.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION arawwala_motors_customization.update_updated_at_column() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ai_usage_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.ai_usage_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    phone_number text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE arawwala_motors_customization.ai_usage_logs OWNER TO postgres;

--
-- Name: chat_takeovers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.chat_takeovers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    phone_number text NOT NULL,
    is_taken_over boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE arawwala_motors_customization.chat_takeovers OWNER TO postgres;

--
-- Name: contact_usage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.contact_usage (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    phone_number text NOT NULL,
    period_start timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE arawwala_motors_customization.contact_usage OWNER TO postgres;

--
-- Name: conversations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    phone_number text NOT NULL,
    message text NOT NULL,
    direction text NOT NULL,
    message_type text DEFAULT 'text'::text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    CONSTRAINT conversations_direction_check CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text])))
);


ALTER TABLE arawwala_motors_customization.conversations OWNER TO postgres;

--
-- Name: faq_usage_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.faq_usage_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    faq_id uuid NOT NULL,
    user_id uuid NOT NULL,
    phone_number text NOT NULL,
    sender_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE arawwala_motors_customization.faq_usage_logs OWNER TO postgres;

--
-- Name: faqs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.faqs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    question text NOT NULL,
    answer text NOT NULL,
    product_id uuid,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    is_tracked boolean DEFAULT false NOT NULL,
    media_urls text[] DEFAULT '{}'::text[] NOT NULL
);


ALTER TABLE arawwala_motors_customization.faqs OWNER TO postgres;

--
-- Name: fcm_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.fcm_tokens (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    device_token text NOT NULL,
    device_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE arawwala_motors_customization.fcm_tokens OWNER TO postgres;

--
-- Name: leads; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    phone_number text NOT NULL,
    customer_name text,
    assigned_to uuid,
    status text DEFAULT 'new'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    product_name text,
    vehicle_model text
);


ALTER TABLE arawwala_motors_customization.leads OWNER TO postgres;

--
-- Name: message_queue; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.message_queue (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    wsender_message_id text NOT NULL,
    user_id uuid NOT NULL,
    phone_number text NOT NULL,
    sender_name text DEFAULT 'Unknown'::text,
    message_text text DEFAULT ''::text,
    message_type text DEFAULT 'text'::text,
    session_api_key text,
    raw_payload jsonb DEFAULT '{}'::jsonb,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    correlation_id text
);


ALTER TABLE arawwala_motors_customization.message_queue OWNER TO postgres;

--
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_name text NOT NULL,
    customer_phone text NOT NULL,
    customer_address text,
    order_items jsonb DEFAULT '[]'::jsonb NOT NULL,
    special_instructions text,
    payment_method text DEFAULT 'cod'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    total_amount numeric(10,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    whatsapp_phone text,
    district text,
    CONSTRAINT orders_payment_method_check CHECK ((payment_method = ANY (ARRAY['cod'::text, 'bank_transfer'::text]))),
    CONSTRAINT orders_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'shipped'::text, 'delivered'::text, 'cancelled'::text])))
);


ALTER TABLE arawwala_motors_customization.orders OWNER TO postgres;

--
-- Name: platform_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.platform_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    value jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE arawwala_motors_customization.platform_settings OWNER TO postgres;

--
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    description text,
    price numeric(10,2) DEFAULT 0 NOT NULL,
    product_type text DEFAULT 'physical'::text NOT NULL,
    variations jsonb DEFAULT '[]'::jsonb,
    images text[] DEFAULT '{}'::text[],
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    delivery_price numeric DEFAULT 0,
    video_url text,
    CONSTRAINT products_product_type_check CHECK ((product_type = ANY (ARRAY['physical'::text, 'digital'::text])))
);


ALTER TABLE arawwala_motors_customization.products OWNER TO postgres;

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    full_name text,
    email text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    plan_tier arawwala_motors_customization.plan_tier DEFAULT 'free'::public.plan_tier NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    business_name text,
    max_products integer DEFAULT 5,
    max_faqs integer DEFAULT 10,
    billing_cycle_start timestamp with time zone DEFAULT now(),
    is_paused boolean DEFAULT false NOT NULL,
    addon_products integer DEFAULT 0 NOT NULL,
    addon_faqs integer DEFAULT 0 NOT NULL,
    addon_orders integer DEFAULT 0 NOT NULL,
    addon_ai_messages integer DEFAULT 0 NOT NULL,
    addon_images integer DEFAULT 0 NOT NULL,
    addon_staff integer DEFAULT 0 NOT NULL,
    addon_contacts integer DEFAULT 0 NOT NULL
);


ALTER TABLE arawwala_motors_customization.profiles OWNER TO postgres;

--
-- Name: settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key text NOT NULL,
    value jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL
);


ALTER TABLE arawwala_motors_customization.settings OWNER TO postgres;

--
-- Name: staff_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.staff_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid NOT NULL,
    staff_user_id uuid NOT NULL,
    staff_email text NOT NULL,
    staff_name text,
    permissions text[] DEFAULT '{}'::text[] NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    whatsapp_number text
);


ALTER TABLE arawwala_motors_customization.staff_accounts OWNER TO postgres;

--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.user_roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role arawwala_motors_customization.app_role DEFAULT 'business_user'::public.app_role NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE arawwala_motors_customization.user_roles OWNER TO postgres;

--
-- Name: user_wsender_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE arawwala_motors_customization.user_wsender_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    session_id text NOT NULL,
    session_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    session_api_key text
);


ALTER TABLE arawwala_motors_customization.user_wsender_sessions OWNER TO postgres;

--
-- Name: ai_usage_logs ai_usage_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.ai_usage_logs
    ADD CONSTRAINT ai_usage_logs_pkey PRIMARY KEY (id);


--
-- Name: chat_takeovers chat_takeovers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.chat_takeovers
    ADD CONSTRAINT chat_takeovers_pkey PRIMARY KEY (id);


--
-- Name: chat_takeovers chat_takeovers_user_id_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.chat_takeovers
    ADD CONSTRAINT chat_takeovers_user_id_phone_number_key UNIQUE (user_id, phone_number);


--
-- Name: contact_usage contact_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.contact_usage
    ADD CONSTRAINT contact_usage_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: faq_usage_logs faq_usage_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.faq_usage_logs
    ADD CONSTRAINT faq_usage_logs_pkey PRIMARY KEY (id);


--
-- Name: faqs faqs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.faqs
    ADD CONSTRAINT faqs_pkey PRIMARY KEY (id);


--
-- Name: fcm_tokens fcm_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.fcm_tokens
    ADD CONSTRAINT fcm_tokens_pkey PRIMARY KEY (id);


--
-- Name: fcm_tokens fcm_tokens_user_id_device_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.fcm_tokens
    ADD CONSTRAINT fcm_tokens_user_id_device_token_key UNIQUE (user_id, device_token);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: leads leads_user_id_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.leads
    ADD CONSTRAINT leads_user_id_phone_number_key UNIQUE (user_id, phone_number);


--
-- Name: message_queue message_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.message_queue
    ADD CONSTRAINT message_queue_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: platform_settings platform_settings_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.platform_settings
    ADD CONSTRAINT platform_settings_key_key UNIQUE (key);


--
-- Name: platform_settings platform_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.platform_settings
    ADD CONSTRAINT platform_settings_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.profiles
    ADD CONSTRAINT profiles_user_id_key UNIQUE (user_id);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: settings settings_user_id_key_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.settings
    ADD CONSTRAINT settings_user_id_key_unique UNIQUE (user_id, key);


--
-- Name: staff_accounts staff_accounts_owner_id_staff_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.staff_accounts
    ADD CONSTRAINT staff_accounts_owner_id_staff_user_id_key UNIQUE (owner_id, staff_user_id);


--
-- Name: staff_accounts staff_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.staff_accounts
    ADD CONSTRAINT staff_accounts_pkey PRIMARY KEY (id);


--
-- Name: message_queue unique_wsender_message; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.message_queue
    ADD CONSTRAINT unique_wsender_message UNIQUE (wsender_message_id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_user_id_role_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.user_roles
    ADD CONSTRAINT user_roles_user_id_role_key UNIQUE (user_id, role);


--
-- Name: user_wsender_sessions user_wsender_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.user_wsender_sessions
    ADD CONSTRAINT user_wsender_sessions_pkey PRIMARY KEY (id);


--
-- Name: user_wsender_sessions user_wsender_sessions_user_id_session_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.user_wsender_sessions
    ADD CONSTRAINT user_wsender_sessions_user_id_session_id_key UNIQUE (user_id, session_id);


--
-- Name: contact_usage_unique_per_cycle; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX contact_usage_unique_per_cycle ON arawwala_motors_customization.contact_usage USING btree (user_id, phone_number, period_start);


--
-- Name: idx_ai_usage_logs_user_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_ai_usage_logs_user_created ON arawwala_motors_customization.ai_usage_logs USING btree (user_id, created_at);


--
-- Name: idx_contact_usage_user_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_contact_usage_user_created ON arawwala_motors_customization.contact_usage USING btree (user_id, created_at);


--
-- Name: idx_conversations_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_created_at ON arawwala_motors_customization.conversations USING btree (created_at DESC);


--
-- Name: idx_conversations_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_conversations_phone ON arawwala_motors_customization.conversations USING btree (phone_number);


--
-- Name: idx_faq_usage_logs_faq_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_faq_usage_logs_faq_id ON arawwala_motors_customization.faq_usage_logs USING btree (faq_id);


--
-- Name: idx_faq_usage_logs_user_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_faq_usage_logs_user_phone ON arawwala_motors_customization.faq_usage_logs USING btree (user_id, phone_number);


--
-- Name: idx_leads_assigned; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_leads_assigned ON arawwala_motors_customization.leads USING btree (assigned_to);


--
-- Name: idx_leads_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_leads_user ON arawwala_motors_customization.leads USING btree (user_id);


--
-- Name: idx_message_queue_processed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_message_queue_processed ON arawwala_motors_customization.message_queue USING btree (processed_at) WHERE (status = 'done'::text);


--
-- Name: idx_message_queue_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_message_queue_status ON arawwala_motors_customization.message_queue USING btree (status, created_at) WHERE (status = ANY (ARRAY['pending'::text, 'failed'::text]));


--
-- Name: idx_message_queue_status_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_message_queue_status_created ON arawwala_motors_customization.message_queue USING btree (status, created_at) WHERE (status = ANY (ARRAY['pending'::text, 'failed'::text]));


--
-- Name: idx_message_queue_user_processing; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_message_queue_user_processing ON arawwala_motors_customization.message_queue USING btree (user_id) WHERE (status = 'processing'::text);


--
-- Name: idx_orders_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_created_at ON arawwala_motors_customization.orders USING btree (created_at DESC);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_orders_status ON arawwala_motors_customization.orders USING btree (status);


--
-- Name: orders check_order_limit; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER check_order_limit BEFORE INSERT ON arawwala_motors_customization.orders FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.enforce_order_limit();


--
-- Name: faqs update_faqs_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_faqs_updated_at BEFORE UPDATE ON arawwala_motors_customization.faqs FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: fcm_tokens update_fcm_tokens_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_fcm_tokens_updated_at BEFORE UPDATE ON arawwala_motors_customization.fcm_tokens FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: leads update_leads_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_leads_updated_at BEFORE UPDATE ON arawwala_motors_customization.leads FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: message_queue update_message_queue_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_message_queue_updated_at BEFORE UPDATE ON arawwala_motors_customization.message_queue FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: orders update_orders_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON arawwala_motors_customization.orders FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: platform_settings update_platform_settings_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_platform_settings_updated_at BEFORE UPDATE ON arawwala_motors_customization.platform_settings FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: products update_products_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON arawwala_motors_customization.products FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: profiles update_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON arawwala_motors_customization.profiles FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: settings update_settings_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_settings_updated_at BEFORE UPDATE ON arawwala_motors_customization.settings FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: staff_accounts update_staff_accounts_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_staff_accounts_updated_at BEFORE UPDATE ON arawwala_motors_customization.staff_accounts FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.update_updated_at_column();


--
-- Name: conversations conversations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.conversations
    ADD CONSTRAINT conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: faq_usage_logs faq_usage_logs_faq_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.faq_usage_logs
    ADD CONSTRAINT faq_usage_logs_faq_id_fkey FOREIGN KEY (faq_id) REFERENCES arawwala_motors_customization.faqs(id) ON DELETE CASCADE;


--
-- Name: faqs faqs_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.faqs
    ADD CONSTRAINT faqs_product_id_fkey FOREIGN KEY (product_id) REFERENCES arawwala_motors_customization.products(id) ON DELETE SET NULL;


--
-- Name: faqs faqs_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.faqs
    ADD CONSTRAINT faqs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: products products_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.products
    ADD CONSTRAINT products_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.profiles
    ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: settings settings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.settings
    ADD CONSTRAINT settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: staff_accounts staff_accounts_staff_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.staff_accounts
    ADD CONSTRAINT staff_accounts_staff_user_id_fkey FOREIGN KEY (staff_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: user_wsender_sessions user_wsender_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY arawwala_motors_customization.user_wsender_sessions
    ADD CONSTRAINT user_wsender_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: platform_settings Authenticated users can view platform settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Authenticated users can view platform settings" ON arawwala_motors_customization.platform_settings FOR SELECT USING ((auth.uid() IS NOT NULL));


--
-- Name: staff_accounts Owners can create staff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Owners can create staff" ON arawwala_motors_customization.staff_accounts FOR INSERT WITH CHECK ((auth.uid() = owner_id));


--
-- Name: staff_accounts Owners can delete their staff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Owners can delete their staff" ON arawwala_motors_customization.staff_accounts FOR DELETE USING ((auth.uid() = owner_id));


--
-- Name: staff_accounts Owners can update their staff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Owners can update their staff" ON arawwala_motors_customization.staff_accounts FOR UPDATE USING ((auth.uid() = owner_id));


--
-- Name: staff_accounts Owners can view their staff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Owners can view their staff" ON arawwala_motors_customization.staff_accounts FOR SELECT USING ((auth.uid() = owner_id));


--
-- Name: leads Owners manage their leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Owners manage their leads" ON arawwala_motors_customization.leads TO authenticated USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: profiles Service can insert profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Service can insert profiles" ON arawwala_motors_customization.profiles FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: conversations Staff can create owner conversations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can create owner conversations" ON arawwala_motors_customization.conversations FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = conversations.user_id) AND (sa.is_active = true) AND ('conversations'::text = ANY (sa.permissions))))));


--
-- Name: faqs Staff can create owner faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can create owner faqs" ON arawwala_motors_customization.faqs FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = faqs.user_id) AND (sa.is_active = true) AND ('faqs'::text = ANY (sa.permissions))))));


--
-- Name: products Staff can create owner products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can create owner products" ON arawwala_motors_customization.products FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = products.user_id) AND (sa.is_active = true) AND ('products'::text = ANY (sa.permissions))))));


--
-- Name: chat_takeovers Staff can manage owner takeovers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can manage owner takeovers" ON arawwala_motors_customization.chat_takeovers FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = chat_takeovers.user_id) AND (sa.is_active = true) AND ('conversations'::text = ANY (sa.permissions))))));


--
-- Name: faqs Staff can update owner faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can update owner faqs" ON arawwala_motors_customization.faqs FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = faqs.user_id) AND (sa.is_active = true) AND ('faqs'::text = ANY (sa.permissions))))));


--
-- Name: orders Staff can update owner orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can update owner orders" ON arawwala_motors_customization.orders FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = orders.user_id) AND (sa.is_active = true) AND ('orders'::text = ANY (sa.permissions))))));


--
-- Name: products Staff can update owner products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can update owner products" ON arawwala_motors_customization.products FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = products.user_id) AND (sa.is_active = true) AND ('products'::text = ANY (sa.permissions))))));


--
-- Name: chat_takeovers Staff can update owner takeovers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can update owner takeovers" ON arawwala_motors_customization.chat_takeovers FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = chat_takeovers.user_id) AND (sa.is_active = true) AND ('conversations'::text = ANY (sa.permissions))))));


--
-- Name: staff_accounts Staff can view own record; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view own record" ON arawwala_motors_customization.staff_accounts FOR SELECT USING ((auth.uid() = staff_user_id));


--
-- Name: conversations Staff can view owner conversations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner conversations" ON arawwala_motors_customization.conversations FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = conversations.user_id) AND (sa.is_active = true) AND ('conversations'::text = ANY (sa.permissions))))));


--
-- Name: faq_usage_logs Staff can view owner faq usage logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner faq usage logs" ON arawwala_motors_customization.faq_usage_logs FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = faq_usage_logs.user_id) AND (sa.is_active = true) AND ('faqs'::text = ANY (sa.permissions))))));


--
-- Name: faqs Staff can view owner faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner faqs" ON arawwala_motors_customization.faqs FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = faqs.user_id) AND (sa.is_active = true) AND ('faqs'::text = ANY (sa.permissions))))));


--
-- Name: orders Staff can view owner orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner orders" ON arawwala_motors_customization.orders FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = orders.user_id) AND (sa.is_active = true) AND ('orders'::text = ANY (sa.permissions))))));


--
-- Name: products Staff can view owner products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner products" ON arawwala_motors_customization.products FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = products.user_id) AND (sa.is_active = true) AND ('products'::text = ANY (sa.permissions))))));


--
-- Name: profiles Staff can view owner profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner profile" ON arawwala_motors_customization.profiles FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = profiles.user_id) AND (sa.is_active = true)))));


--
-- Name: settings Staff can view owner settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner settings" ON arawwala_motors_customization.settings FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = settings.user_id) AND (sa.is_active = true)))));


--
-- Name: chat_takeovers Staff can view owner takeovers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff can view owner takeovers" ON arawwala_motors_customization.chat_takeovers FOR SELECT USING ((EXISTS ( SELECT 1
   FROM arawwala_motors_customization.staff_accounts sa
  WHERE ((sa.staff_user_id = auth.uid()) AND (sa.owner_id = chat_takeovers.user_id) AND (sa.is_active = true) AND ('conversations'::text = ANY (sa.permissions))))));


--
-- Name: leads Staff insert owner leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff insert owner leads" ON arawwala_motors_customization.leads FOR INSERT TO authenticated WITH CHECK (public.is_staff_of(auth.uid(), user_id));


--
-- Name: leads Staff update owner leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff update owner leads" ON arawwala_motors_customization.leads FOR UPDATE TO authenticated USING (public.is_staff_of(auth.uid(), user_id)) WITH CHECK (public.is_staff_of(auth.uid(), user_id));


--
-- Name: leads Staff view owner leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Staff view owner leads" ON arawwala_motors_customization.leads FOR SELECT TO authenticated USING (public.is_staff_of(auth.uid(), user_id));


--
-- Name: faqs Super admins can delete all faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can delete all faqs" ON arawwala_motors_customization.faqs FOR DELETE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: platform_settings Super admins can delete platform settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can delete platform settings" ON arawwala_motors_customization.platform_settings FOR DELETE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: user_roles Super admins can delete roles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can delete roles" ON arawwala_motors_customization.user_roles FOR DELETE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: platform_settings Super admins can insert platform settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can insert platform settings" ON arawwala_motors_customization.platform_settings FOR INSERT WITH CHECK (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: user_roles Super admins can manage roles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can manage roles" ON arawwala_motors_customization.user_roles FOR INSERT WITH CHECK (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: faqs Super admins can update all faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update all faqs" ON arawwala_motors_customization.faqs FOR UPDATE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: orders Super admins can update all orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update all orders" ON arawwala_motors_customization.orders FOR UPDATE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: profiles Super admins can update all profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update all profiles" ON arawwala_motors_customization.profiles FOR UPDATE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: settings Super admins can update all settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update all settings" ON arawwala_motors_customization.settings FOR UPDATE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: platform_settings Super admins can update platform settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update platform settings" ON arawwala_motors_customization.platform_settings FOR UPDATE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: user_roles Super admins can update roles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can update roles" ON arawwala_motors_customization.user_roles FOR UPDATE USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: ai_usage_logs Super admins can view all ai usage logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all ai usage logs" ON arawwala_motors_customization.ai_usage_logs FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: contact_usage Super admins can view all contact usage; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all contact usage" ON arawwala_motors_customization.contact_usage FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: conversations Super admins can view all conversations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all conversations" ON arawwala_motors_customization.conversations FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: faqs Super admins can view all faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all faqs" ON arawwala_motors_customization.faqs FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: orders Super admins can view all orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all orders" ON arawwala_motors_customization.orders FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: profiles Super admins can view all profiles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all profiles" ON arawwala_motors_customization.profiles FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: user_wsender_sessions Super admins can view all sessions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all sessions" ON arawwala_motors_customization.user_wsender_sessions FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: settings Super admins can view all settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all settings" ON arawwala_motors_customization.settings FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: staff_accounts Super admins can view all staff; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view all staff" ON arawwala_motors_customization.staff_accounts FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: platform_settings Super admins can view platform settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins can view platform settings" ON arawwala_motors_customization.platform_settings FOR SELECT USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: leads Super admins view all leads; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Super admins view all leads" ON arawwala_motors_customization.leads FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'super_admin'::public.app_role));


--
-- Name: conversations Users can create own conversations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can create own conversations" ON arawwala_motors_customization.conversations FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: faqs Users can create own faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can create own faqs" ON arawwala_motors_customization.faqs FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: orders Users can create own orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can create own orders" ON arawwala_motors_customization.orders FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: products Users can create own products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can create own products" ON arawwala_motors_customization.products FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: user_wsender_sessions Users can create own sessions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can create own sessions" ON arawwala_motors_customization.user_wsender_sessions FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: settings Users can create own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can create own settings" ON arawwala_motors_customization.settings FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: conversations Users can delete own conversations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete own conversations" ON arawwala_motors_customization.conversations FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: faqs Users can delete own faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete own faqs" ON arawwala_motors_customization.faqs FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: orders Users can delete own orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete own orders" ON arawwala_motors_customization.orders FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: products Users can delete own products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete own products" ON arawwala_motors_customization.products FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: user_wsender_sessions Users can delete own sessions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete own sessions" ON arawwala_motors_customization.user_wsender_sessions FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: settings Users can delete own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete own settings" ON arawwala_motors_customization.settings FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: fcm_tokens Users can delete own tokens; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete own tokens" ON arawwala_motors_customization.fcm_tokens FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: chat_takeovers Users can delete their own takeovers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can delete their own takeovers" ON arawwala_motors_customization.chat_takeovers FOR DELETE USING ((auth.uid() = user_id));


--
-- Name: fcm_tokens Users can insert own tokens; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert own tokens" ON arawwala_motors_customization.fcm_tokens FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: chat_takeovers Users can insert their own takeovers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can insert their own takeovers" ON arawwala_motors_customization.chat_takeovers FOR INSERT WITH CHECK ((auth.uid() = user_id));


--
-- Name: conversations Users can update own conversations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own conversations" ON arawwala_motors_customization.conversations FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: faqs Users can update own faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own faqs" ON arawwala_motors_customization.faqs FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: orders Users can update own orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own orders" ON arawwala_motors_customization.orders FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: products Users can update own products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own products" ON arawwala_motors_customization.products FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: user_wsender_sessions Users can update own sessions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own sessions" ON arawwala_motors_customization.user_wsender_sessions FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: settings Users can update own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own settings" ON arawwala_motors_customization.settings FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: fcm_tokens Users can update own tokens; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update own tokens" ON arawwala_motors_customization.fcm_tokens FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: profiles Users can update their own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update their own profile" ON arawwala_motors_customization.profiles FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: chat_takeovers Users can update their own takeovers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can update their own takeovers" ON arawwala_motors_customization.chat_takeovers FOR UPDATE USING ((auth.uid() = user_id));


--
-- Name: ai_usage_logs Users can view own ai usage logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own ai usage logs" ON arawwala_motors_customization.ai_usage_logs FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: contact_usage Users can view own contact usage; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own contact usage" ON arawwala_motors_customization.contact_usage FOR SELECT TO authenticated USING (((auth.uid() = user_id) OR arawwala_motors_customization.is_staff_of(auth.uid(), user_id)));


--
-- Name: conversations Users can view own conversations; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own conversations" ON arawwala_motors_customization.conversations FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: faq_usage_logs Users can view own faq usage logs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own faq usage logs" ON arawwala_motors_customization.faq_usage_logs FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: faqs Users can view own faqs; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own faqs" ON arawwala_motors_customization.faqs FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: orders Users can view own orders; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own orders" ON arawwala_motors_customization.orders FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: products Users can view own products; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own products" ON arawwala_motors_customization.products FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: user_roles Users can view own roles; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own roles" ON arawwala_motors_customization.user_roles FOR SELECT USING (((auth.uid() = user_id) OR arawwala_motors_customization.has_role(auth.uid(), 'super_admin'::public.app_role)));


--
-- Name: user_wsender_sessions Users can view own sessions; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own sessions" ON arawwala_motors_customization.user_wsender_sessions FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: settings Users can view own settings; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own settings" ON arawwala_motors_customization.settings FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: fcm_tokens Users can view own tokens; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view own tokens" ON arawwala_motors_customization.fcm_tokens FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: profiles Users can view their own profile; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view their own profile" ON arawwala_motors_customization.profiles FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: chat_takeovers Users can view their own takeovers; Type: POLICY; Schema: public; Owner: postgres
--

CREATE POLICY "Users can view their own takeovers" ON arawwala_motors_customization.chat_takeovers FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: ai_usage_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.ai_usage_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_takeovers; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.chat_takeovers ENABLE ROW LEVEL SECURITY;

--
-- Name: contact_usage; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.contact_usage ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: faq_usage_logs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.faq_usage_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: faqs; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.faqs ENABLE ROW LEVEL SECURITY;

--
-- Name: fcm_tokens; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.fcm_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: leads; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.leads ENABLE ROW LEVEL SECURITY;

--
-- Name: message_queue; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.message_queue ENABLE ROW LEVEL SECURITY;

--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.platform_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.products ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: settings; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.settings ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_accounts; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.staff_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: user_roles; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.user_roles ENABLE ROW LEVEL SECURITY;

--
-- Name: user_wsender_sessions; Type: ROW SECURITY; Schema: public; Owner: postgres
--

ALTER TABLE arawwala_motors_customization.user_wsender_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA arawwala_motors_customization; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA arawwala_motors_customization TO postgres;
GRANT USAGE ON SCHEMA arawwala_motors_customization TO anon;
GRANT USAGE ON SCHEMA arawwala_motors_customization TO authenticated;
GRANT USAGE ON SCHEMA arawwala_motors_customization TO service_role;


--
-- Name: FUNCTION can_read_usage(_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.can_read_usage(_user_id uuid) TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.can_read_usage(_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.can_read_usage(_user_id uuid) TO service_role;


--
-- Name: FUNCTION enforce_order_limit(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.enforce_order_limit() TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.enforce_order_limit() TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.enforce_order_limit() TO service_role;


--
-- Name: FUNCTION get_ai_message_usage(_user_id uuid, _since timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.get_ai_message_usage(_user_id uuid, _since timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.get_ai_message_usage(_user_id uuid, _since timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.get_ai_message_usage(_user_id uuid, _since timestamp with time zone) TO service_role;


--
-- Name: FUNCTION get_contact_usage(_user_id uuid, _since timestamp with time zone); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.get_contact_usage(_user_id uuid, _since timestamp with time zone) TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.get_contact_usage(_user_id uuid, _since timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.get_contact_usage(_user_id uuid, _since timestamp with time zone) TO service_role;


--
-- Name: FUNCTION get_staff_owner_id(_user_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.get_staff_owner_id(_user_id uuid) TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.get_staff_owner_id(_user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.get_staff_owner_id(_user_id uuid) TO service_role;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user() TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user() TO service_role;


--
-- Name: FUNCTION handle_new_user_role(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user_role() TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user_role() TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user_role() TO service_role;


--
-- Name: FUNCTION handle_new_user_settings(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user_settings() TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user_settings() TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.handle_new_user_settings() TO service_role;


--
-- Name: FUNCTION has_role(_user_id uuid, _role arawwala_motors_customization.app_role); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.has_role(_user_id uuid, _role arawwala_motors_customization.app_role) TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.has_role(_user_id uuid, _role arawwala_motors_customization.app_role) TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.has_role(_user_id uuid, _role arawwala_motors_customization.app_role) TO service_role;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.is_admin() TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.is_admin() TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.is_admin() TO service_role;


--
-- Name: FUNCTION is_staff_of(_staff_user_id uuid, _owner_id uuid); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.is_staff_of(_staff_user_id uuid, _owner_id uuid) TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.is_staff_of(_staff_user_id uuid, _owner_id uuid) TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.is_staff_of(_staff_user_id uuid, _owner_id uuid) TO service_role;


--
-- Name: FUNCTION update_updated_at_column(); Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON FUNCTION arawwala_motors_customization.update_updated_at_column() TO anon;
GRANT ALL ON FUNCTION arawwala_motors_customization.update_updated_at_column() TO authenticated;
GRANT ALL ON FUNCTION arawwala_motors_customization.update_updated_at_column() TO service_role;


--
-- Name: TABLE ai_usage_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.ai_usage_logs TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.ai_usage_logs TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.ai_usage_logs TO service_role;


--
-- Name: TABLE chat_takeovers; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.chat_takeovers TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.chat_takeovers TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.chat_takeovers TO service_role;


--
-- Name: TABLE contact_usage; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.contact_usage TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.contact_usage TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.contact_usage TO service_role;


--
-- Name: TABLE conversations; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.conversations TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.conversations TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.conversations TO service_role;


--
-- Name: TABLE faq_usage_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.faq_usage_logs TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.faq_usage_logs TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.faq_usage_logs TO service_role;


--
-- Name: TABLE faqs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.faqs TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.faqs TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.faqs TO service_role;


--
-- Name: TABLE fcm_tokens; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.fcm_tokens TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.fcm_tokens TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.fcm_tokens TO service_role;


--
-- Name: TABLE leads; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.leads TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.leads TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.leads TO service_role;


--
-- Name: TABLE message_queue; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.message_queue TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.message_queue TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.message_queue TO service_role;


--
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.orders TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.orders TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.orders TO service_role;


--
-- Name: TABLE platform_settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.platform_settings TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.platform_settings TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.platform_settings TO service_role;


--
-- Name: TABLE products; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.products TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.products TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.products TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.profiles TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.profiles TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.profiles TO service_role;


--
-- Name: TABLE settings; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.settings TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.settings TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.settings TO service_role;


--
-- Name: TABLE staff_accounts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.staff_accounts TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.staff_accounts TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.staff_accounts TO service_role;


--
-- Name: TABLE user_roles; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.user_roles TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.user_roles TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.user_roles TO service_role;


--
-- Name: TABLE user_wsender_sessions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE arawwala_motors_customization.user_wsender_sessions TO anon;
GRANT ALL ON TABLE arawwala_motors_customization.user_wsender_sessions TO authenticated;
GRANT ALL ON TABLE arawwala_motors_customization.user_wsender_sessions TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA arawwala_motors_customization GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict R7DDBNPoHg5lW0iYAdBMe4mz1SgnbHcqcOIhD2KuCe0RvVYu7897aSIdT9HpYmk



-- 4. Data dump
--
-- PostgreSQL database dump
--

\restrict uIIL95zWHxf06J6MmQbSzq1x5GZjbKeAnKSfkAiL3OosFu0ndJT8digHwyfDikP

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: ai_usage_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.ai_usage_logs (id, user_id, phone_number, created_at) FROM stdin;
f8bcee01-e37d-407f-8850-eb43ecf54b54	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-09-29 15:01:55.791272+00
b52ec04d-b273-47ea-80c2-a23004558a65	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-09-29 15:02:20.430523+00
941a6fd1-9ea6-4d28-a2b8-813bd9ac71fe	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-09-29 15:03:06.139845+00
574a47fa-f4b8-4b1e-9ff7-470e816fac59	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-09-29 15:03:22.706067+00
d1dc1d2c-543a-46df-a345-93d3a27f29b9	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-09-29 15:03:49.226682+00
1c71a1f0-1384-4d83-9fcf-d738d04fe92b	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-09-29 15:04:19.513919+00
91017e78-dea5-4dc2-977b-8d42235c8d3a	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:14:29.679868+00
7cd47f7c-710a-4520-8dfe-625c1906d8fa	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:15:42.144918+00
8c5cd412-3f0c-4788-ad05-647acb8f4fed	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:27:41.192788+00
33e33fe3-b67f-48fe-b5fb-66734c932926	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:28:54.061792+00
cede0674-9306-4292-b25a-fb4adcec6613	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:29:05.23024+00
8fd4d42f-0a4b-4ed1-b318-1a706168e0cd	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:29:32.422981+00
b00a8c9e-3f48-4ab3-8047-2cd108ad15b2	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:30:18.471592+00
61c2038e-b2f1-4357-b3fa-b0673e2f65a5	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:34:05.458947+00
92b0362c-af23-465c-afc6-a0723f17779a	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:34:26.14389+00
f70fd6d8-ad18-495a-8e58-26188ae3a942	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:34:47.071247+00
c2f372b4-62cd-4ea9-9788-9fc27d526f41	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:35:27.853795+00
674a252a-4eda-4185-a667-e06ec457a568	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:35:51.314553+00
fb968967-57e6-420f-b64a-f96702705ccd	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:43:36.83228+00
0beffcfd-06dc-4382-83e5-8318b07a9089	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:43:49.916763+00
fa4580a6-be17-4daa-a151-c952a9d8cad4	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:44:16.428319+00
4bb3f3a3-baab-474e-ac82-ef8b9045d394	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:45:32.688252+00
cda1e2b0-8caf-430f-a9bf-a9555111660a	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-10-01 10:45:49.409064+00
\.


--
-- Data for Name: chat_takeovers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.chat_takeovers (id, user_id, phone_number, is_taken_over, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: contact_usage; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.contact_usage (id, user_id, phone_number, period_start, created_at) FROM stdin;
7d225cc1-7001-4bd6-9d84-916c5d89bbf5	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	2026-09-28 16:31:36.561+00	2026-09-29 14:57:56.230412+00
\.


--
-- Data for Name: conversations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.conversations (id, phone_number, message, direction, message_type, metadata, created_at, user_id) FROM stdin;
2891fe98-a6d2-4dd9-9a6b-1e5c18e65fa3	94773552869	ඔව් සර් ලංකාව වටේම පැය 16ක් ඇතුලත Deliver කරල දෙන්න පුලුවන් අපිට.\n\nසෙනසුරාදා ඉරිදා හා පෝය දින හැර සතියේ ඕනම දවසක හවස 5 වන තෙක් orders දාන්න පුලුවන්.\n\nYes sir, we can deliver within 16 hours all over Sri Lanka. Orders can be placed on any day of the week except Saturday, Sunday and Poya days until 5.00 p.m.	outbound	text	{"correlationId": "d309d6db-25c3-444d-bf53-af0890dc6221"}	2026-10-01 10:43:49.931252+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
1b97f043-1046-4435-a352-141872eb3353	94773552869	Mokenda delivery karanne oyala	inbound	text	{"raw": {"id": "evt_01m3vh131pts6s3ree0jfws68f", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AB0FC4BA205D3A716CE", "ack": 2, "body": "Mokenda delivery karanne oyala", "from": "156745469018156@lid", "_data": {"key": {"id": "3AB0FC4BA205D3A716CE", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Mokenda delivery karanne oyala", "messageContextInfo": {"messageSecret": "tkfC2Dj5LOzTL10SzTYFtBzuQvbMMHm/FwEl5WpkwHs=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851451}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851451}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851451958, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}, "event": "message", "is_voice": false, "senderName": "Dulnith Liyanage", "correlationId": "523767d3-300e-4560-b879-eee55cc33820"}	2026-10-01 10:44:12.931007+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
308815dc-85a4-46b1-b7fb-5794676d4b55	94773552869	අපි ඩිලිවරි සඳහා Prompt Xpress ආයතනය භාවිතා කරනවා.\n\nඔබේ පැකේජය ඇති ස්ථානය මෙම ලින්ක් එකෙන් පරීක්ෂා කළ හැකියි:\n\nකොළ පාට ස්ටිකරයේ ඇති RPxxxxxxxx අංකය ඇතුළත් කරන්න.\n\nWe use Prompt Xpress for our deliveries.\n\nYou can track your package here:\n\nEnter the RPxxxxxxxx number found on the green sticker.	outbound	text	{"correlationId": "523767d3-300e-4560-b879-eee55cc33820"}	2026-10-01 10:44:16.43788+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
34865a1f-85e9-4d5a-810c-4544df628d5a	94773552869	Arawwala Motors\n📍 කටාන පන්සල ඉදිරිපිට\n100/79, City Gate Temple Junction, Katana North, Katana.\n\n📞 077-3844123 / 077-4811555\n🌍 Google Maps: https://maps.app.goo.gl/hG3BtEuqJ1e7m27AA?g_st=com.google.maps.preview.copy	outbound	text	{"correlationId": "30c15806-fc2b-415a-8687-f7d9a2a4e207"}	2026-10-01 10:45:49.423852+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
8d0918b7-e929-45da-addd-47fda8baa026	94773552869	Gana keeyak yanawada delivery ekata	inbound	text	{"raw": {"id": "evt_01m3vh3ek74e2aed764fhz1txh", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3ADF8A9212375477EF3C", "ack": 2, "body": "Gana keeyak yanawada delivery ekata", "from": "156745469018156@lid", "_data": {"key": {"id": "3ADF8A9212375477EF3C", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Gana keeyak yanawada delivery ekata", "messageContextInfo": {"messageSecret": "Sbo8YCp5r5Hd2b6HvS0ZXTctZSlCBBONGKC1C1yf9zc=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851529}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851529}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851529320, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}, "event": "message", "is_voice": false, "senderName": "Dulnith Liyanage", "correlationId": "5708a7c7-0738-4155-b20c-dfa0e4f1174f"}	2026-10-01 10:45:30.580011+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
5c29ccc0-65e7-42f7-8770-1bf43dea8306	94773552869	ඩිලිවරි ගාස්තු පහත පරිදි වේ:\n\n🔹 පලමු 1kg සදහා: 480/=\n🔹 වැඩි වන සෑම 1kg සදහාම: 140/=\n\nඋදාහරණයක් ලෙස 5kg පැකේජයක් සදහා 1,060/= වැය වේ. මෙය මුළු ලංකාවටම අදාල වේ.	outbound	text	{"correlationId": "5708a7c7-0738-4155-b20c-dfa0e4f1174f"}	2026-10-01 10:45:32.723252+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
ccb6ebab-c56a-4d51-8f5c-df4aca632f84	94773552869	Koheda oyagollo inne	inbound	text	{"raw": {"id": "evt_01m3vh3ygyc3r6y2ngp57hvbra", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AD9525A23DF000C4599", "ack": 2, "body": "Koheda oyagollo inne", "from": "156745469018156@lid", "_data": {"key": {"id": "3AD9525A23DF000C4599", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Koheda oyagollo inne", "messageContextInfo": {"messageSecret": "glx9rvLulN9BxJnrtvos9CKneLV5OC/T3JwzEQ+1lb4=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851545}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851545}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851545630, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}, "event": "message", "is_voice": false, "senderName": "Dulnith Liyanage", "correlationId": "30c15806-fc2b-415a-8687-f7d9a2a4e207"}	2026-10-01 10:45:46.770482+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
d30cd003-7297-4fde-aa49-217ee952c3ca	94773552869	Hello	inbound	text	{"raw": {"id": "evt_01m3vgzddm7468xkbghcxhvt9b", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AABBA3EEED97047EBBB", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3AABBA3EEED97047EBBB", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "iXrPNn2gzA6ujpdqF949cULV1L/LAKLWNghyy2Z6Boo=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851396}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851396}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851397044, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}, "event": "message", "is_voice": false, "senderName": "Dulnith Liyanage", "correlationId": "6320c6fe-377c-443d-9e80-109de62d244b"}	2026-10-01 10:43:18.357156+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
d4e730da-e6dc-4bd9-840c-a4291dcff838	94773552869	ඔව් කියන්න සර්\nමොනාද ඕනේ\n\nකරුණාකර ඔබට අවශ්‍ය භාණ්ඩයේ නම සහ ඔබගේ වාහනයේ මාදිලිය අපට එවන්න. ඔබට භාණ්ඩයේ නම හෝ වාහනයේ මාදිලිය ගැන විශ්වාසයක් නොමැති නම්, කරුණාකර භාණ්ඩයේ හෝ වාහනයේ ඡායාරූපයක් එවන්න.\n\nYes sir, tell me what you want.\n\nPlease send us the name of the product you need and the model of your vehicle. If you are not sure about the product name or the vehicle model, please send a photo of the product or the vehicle.\n\nஆம் ஐயா, சொல்லுங்கள்\nஉங்களுக்கு என்ன வேண்டும்\n\nஉங்களுக்கு தேவையான பொருளின் பெயரையும் உங்கள் வாகனத்தின் மாதிரியையும் எங்களுக்கு அனுப்பவும். பொருளின் பெயர் அல்லது வாகனத்தின் மாதிரி உங்களுக்குத் தெரியாவிட்டால், தயவுசெய்து பொருளின் அல்லது வாகனத்தின் புகைப்படத்தை அனுப்பவும்.\n	outbound	text	{"type": "welcome_message", "correlationId": "6320c6fe-377c-443d-9e80-109de62d244b"}	2026-10-01 10:43:19.65271+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
557581a7-b018-4ceb-b986-846bd81ec434	94773552869	Mudguard\nToyota Lexus	inbound	text	{"raw": {"id": "evt_01m3vgzy1hcyaa9qbtr1f0v525", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A81B92CEECB2EE533E9", "ack": 2, "body": "Mudguard\\nToyota Lexus", "from": "156745469018156@lid", "_data": {"key": {"id": "3A81B92CEECB2EE533E9", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Mudguard\\nToyota Lexus", "messageContextInfo": {"messageSecret": "wQJ1+wSNdP0jc6+HcDTj/QUC3MDe5xtdQRB5mTUuSMg=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851413}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851413}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851414065, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}, "event": "message", "is_voice": false, "senderName": "Dulnith Liyanage", "correlationId": "dc673c42-abcb-4a43-ad5a-35c716478a8d"}	2026-10-01 10:43:34.352711+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
2681d95d-68c3-487b-aac3-d42d5ce83752	94773552869	ඔබේ ඉල්ලීම අප වෙත ලැබුණා. අපගේ කණ්ඩායම මෙය පරීක්ෂා කර එම භාණ්ඩය තිබේදැයි ඉක්මනින්ම ඔබට දන්වනු ඇත.\n\nYour request has been submitted. Our team will review it and notify you about the availability of the product soon.	outbound	text	{"correlationId": "dc673c42-abcb-4a43-ad5a-35c716478a8d"}	2026-10-01 10:43:36.838618+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
6fc8a000-2e41-43fa-9dac-6c608aaa305b	94773552869	How long for delivery bosa	inbound	text	{"raw": {"id": "evt_01m3vh0b0tmjjshcmtq93121te", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A6510C867673378B414", "ack": 2, "body": "How long for delivery bosa", "from": "156745469018156@lid", "_data": {"key": {"id": "3A6510C867673378B414", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "How long for delivery bosa", "messageContextInfo": {"messageSecret": "Qn7evFPrcztsWfHVkPweocUrgv3cN2ZDDgG6J538x0E=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851427}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851427}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851427354, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}, "event": "message", "is_voice": false, "senderName": "Dulnith Liyanage", "correlationId": "d309d6db-25c3-444d-bf53-af0890dc6221"}	2026-10-01 10:43:47.642835+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.products (id, name, description, price, product_type, variations, images, is_active, created_at, updated_at, user_id, delivery_price, video_url) FROM stdin;
\.


--
-- Data for Name: faqs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.faqs (id, question, answer, product_id, is_active, created_at, updated_at, user_id, is_tracked, media_urls) FROM stdin;
a005a03d-d96a-411a-9b3c-d6b32db30d8a	How long does delivery take and what is the cutoff time? (කොච්චර වෙලාවකින් ඩිලිවරි වෙනවද? කීයට කලින්ද order කරන්න ඕනෙ?)	ඔව් සර් ලන්කාව වටේම පැය 16ක් ඇතුලත Deliver කරල දෙන්න පුලුවන් අපිට. සෙනසුරාදා ඉරිදා හා පෝය දින හැර සතියේ ඕනම දවසක හවස 5 වන තෙක් orders දාන්න පුලුවන්	\N	t	2026-09-28 17:29:43.492502+00	2026-09-28 17:33:32.699918+00	05bea8cb-2e17-4593-9004-b8abacc7ee58	f	{}
\.


--
-- Data for Name: faq_usage_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.faq_usage_logs (id, faq_id, user_id, phone_number, sender_name, created_at) FROM stdin;
\.


--
-- Data for Name: fcm_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.fcm_tokens (id, user_id, device_token, device_name, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: leads; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.leads (id, user_id, phone_number, customer_name, assigned_to, status, created_at, updated_at, product_name, vehicle_model) FROM stdin;
42c39bdf-169c-4df5-840c-8378b94b36a4	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	\N	new	2026-10-01 10:43:36.816965+00	2026-10-01 10:43:36.816965+00	Mudguard	Toyota Lexus
\.


--
-- Data for Name: message_queue; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.message_queue (id, wsender_message_id, user_id, phone_number, sender_name, message_text, message_type, session_api_key, raw_payload, status, attempts, max_attempts, error_message, created_at, updated_at, processed_at, correlation_id) FROM stdin;
83155e85-cabc-4a49-8ebd-3bef7d4d8359	false_156745469018156@lid_3A699BD0D03BE655BEFE	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Delivery	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vg59zxt8r9823wtxmxvjwg", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A699BD0D03BE655BEFE", "ack": 2, "body": "Delivery", "from": "156745469018156@lid", "_data": {"key": {"id": "3A699BD0D03BE655BEFE", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Delivery", "messageContextInfo": {"messageSecret": "8hqjXNsb19DuDzsNSKCwCa23Q4dcyS2CJ5NaWuU5UF8=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850541}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850541}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850541565, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:29:01.74034+00	2026-10-01 10:29:05.459008+00	2026-10-01 10:29:05.455+00	aa059588-fc20-4f88-9439-fc1cb4de1da8
0c550c64-258b-4050-ae58-5e169dfcdd55	false_156745469018156@lid_3A05D703F3D81080A6FA	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3ptr7rycwmg3t6msnqyc9v9", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A05D703F3D81080A6FA", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3A05D703F3D81080A6FA", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "K5CHmGd8M42IAgDfdQlqQE3mdZM2Bam6cPTUUBEZe54=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790693875}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790693875}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790693875486, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 14:57:56.128588+00	2026-09-29 14:57:57.694964+00	2026-09-29 14:57:57.692+00	0d8d626f-67c5-417b-805c-9776188192c2
992633fd-f9be-42e3-9117-b58f441a9cd9	false_156745469018156@lid_3A56F15018F85D65F06E	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Location	text	u_05bea8cb2e1745939004	{"id": "evt_01m3ptrkq4hf2mta0t9rfper5w", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A56F15018F85D65F06E", "ack": 2, "body": "Location", "from": "156745469018156@lid", "_data": {"key": {"id": "3A56F15018F85D65F06E", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Location", "messageContextInfo": {"messageSecret": "fKJ9HdSVvufZ2saRh0PU5cBugRRNmckgdLBGIoFlJOo=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790693887}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790693887}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790693887716, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	dead	3	3	AI processing failed	2026-09-29 14:58:08.152482+00	2026-09-29 14:58:08.414232+00	\N	27909996-7278-4615-8b21-c8fd4442f075
ce53b2be-ab55-43f6-ad34-524d64a27809	false_156745469018156@lid_3A2998FECED3C1B2B91C	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Delivery	text	u_05bea8cb2e1745939004	{"id": "evt_01m3ptryvzj39ax4z6egyr6p6b", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A2998FECED3C1B2B91C", "ack": 2, "body": "Delivery", "from": "156745469018156@lid", "_data": {"key": {"id": "3A2998FECED3C1B2B91C", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Delivery", "messageContextInfo": {"messageSecret": "Ta/C4+URuw4BGT5h6rMnCvw40rxIZl3no43XMM8lenw=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790693899}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790693899}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790693899135, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	dead	3	3	AI processing failed	2026-09-29 14:58:19.463696+00	2026-09-29 14:58:19.605797+00	\N	a61ac4f9-a44a-4d1f-82fc-c23204fb9e21
c1be0903-5e72-40f9-bcfc-ab825b7103e3	false_156745469018156@lid_3A15F154F6583521E690	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Link to website?	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vg7gg79gvd8cxnxyffkm4s", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A15F154F6583521E690", "ack": 2, "body": "Link to website?", "from": "156745469018156@lid", "_data": {"key": {"id": "3A15F154F6583521E690", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Link to website?", "messageContextInfo": {"messageSecret": "ItcYJUbxHzlLfcA03sISZGxgakrtz/0q0+QFJEM3tXk=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850613}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850613}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850613767, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:30:14.998965+00	2026-10-01 10:30:20.28502+00	2026-10-01 10:30:20.282+00	8e0df89c-7018-41de-b60f-fbc9c8f42d23
e667dd2a-fd49-4aaf-9979-586927132cfe	false_156745469018156@lid_3A06A39058162A7FD8D1	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3ptsevrszbamhw2xba8fb3p", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A06A39058162A7FD8D1", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3A06A39058162A7FD8D1", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "Q/UO+6gFadDHrh69tNj73pHdmXRDPmrXQU39yiyqrX0=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790693915}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790693915}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790693915512, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	dead	3	3	AI processing failed	2026-09-29 14:58:35.780119+00	2026-09-29 14:58:35.980612+00	\N	8472ab4c-fde1-4bc2-9484-aa94408c94d0
3e87a099-5889-4b1c-b7ea-8f7b9c0737c2	false_156745469018156@lid_3AFED4CB7CE021DEABEC	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3pttdn0g6sbj6m04nh1be4z", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AFED4CB7CE021DEABEC", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3AFED4CB7CE021DEABEC", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "/DO2r8z4vjzluELrsCvW7CTLceZwd6PZzuOJgnKrgxI=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790693946}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790693946}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790693947041, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 14:59:07.359504+00	2026-09-29 14:59:07.591984+00	2026-09-29 14:59:07.59+00	6f3b3fb5-6447-4089-b595-9539d616dcac
021d4134-9e98-44cd-810b-51509f7194fc	false_156745469018156@lid_3A2EB954839B9C78B0BE	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Delivery	text	u_05bea8cb2e1745939004	{"id": "evt_01m3pttnjhmrz62042ec0cvfsj", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A2EB954839B9C78B0BE", "ack": 2, "body": "Delivery", "from": "156745469018156@lid", "_data": {"key": {"id": "3A2EB954839B9C78B0BE", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Delivery", "messageContextInfo": {"messageSecret": "vPH3t9Am7Oc+ItMFcK0376C7eR7RH91CwpPqYTYDjoE=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790693955}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790693955}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790693955153, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	dead	3	3	AI processing failed	2026-09-29 14:59:15.399794+00	2026-09-29 14:59:15.518595+00	\N	ab608b0b-b14d-4c51-acfb-a2e0fee9e7c0
2a18c61c-5c69-499e-8a51-b1f766738b04	false_156745469018156@lid_3A19E208763FB7E533E8	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Location?	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vg4yyt063fxmyn8rb8j5k2", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A19E208763FB7E533E8", "ack": 2, "body": "Location?", "from": "156745469018156@lid", "_data": {"key": {"id": "3A19E208763FB7E533E8", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Location?", "messageContextInfo": {"messageSecret": "POltbLXkVQDc90DbAXXFw/zRQvgQqKKjTB4blEFctZ0=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850530}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850530}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850530266, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:28:50.892828+00	2026-10-01 10:28:55.103785+00	2026-10-01 10:28:55.101+00	dbbbdc24-5ca4-4798-998d-c49a605e89db
e3ad1464-639e-464e-9859-06dbcf70ff38	false_156745469018156@lid_3A321E7BCA1E177A927A	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3ptz8wjt3d1a8tfedgcf34f", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A321E7BCA1E177A927A", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3A321E7BCA1E177A927A", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "ouH5jzMWsrWqM3j+JAKaHviump5xxKNbpCZ+9kupmbA=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694105}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790694105}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694106002, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:01:47.044554+00	2026-09-29 15:01:47.851495+00	2026-09-29 15:01:47.849+00	d3b1f0a4-d6cd-401e-982d-d53648800c43
e4bcafff-b313-428c-a92e-5179545c0d04	false_156745469018156@lid_3AB8E03FA0A1F3279A14	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Delivery	text	u_05bea8cb2e1745939004	{"id": "evt_01m3ptzed4gwtxxm46jxf38fzr", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AB8E03FA0A1F3279A14", "ack": 2, "body": "Delivery", "from": "156745469018156@lid", "_data": {"key": {"id": "3AB8E03FA0A1F3279A14", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Delivery", "messageContextInfo": {"messageSecret": "7sL1knhgloK/bsfZOmieg4NGJEEziIl1KtSIi1GMA+M=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694111}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790694111}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694111653, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:01:51.971905+00	2026-09-29 15:01:55.982658+00	2026-09-29 15:01:55.98+00	815e65e3-d9ab-4ee5-b7bf-18eaf9fd41c7
76ef7d54-7d52-4541-9ee9-5151483ddd2c	false_156745469018156@lid_3AD290586404CB4A6E48	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Location	text	u_05bea8cb2e1745939004	{"id": "evt_01m3pv06vpqp16v8w8dtag9tgf", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AD290586404CB4A6E48", "ack": 2, "body": "Location", "from": "156745469018156@lid", "_data": {"key": {"id": "3AD290586404CB4A6E48", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Location", "messageContextInfo": {"messageSecret": "eqH9NLmUep+FonLosMPjZQzlmaZuufHMHDReDY5QipE=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694136}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790694136}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694136694, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:02:17.213219+00	2026-09-29 15:02:21.503182+00	2026-09-29 15:02:21.499+00	1d758125-0881-4d56-b6c2-0cf05d99bbbf
88d3007e-aaca-471f-9e8c-15e71c305f82	false_156745469018156@lid_3A43C0598459022CACCC	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Spare parts	text	u_05bea8cb2e1745939004	{"id": "evt_01m3pv1kwbjncc1q6xwbtms5ev", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A43C0598459022CACCC", "ack": 2, "body": "Spare parts", "from": "156745469018156@lid", "_data": {"key": {"id": "3A43C0598459022CACCC", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Spare parts", "messageContextInfo": {"messageSecret": "6vjaZFxkP4IovtZJBA6fUcGkev7SFxE3rHsJsAhROmg=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694182}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790694182}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694182795, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:03:03.272739+00	2026-09-29 15:03:07.876256+00	2026-09-29 15:03:07.874+00	c98fb840-f180-4003-a373-fbf194d41988
4cc973c6-2f7a-49d6-95f3-3e0389dd468d	false_156745469018156@lid_3A3A23081CD16D070919	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Steering wheel	text	u_05bea8cb2e1745939004	{"id": "evt_01m3pv24ea71xp2zqsg98pz0ny", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A3A23081CD16D070919", "ack": 2, "body": "Steering wheel", "from": "156745469018156@lid", "_data": {"key": {"id": "3A3A23081CD16D070919", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Steering wheel", "messageContextInfo": {"messageSecret": "8csc+uneQW77EtaY6QmqQG+wsHYQhVz/8W2ao2FqOYU=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694199}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790694199}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694199754, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:03:20.348081+00	2026-09-29 15:03:22.881812+00	2026-09-29 15:03:22.88+00	4660d02e-01cc-460c-8608-81cc33f7c4ee
059044ef-d679-48a9-8306-418c6b286e7c	false_156745469018156@lid_3AEAABDAF85DB56B2A10	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Honda civic	text	u_05bea8cb2e1745939004	{"id": "evt_01m3pv2xa0wtpt2x1d4m9mhze8", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AEAABDAF85DB56B2A10", "ack": 2, "body": "Honda civic", "from": "156745469018156@lid", "_data": {"key": {"id": "3AEAABDAF85DB56B2A10", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Honda civic", "messageContextInfo": {"messageSecret": "UO913tXtxqmCh+mI+ahVvtTTH8kMAfPskutiE/FUe/Q=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694225}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790694225}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694225216, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:03:45.564823+00	2026-09-29 15:03:49.416765+00	2026-09-29 15:03:49.413+00	6b3335de-5c1d-4288-9362-6bcced788202
f7ae80da-43b4-4bd7-bd73-f9129a967f61	false_156745469018156@lid_3A86B66C712537F9740A	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vgdrp24w47rq37gkj5qjy1", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A86B66C712537F9740A", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3A86B66C712537F9740A", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "rCoLOoWgyueciJ7jaZB3t/u5USX+DL+Gg3vgMsvuGlg=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850818}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850818}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850818754, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:33:40.058191+00	2026-10-01 10:33:41.514701+00	2026-10-01 10:33:41.513+00	bccc6846-a9ec-4c34-8c0e-80e07f00c2dc
543e1baa-4474-4b7c-aa8a-f2b7a2e33e05	false_156745469018156@lid_3AF0D4A3D9AAB29FDA4D	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage		image	u_05bea8cb2e1745939004	{"id": "evt_01m3pv3gfepqhzzr6r3beqpj77", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AF0D4A3D9AAB29FDA4D", "ack": 2, "body": null, "from": "156745469018156@lid", "_data": {"key": {"id": "3AF0D4A3D9AAB29FDA4D", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"imageMessage": {"url": "https://mmg.whatsapp.net/o1/v/t24/f2/m232/AQPIj40ihsII7MrL8y0RKJckvGSA5ysWbQuImlwbGPLyXSHzNzqel9zXoh3XI4dje2JgvXwtsEVjFcv1yLoIbwe8fs5ZFnei8HIVHgoo-g?ccb=9-4&oh=01_Q5Aa5gFKt_vDCoJ0h2Gum4QaHzjpvjm-43NpQAioAfgPGqNhUA&oe=6AE32F9E&_nc_sid=e6ed6c&mms3=true", "width": 1600, "height": 1600, "mediaKey": "fGNElscajebIKpogtB0YGvTWZAKVCUSFy0lhKhrX0Mg=", "mimetype": "image/jpeg", "directPath": "/o1/v/t24/f2/m232/AQPIj40ihsII7MrL8y0RKJckvGSA5ysWbQuImlwbGPLyXSHzNzqel9zXoh3XI4dje2JgvXwtsEVjFcv1yLoIbwe8fs5ZFnei8HIVHgoo-g?ccb=9-4&oh=01_Q5Aa5gFKt_vDCoJ0h2Gum4QaHzjpvjm-43NpQAioAfgPGqNhUA&oe=6AE32F9E&_nc_sid=e6ed6c", "fileLength": "105792", "fileSha256": "D8V40kEjLgRiXwZlbTDY+l9ZZpU2Q7BDa5D176s+dCM=", "contextInfo": {"statusSourceType": "IMAGE"}, "scanLengths": [20404, 41247, 14819, 29320], "scansSidecar": "9AnstHUlxjifPh96VnVgb5yYn1oj/IbBiQrNVBCRgyKgSHOO2iMFJg==", "fileEncSha256": "xg9wmDZzlA8NwZTNhSAdH2jeFqWRyiZ+nWZM0igVMZg=", "jpegThumbnail": "/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAQFBQkGCQkJCQkKCAkICgsLCgoLCwwKCwoLCgwMDAwNDQwMDAwMDw4PDAwNDw8PDw0OERERDhEQEBETERMREQ0BBAQECAYIBwgIBwgGCAYICAgHBwgICQcHBwcHCQoJCAgICAkKCQgIBggICQkJCgoJCQoICQgKCgoKCg4QDg4Od//CABEIAEgASAMBIgACEQEDEQH/xABgAAABBQEBAQEAAAAAAAAAAAAHAwQFBggAAgEJEAABAgQCBgUHCAgHAAAAAAACAQMABBESBSEGIjEyQVETFEJhcQcVUoGEkaEIRWKSscHE0SMkM0NTotLhVIKFssLD8P/aAAwDAQACAAMAAAAAkZuo3+EkGnoj1ZZLzOjy7sHYZoeuvnrzmGzGgLgvPFuYW6hmjSyyMcCZJmd44HRr5lqE6fnh+h9ekosIncEArPJzDR3Ap70PDZl1BluXZkWArUJMwlw3pgrSFdmzCJa3ZAHnyaryMMbdKSQZJDV+2HV3+RiiVwnaZIrt0rwMyYCs6yiLHjdogTRJv5X1kGu7g5VPF01rfnKIdMXcAc+//9oACAECAAE/ADcv1SRCGCdKnCHrnO1+UFjBNaihcQ9qv3c48sM6cx5suolvW6U7+r/lDJLEuwrvGiJHm9OaxjMujStknar8I8qa183e1f8ARHHh6ow5d71QRxiUuL/RhXdqurHlflEY82UVVu63t7ur/nFufLOGDUM0hx1w+1an0YlpdES7iUeXAaeafbfw0TjoNIrnR3Zjq3U3iROUIzki1290OPo2m5X/AN4QrdY8uXzR7b+Gj//aAAgBAwABPwAmtVO6AaTksAiBwr6s4GQE9a61F4R8oCXFrzLSufX617uqwSItIfcRvhVVjrnCieHGJF6+5OX3x8oj5k/1D8JDG7xzWJ9N1fGAZK6uX2/0xKOK2hFzyzj5QL/SeZdmXX9nf1WEXJPCHwQ9sA0A8Ll74mHlrTgMeXZa+Z/bvw0XGIJrV4bM0qkdar2fj/aAFTXepHSd0eXT5o9u/DR//9oACAEBAAE/AMawdnFcWnJgZlAljITqAXnrCNdUrKa1YY00d0dHqDTAudDuOO3FeJZiVo2jshzTzF5wdVzoAX+GItJ7xz/miRlXpkldnSeVuy/tJfdu66pb38Yl8IkKN/pSIzrWq2AP0Vol3rrDMmw0lrbYWrlklbvXGluAO4U4RWr0Brql6FeyX3QzhU7PfsJZ1xOaCtv1loPxhnyfYg9m6rUun0ivL3BVPjGAtOtNOE9kUwgm2PFWwVRUk7rljDDlDMOuMA8g6oOKlSbr/uHuX1Q45hbC1Rhpz0VcGvhQF1U90TrrDt5C8aVSoh2a8qR0vfGCYqw1YExWgFqr9y+uHFSYdc3XGyRCTtCucGlIdSNMgKWfwomRQVqbFvZUCs1fCHVQCW1ckXKCmCLisHMIG8VIcxiXb3ngT/MkHpPJh++H1VX7I0e00YWZBkXai4SCorVNvFK8ocCHRjS5i/qrm3oZi73gf9oM7omHuhEiXYKKvujEMadnHCMiW2uqNckSGG35taMsuvKtdwCPZt2JwiZU2DIHEJswWhCWSivJUhl05d4M6GBgqUhg+mZZc/iNAX1hRYdGNJZEurOGqUEVFfXVEhRpGJpcy6nMC+xY6TKJR1h1m2UdnEBi5VB98mxdMiHUbblgJdZBUC195RWMWlHivTq7EqjVXFM3LHXBpT9+8ThbuSCNbomy/WxT6TX/ABjDcck2pOWFx9BMGQEkoWSolOUO6SSH+IT6p/0xp/Otg23LNlVVW9zupuiv2+6FOqrEzrVTmlIVw5V1bcjaMkTJFoqVTYVUiYxWafqjs04SLSooS2rbs1UtHLwglTx8Y0ew17E5pstZWwMTdcXZQOFea7IMkUBpyh4onZkrREiuJE1izW4l3iqSktVXmsK9xhx2qxpBo1MlMuPSzavNvFfqqlQIt5FRV55osSOgs3MazxBLj9c/cmXxiV0Tw2Q1nf1g09Na/wAqUH31huYRwhl5ZtARfRSlE4rlsSH1RkbUXdyrEy/3xiEwomQlkQqqL4x1itUgppIOet2LDuKLTfX3wj5vrktE9JYkdJ5TCwMAtddvo6fa4atfR7k47YbxpjEEXo1oXoxNZxjGjpz/AOmliRHO0BrS+mSLXgUYNoPM2uvzxNy7Tbb2oq3ka9EVpVGoiiLQucTKkq6pIorsh5ejEiNy0RRVX1RiGLE8NENbe7LKBnHKW9IdvK5aQw9RKRKzZMkJAtFSGp3rDaEu2n5R//4AAwD/2Q==", "firstScanLength": 20404, "imageSourceType": "USER_IMAGE", "firstScanSidecar": "9AnstHUlxjifPg==", "mediaKeyTimestamp": "1790694242", "midQualityFileSha256": "0x/5ZruM3FlpXhQ9KSrxMgmFuuSwUsyUwcbqmENLJNY="}, "messageContextInfo": {"messageSecret": "P87h30w7WwVjbyzyRZmXflfoAwfYipXixc5Qn19C7Ks=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694244}, "media": {"url": "https://waha.buildstart.io/api/files/u_05bea8cb2e1745939004/3AF0D4A3D9AAB29FDA4D.jpeg", "filename": null, "mimetype": "image/jpeg"}, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": true, "location": null, "timestamp": 1790694244}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694244846, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:04:05.223787+00	2026-09-29 15:04:05.287824+00	2026-09-29 15:04:05.287+00	41685ff0-b77b-4dfe-a210-1947450b5d11
d03b9899-aeba-4efe-9458-3629309cef69	false_156745469018156@lid_3A0B3B2DD3E928FDC995	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	What courier are you using	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vg65rtgh9hekbs47vm3xn4", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A0B3B2DD3E928FDC995", "ack": 2, "body": "What courier are you using", "from": "156745469018156@lid", "_data": {"key": {"id": "3A0B3B2DD3E928FDC995", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "What courier are you using", "messageContextInfo": {"messageSecret": "Pdml6VmRyrS/t2pJaiVHY0JGi+wAoRj4DF0TYc37BDg=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850569}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850569}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850570010, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:29:30.240817+00	2026-10-01 10:29:32.710636+00	2026-10-01 10:29:32.706+00	7f810153-a6d2-4e59-be99-9b3623defc5e
ec830504-e0eb-4fde-a14d-e8025a375d54	false_156745469018156@lid_3A14FC3EC66B76F13944	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Meka thama	text	u_05bea8cb2e1745939004	{"id": "evt_01m3pv3vp45nv8a1w114s4xbp1", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1790792999, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1788201000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A14FC3EC66B76F13944", "ack": 2, "body": "Meka thama", "from": "156745469018156@lid", "_data": {"key": {"id": "3A14FC3EC66B76F13944", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Meka thama", "messageContextInfo": {"messageSecret": "4R4Ib/vk2bh1fZ7lDaY8BgNCTnv2/RdK83KXm9Cg7Hs=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "PhM/Fcv+VzEH6g==", "recipientTimestamp": "1790693848"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790694256}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790694256}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790694256324, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-09-29 15:04:17.242103+00	2026-09-29 15:04:20.01131+00	2026-09-29 15:04:20.01+00	d123fafa-0e42-46b7-b037-3a55c019a410
486971da-2f51-4c56-9320-d4cba318b1cc	false_156745469018156@lid_3A31E3A3C5A2F4BDF913	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vf8qecxc991xarg0re2eqr", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A31E3A3C5A2F4BDF913", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3A31E3A3C5A2F4BDF913", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "ghGzxpLGvk2w0LCTo1f2JmmKMRYPif8xN045AupKkrs=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790849604}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790849604}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790849605068, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:13:27.182074+00	2026-10-01 10:13:29.765173+00	2026-10-01 10:13:29.764+00	4f8b4095-8dc7-400e-89c1-455f23d2bc65
845a4653-956b-4166-b83d-3cf5655c54bf	false_156745469018156@lid_3A6652E2B7B289FD2EBA	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Product Name: Steering Wheel\nVehicle: Hyundai Tuscon	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vfahefbd7ybk1t47wtxcd1", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A6652E2B7B289FD2EBA", "ack": 2, "body": "Product Name: Steering Wheel\\nVehicle: Hyundai Tuscon", "from": "156745469018156@lid", "_data": {"key": {"id": "3A6652E2B7B289FD2EBA", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Product Name: Steering Wheel\\nVehicle: Hyundai Tuscon", "messageContextInfo": {"messageSecret": "SH59Fy87yL9O4szwd26UVEWzcd63f+Wb5JFNhf2HbrA=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790849664}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790849664}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790849664463, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:14:25.570995+00	2026-10-01 10:14:29.974024+00	2026-10-01 10:14:29.973+00	fde434db-970a-44e8-aea4-de7de1753a40
37e0af4d-fc8e-42dc-b1bc-82b4aa1026c0	false_156745469018156@lid_3A146AB1F2BE3D97FC3B	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage		image	u_05bea8cb2e1745939004	{"id": "evt_01m3vfc51qk8gy4z2setcak2cr", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A146AB1F2BE3D97FC3B", "ack": 2, "body": null, "from": "156745469018156@lid", "_data": {"key": {"id": "3A146AB1F2BE3D97FC3B", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"imageMessage": {"url": "https://mmg.whatsapp.net/o1/v/t24/f2/m238/AQMPiHCioszKxHBz6kZQ6WAP7LiVV-Omvfjyi9uAF7nDbq5mKMMZKZ7P0nLhLFCa0NsqqKfDH504oQoS2xiMcmZkE1PShL-HpoZq3om7Jg?ccb=9-4&oh=01_Q5Aa5gEVS-gvZDMaGvAOlrdpJ_PUb5Aprmt8L42jb8pUTRjDMg&oe=6AE5BAC7&_nc_sid=e6ed6c&mms3=true", "width": 1200, "height": 1600, "mediaKey": "thkbzs1y4imtjs3AumLEstDe9WCNKnRGTKpsUjFn6F0=", "mimetype": "image/jpeg", "directPath": "/o1/v/t24/f2/m238/AQMPiHCioszKxHBz6kZQ6WAP7LiVV-Omvfjyi9uAF7nDbq5mKMMZKZ7P0nLhLFCa0NsqqKfDH504oQoS2xiMcmZkE1PShL-HpoZq3om7Jg?ccb=9-4&oh=01_Q5Aa5gEVS-gvZDMaGvAOlrdpJ_PUb5Aprmt8L42jb8pUTRjDMg&oe=6AE5BAC7&_nc_sid=e6ed6c", "fileLength": "519747", "fileSha256": "aKrbS9byImUgftg3d0v4sfb1YWxNYLH/8uY05qk6uWY=", "contextInfo": {"statusSourceType": "IMAGE"}, "scanLengths": [28119, 256747, 111973, 122906], "scansSidecar": "PZB0FVSgwbNYyJqkfU9wMQvEI5mtbsfsc+CfaqqeHoLOdXf6dZtjew==", "fileEncSha256": "w0sHtx5XZHb497V9HUFS05wUfwzxYMZBJaxzJERCS0o=", "jpegThumbnail": "/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAQFBQkGCQkJCQkKCAkICgsLCgoLCwwKCwoLCgwMDAwNDQwMDAwMDw4PDAwNDw8PDw0OERERDhEQEBETERMREQ0BBAQECAYIBwgIBwgGCAYICAgHBwgICQcHBwcHCQoJCAgICAkKCQgIBggICQkJCgoJCQoICQgKCgoKCg4QDg4Od//CABEIAEgASAMBIgACEQEDEQH/xABmAAACAgMBAQAAAAAAAAAAAAAGBwUIAAMEAgEQAAECBAMCCgILDQkAAAAAAAIBAwAEERIFEyEiMQYHFCMyQUJRYXJxkQgVJDNSU2KBgqHwEDVGhJKisbLBwsPE4URFdIWTs9HS8f/aAAwDAQACAAMAAAAAeUGBDf3C+vJwGc+2046k92rW5hOK8RpATcsvEV+RoMw1yG2hZxPk/G8+/wBE2118/JWPVYStfjscsb1ctc1MWCC2CbINtyJ8lgvH204KARWyFN4DVHa5Fn9gQb15TytEmWD2Bds0KGIx89eiQ5XWrfybumW6uUTdaHfCEQIivXhlhXwIRrBzk2oaab+fPtfT5iZokq/WBzEGgP/aAAgBAgABPwC+HdqPphtdGMUa2PKUcbCfe78a/gfcc/akHYT1FDVvUTibZuu8Rjja/u78b/gRnlGasZ3zQ4cccbdjmH+PKl/2PuFs+oYFy9TFNFH7ftgOj5V/WjjqT71L/jP5eOR/L3fJ/rEzKWj0ulGXExMZFNLrtI44JrO9rNm2zlfX38nj/9oACAEDAAE/AACv1wAaeYYvVeyRoPTIEUkEvMnR644NzaK9bd742uz4j9lj2T34P+Htn/JR/WAXT6KwjT+S5lzCAD7igbdutBGta74wZ5WXArTmlStO1ur649k5+D/+ZfycNtJr5ihsNjxVFhySMzLmsu3W6/VxF66DuiQZy1NLbfnrHsin81ng4vWPtkK+keRfsosM9vzr+yJfUfpH9RLDjGWrLi7QuIQ6L176L47KwujnnH6w/oscfp7OCj8FcQX8rkn/AFgH7btnpFXfDD9lVtrapFT0rWkOnW3z6eHf690SWG8sVdvKylEkW27fXxHq0j2R2G8k9ouczM32x7NtLeSfKWvSj//aAAgBAQABPwCZ4w5Nu02ZOZcu6ztCv1lD3GO8RDl4c1VVol5n+7vjEeG85isxM4U/yMAmJKZ5tsHheFwGTcFbi2bSttX0xh+I8neG+tjwEC0UtzgbtDa8O1HAvgRITmBykxMSjSvmyRnc3t7Drva8RoPzRwN4GyuO4NKFNNgfPTNakQkPPL2m113Wa+mOB3FbguOYaMzMDNNuk/NBsP2jay+42GhAXZSMbw1jC52bk27jbljVtszJCJaCK6qiJrr3RhTaimu0nV8/2pE4422yxcYhtHvIR7WnXX1w9i8qCK4EwyWUSVXMGiKS6XKN1N3dDjqBjkm4hByiYtbErfc3OIQbXRNUtLqiYGWlXMl0XqybpCZBQtps6aXdUY2WIctk2pLEJhRfMW8ltXWMoRMWxErrK18tEjFXeFHBza5VMSMlmi2AtvAQfkD5SXdHBbjcmsDZbw8cObmABx0s0zcvq6ZObh36l1QmNljU/iD5tC2SzNytptWXAKb9+8F6uuGCog0HZ36bqeK/bfGPYS3PYpg7UzMZTOKZbV1ujdjygSrd5vRHGXwDwrAMCfm5Ksi+0TQjzzjnKMwguBRNdk+kWxb0ejGI5Ye1M0wd7bYMqhEu0lllw+kSEkjh6wspiGICOguPI6PlmEBz96MCF1z3SJCb8u4htZtSS4XAp8qnzxi+OTmKhyacZlhFs0cq0jnSoqa3kVN8Xt5oOu5RvhclXQmrrejvauBdnwjAsQy8ZmR2CSYvpvtvTb7dF74eec0vQbadn/yOGWCPzzco8ArRts20qttq33Io3aeqsTktieKCw1Ozb82ksvM5zxuIA+TaFfTvguBk6/JA0Mu/SXTMq3Lm5ptaAI7+l3xxlI4M40Lgk27yLD0dAtk0PJbuvHWh96RxfzcvKldOPMstGjyJnKAgRXsU6elaXRwdSVmCnjb5O6JTjuWQo2SK3lS3RtTo3XRwjk22cQk3WZVp1/NlxsyyIXAJXlIcsaXVt+DHCqaeY4QOuHLDIq242QttjYhAI6O2rbq4EEq27Cq7pft92/8ARrExxgYCxLMkzIPZKc2Iqyw44Vidopg3C3euJjjdbYT3Hhih3XONs/VLNh+tGO8Z2Pyy2MOsymY2BqrQOGa1+XM7X5sPT0ziRC/NvHMPOOJc44VSXbT6o4u+A2GY7hDcxMuOZpvuhaLjdtoFottqxPcFGdpzNCxt4gFtPfUG9R79+kYHNGk9LMs6FysWxK82rCu2NpK0jhvhM3JY5MtTj3KHRyiuvI+acCrYXHauyOzGBziTEu1tohtVbKvS2d1fo0jF8VlXcNkgZaLmzcv50V2lX4F13z2jHLg3o1/xHCHESzmzCXERNgVFDEtfHaaa/e8yxh8046bb9jSZLl1MvYubK5Kp19VYkZ16emMhGZcSdG0FRHFoops/GuF6iJYLhZiMuRNONMrlEoENgtODb8uzMiQxflLbz4yhXy43kIukZLfoR3ZBCFvSRf0xLIs84887oswSkIkSukICiUG8tdIwV/KccbG3ngQx2qc4GhV8bafkxMyaphLXSIEmi+NsrQvkIz+cpeENSwUqQ6Jv9EcIGZceTE2GnJQ7Yb/oOOKn0rS+TEpPA0pNWEgpca6132jTd4RKT3JJhp0S6Biu8k0rrqKiW6u4kiZwRJ6YxVwHmZYZJrlBA6thOoYkSiAXvH2e0Rb0u1jgu4BTYtkgWTAEBX2URV1TV3YTzUWnUkOoTSuBbabK263b0WlYYmHGn23F6KEl3im4l+3dBy6jhNxNKhBNU6AfB+MzfzRa9JQVoHQapds7oxwzmG5A1LaSXQendsig00VoEHy1P0xLi4AzZg3mEbQ91oijg7Wvq+eOAuAYTjmFzDBovtj/AGhT99llquUTKfF/rLUSjhRg4g6y40TT9o5Rk0TRDe0tpe8gCDXu2i71jDHRkSacFecbUTSnSuFUrQk/SmscMeamb6ELc2KPCSg6gueVXedLxIt9dIdvcCvZ3en7JDrmfhfZu5V0vc43fzHq5uH2TQF6Kqqp1U3bvGkTMm6/JYUZNraTbm0Sv0ps7szmv9H6UYOcu3MuI8Y2cndb8LytsEU3KVdw+EOTDqPE8yRS5mJsETSkBKJ6EC296RJSkzM4aoNqbiYe6S2XOna050rQQMsBr0jUtd0ZToKupIoLr4f8awjPtjhQmdouSB2mQ5QqQF8IyczTLuoFBtWDm8paotKd/a0/TH///gADAP/Z", "firstScanLength": 28119, "imageSourceType": "USER_IMAGE", "firstScanSidecar": "PZB0FVSgwbNYyA==", "mediaKeyTimestamp": "1790849707", "midQualityFileSha256": "IMEP5F+blPbDWaQewf4VEKv13tPzvPaWUwio9633/II="}, "messageContextInfo": {"messageSecret": "7iLvkPpmMxwLrpQ+W63/V5kpMXirm26dA92ThAbbJbU=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790849716}, "media": {"url": "https://waha.buildstart.io/api/files/u_05bea8cb2e1745939004/3A146AB1F2BE3D97FC3B.jpeg", "filename": null, "mimetype": "image/jpeg"}, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": true, "location": null, "timestamp": 1790849716}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790849717303, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:15:18.512436+00	2026-10-01 10:15:18.604068+00	2026-10-01 10:15:18.603+00	440945e5-a91d-4179-8286-556f8000e383
016e28f3-f66d-443a-ae74-f07f24e97400	false_156745469018156@lid_3ADFF22752A7A66B0A7C	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Meka thama	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vfcrcbb67ghgtpd7bbhden", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3ADFF22752A7A66B0A7C", "ack": 2, "body": "Meka thama", "from": "156745469018156@lid", "_data": {"key": {"id": "3ADFF22752A7A66B0A7C", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Meka thama", "messageContextInfo": {"messageSecret": "z50faqtRbAIFdoGjQxbic1Tx8xJ0Md2EJwnL47eungg=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790849736}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790849736}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790849737099, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:15:37.75283+00	2026-10-01 10:15:42.5557+00	2026-10-01 10:15:42.552+00	18709f60-4dcd-443f-b3fe-caf76ecccabf
6a43f782-cc92-4e2b-b479-8657355c0019	false_156745469018156@lid_3AF1F1456D877C1C8A71	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vg1ztsnanv1k2r8cb7hftv", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AF1F1456D877C1C8A71", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3AF1F1456D877C1C8A71", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "coLY2RBy7wo30HoNZIF9EvZ76WC0wedD4zEM0vOlwpM=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850432}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850432}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850432857, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:27:13.741942+00	2026-10-01 10:27:15.373083+00	2026-10-01 10:27:15.371+00	6ce3a8bc-950b-4c6b-998a-7fd584118488
727535f7-be97-49d6-a1e0-693ab187429a	false_156745469018156@lid_3AF754B90C62559C1885	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Steering Wheel\nKia Sorento	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vg2rasa53vc94dabdms9zm", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AF754B90C62559C1885", "ack": 2, "body": "Steering Wheel\\nKia Sorento", "from": "156745469018156@lid", "_data": {"key": {"id": "3AF754B90C62559C1885", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Steering Wheel\\nKia Sorento", "messageContextInfo": {"messageSecret": "DWQE9WwEG34uJgDDq1ixWXh096frrA4r/ytk7+BspMY=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850457}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850457}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850457946, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:27:38.591957+00	2026-10-01 10:27:41.453342+00	2026-10-01 10:27:41.451+00	4e7ca3ba-367b-4d28-93dc-bf5d1135c6a9
d3571350-5ef1-44cc-90df-995c55322f57	false_156745469018156@lid_3A04506C7D89179FFEE1	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Steering Wheel\nKia Sorento	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vgeg00z8fhw7jhe4gct8dv", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A04506C7D89179FFEE1", "ack": 2, "body": "Steering Wheel\\nKia Sorento", "from": "156745469018156@lid", "_data": {"key": {"id": "3A04506C7D89179FFEE1", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Steering Wheel\\nKia Sorento", "messageContextInfo": {"messageSecret": "4d73S/phVMKvmRoRDFclaQrZXGZkBY1AeICj3uVH5aU=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850842}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850842}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850842624, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:34:02.84175+00	2026-10-01 10:34:05.716571+00	2026-10-01 10:34:05.713+00	8f35ead6-98b6-45f6-87c7-330baa9d2bea
8e254b74-428f-480a-a1a3-269fa4d3b35a	false_156745469018156@lid_3A00E1D0C85D08E17694	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	How long for delivery	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vgf44njcshw6nrkfct3q35", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A00E1D0C85D08E17694", "ack": 2, "body": "How long for delivery", "from": "156745469018156@lid", "_data": {"key": {"id": "3A00E1D0C85D08E17694", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "How long for delivery", "messageContextInfo": {"messageSecret": "LQ+LwNJvz78aNMcnMRiWswwga0o3QpUsQOoP9yw6/y0=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850863}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850863}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850863253, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:34:24.016898+00	2026-10-01 10:34:26.382185+00	2026-10-01 10:34:26.379+00	76de1986-f122-43a8-b248-1c6ae11e332c
3ea26bfa-045a-482c-9033-7c6e0d7ac57d	false_156745469018156@lid_3A1A09CA21D8D51E5537	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Mokenda deliver karanne	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vgfqg4hv2asxcj599056jh", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A1A09CA21D8D51E5537", "ack": 2, "body": "Mokenda deliver karanne", "from": "156745469018156@lid", "_data": {"key": {"id": "3A1A09CA21D8D51E5537", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Mokenda deliver karanne", "messageContextInfo": {"messageSecret": "6KSIsnNDDkk70nHBWL1X85gg8tO4s4ePmEre26UNTEw=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850882}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850882}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850883076, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:34:43.779503+00	2026-10-01 10:34:48.521216+00	2026-10-01 10:34:48.519+00	62ff5c50-b6c8-4ec5-8b2e-ceca3b4fc1d3
b96ad312-f20d-4d02-b25b-8e800052b869	false_156745469018156@lid_3A0C0193C2F84B265596	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Oyala koheda inne	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vgh0rkn0yxgzze5m150hxa", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A0C0193C2F84B265596", "ack": 2, "body": "Oyala koheda inne", "from": "156745469018156@lid", "_data": {"key": {"id": "3A0C0193C2F84B265596", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Oyala koheda inne", "messageContextInfo": {"messageSecret": "VgYcWgiQhVLnfcuVROuLZLt/S/93Ba+/yx4wP1WJaiE=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850925}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850925}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850925331, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:35:25.535641+00	2026-10-01 10:35:29.040884+00	2026-10-01 10:35:29.038+00	4f87329a-6095-4b99-8a94-1a9016476dc7
48bc5461-2165-4e5a-9f4a-f7b05bae772e	false_156745469018156@lid_3A6BE55870307982E619	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Delivery gana kohomada	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vghqba0jc3pd4zps7j0znr", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A6BE55870307982E619", "ack": 2, "body": "Delivery gana kohomada", "from": "156745469018156@lid", "_data": {"key": {"id": "3A6BE55870307982E619", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Delivery gana kohomada", "messageContextInfo": {"messageSecret": "GERvD5SIG6LmtZkeE81MprI8lgTow2GS3c2qm385dOs=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790850948}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790850948}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790850948458, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:35:49.142427+00	2026-10-01 10:35:51.5465+00	2026-10-01 10:35:51.543+00	77b9bff2-b6ed-4fd4-8614-aa287705aaef
82cf2fef-1011-464a-b8a2-f7be483c81dc	false_156745469018156@lid_3AABBA3EEED97047EBBB	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Hello	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vgzddm7468xkbghcxhvt9b", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AABBA3EEED97047EBBB", "ack": 2, "body": "Hello", "from": "156745469018156@lid", "_data": {"key": {"id": "3AABBA3EEED97047EBBB", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Hello", "messageContextInfo": {"messageSecret": "iXrPNn2gzA6ujpdqF949cULV1L/LAKLWNghyy2Z6Boo=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851396}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851396}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851397044, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:43:18.284232+00	2026-10-01 10:43:19.676601+00	2026-10-01 10:43:19.674+00	6320c6fe-377c-443d-9e80-109de62d244b
a839b285-5db1-4e50-8b0e-04de846234c2	false_156745469018156@lid_3A81B92CEECB2EE533E9	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Mudguard\nToyota Lexus	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vgzy1hcyaa9qbtr1f0v525", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A81B92CEECB2EE533E9", "ack": 2, "body": "Mudguard\\nToyota Lexus", "from": "156745469018156@lid", "_data": {"key": {"id": "3A81B92CEECB2EE533E9", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Mudguard\\nToyota Lexus", "messageContextInfo": {"messageSecret": "wQJ1+wSNdP0jc6+HcDTj/QUC3MDe5xtdQRB5mTUuSMg=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851413}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851413}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851414065, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:43:34.327843+00	2026-10-01 10:43:37.058561+00	2026-10-01 10:43:37.055+00	dc673c42-abcb-4a43-ad5a-35c716478a8d
19cf68de-5516-44e8-aa77-6114d6d36eb5	false_156745469018156@lid_3A6510C867673378B414	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	How long for delivery bosa	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vh0b0tmjjshcmtq93121te", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3A6510C867673378B414", "ack": 2, "body": "How long for delivery bosa", "from": "156745469018156@lid", "_data": {"key": {"id": "3A6510C867673378B414", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "How long for delivery bosa", "messageContextInfo": {"messageSecret": "Qn7evFPrcztsWfHVkPweocUrgv3cN2ZDDgG6J538x0E=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851427}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851427}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851427354, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:43:47.608194+00	2026-10-01 10:43:50.999472+00	2026-10-01 10:43:50.996+00	d309d6db-25c3-444d-bf53-af0890dc6221
5e207e44-0deb-4f3b-a2a3-29a72ba37af8	false_156745469018156@lid_3AB0FC4BA205D3A716CE	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Mokenda delivery karanne oyala	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vh131pts6s3ree0jfws68f", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AB0FC4BA205D3A716CE", "ack": 2, "body": "Mokenda delivery karanne oyala", "from": "156745469018156@lid", "_data": {"key": {"id": "3AB0FC4BA205D3A716CE", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Mokenda delivery karanne oyala", "messageContextInfo": {"messageSecret": "tkfC2Dj5LOzTL10SzTYFtBzuQvbMMHm/FwEl5WpkwHs=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851451}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851451}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851451958, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:44:12.885594+00	2026-10-01 10:44:16.650546+00	2026-10-01 10:44:16.649+00	523767d3-300e-4560-b879-eee55cc33820
5a6ab3bc-3935-44d8-8501-21c9ce3fb78f	false_156745469018156@lid_3ADF8A9212375477EF3C	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Gana keeyak yanawada delivery ekata	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vh3ek74e2aed764fhz1txh", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3ADF8A9212375477EF3C", "ack": 2, "body": "Gana keeyak yanawada delivery ekata", "from": "156745469018156@lid", "_data": {"key": {"id": "3ADF8A9212375477EF3C", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Gana keeyak yanawada delivery ekata", "messageContextInfo": {"messageSecret": "Sbo8YCp5r5Hd2b6HvS0ZXTctZSlCBBONGKC1C1yf9zc=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851529}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851529}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851529320, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:45:30.498376+00	2026-10-01 10:45:33.404561+00	2026-10-01 10:45:33.4+00	5708a7c7-0738-4155-b20c-dfa0e4f1174f
a9b8931e-559e-4e1e-beba-3515b2cc7043	false_156745469018156@lid_3AD9525A23DF000C4599	05bea8cb-2e17-4593-9004-b8abacc7ee58	94773552869	Dulnith Liyanage	Koheda oyagollo inne	text	u_05bea8cb2e1745939004	{"id": "evt_01m3vh3ygyc3r6y2ngp57hvbra", "me": {"id": "94774496321@c.us", "lid": "112705109246037@lid", "pushName": "BuildStart Dulnith", "messageCapping": {"cycleEnd": 1793471399, "mvStatus": "NOT_ELIGIBLE", "oteStatus": "NOT_ELIGIBLE", "usedQuota": 0, "cycleStart": 1790793000, "totalQuota": -1, "cappingStatus": "NONE"}, "reachoutTimelock": null}, "event": "message", "engine": "NOWEB", "payload": {"id": "false_156745469018156@lid_3AD9525A23DF000C4599", "ack": 2, "body": "Koheda oyagollo inne", "from": "156745469018156@lid", "_data": {"key": {"id": "3AD9525A23DF000C4599", "fromMe": false, "remoteJid": "156745469018156@lid", "participant": "", "remoteJidAlt": "94773552869@s.whatsapp.net", "addressingMode": "lid"}, "status": 3, "message": {"conversation": "Koheda oyagollo inne", "messageContextInfo": {"messageSecret": "glx9rvLulN9BxJnrtvos9CKneLV5OC/T3JwzEQ+1lb4=", "deviceListMetadata": {"senderKeyHash": "mqtlU70vWwhEGw==", "senderTimestamp": "1790215602", "recipientKeyHash": "fsqSqbuGr36nng==", "recipientTimestamp": "1790849561"}, "deviceListMetadataVersion": 2}}, "pushName": "Dulnith Liyanage", "broadcast": false, "messageTimestamp": 1790851545}, "media": null, "fromMe": false, "source": "app", "vCards": null, "ackName": "DEVICE", "replyTo": null, "hasMedia": false, "location": null, "timestamp": 1790851545}, "session": "u_05bea8cb2e1745939004", "timestamp": 1790851545630, "environment": {"tier": "CORE", "engine": "NOWEB", "worker": {"id": null}, "browser": null, "version": "2026.8.1", "platform": "linux/x64"}}	done	1	3	\N	2026-10-01 10:45:46.661132+00	2026-10-01 10:45:51.381058+00	2026-10-01 10:45:51.379+00	30c15806-fc2b-415a-8687-f7d9a2a4e207
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.orders (id, customer_name, customer_phone, customer_address, order_items, special_instructions, payment_method, status, total_amount, created_at, updated_at, user_id, whatsapp_phone, district) FROM stdin;
\.


--
-- Data for Name: platform_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.platform_settings (id, key, value, created_at, updated_at) FROM stdin;
5e6fb2ca-b4a9-4c12-a9b4-083449e46e75	plan_limits	{"pro": {"max_faqs": 100, "max_staff": 0, "max_products": 50, "contacts_per_month": 300, "max_orders_per_month": 500, "ai_messages_per_month": 2000, "max_images_per_product": 5}, "free": {"max_faqs": 10, "max_staff": 0, "max_products": 5, "contacts_per_month": 50, "max_orders_per_month": 50, "ai_messages_per_month": 100, "max_images_per_product": 1}, "enterprise": {"max_faqs": 999, "max_staff": 2, "max_products": 999, "contacts_per_month": 1500, "max_orders_per_month": 9999, "ai_messages_per_month": 99999, "max_images_per_product": 10}}	2026-09-28 16:26:43.598969+00	2026-09-28 16:26:43.598969+00
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.profiles (id, user_id, full_name, email, created_at, updated_at, plan_tier, is_active, business_name, max_products, max_faqs, billing_cycle_start, is_paused, addon_products, addon_faqs, addon_orders, addon_ai_messages, addon_images, addon_staff, addon_contacts) FROM stdin;
cb555e0d-49dc-4e97-8949-1e7db2f822e8	d5acf738-672d-4cd9-8257-3a726f51503b	Admin	admin@arawwala.com	2026-09-28 16:31:28.704019+00	2026-09-28 16:31:28.704019+00	free	t	\N	5	10	2026-09-28 16:31:28.704019+00	f	0	0	0	0	0	0	0
aa4f5f7d-3154-4e2a-8482-1770bcbb251f	05bea8cb-2e17-4593-9004-b8abacc7ee58	Customer	customer@arawwala.com	2026-09-28 16:31:36.561363+00	2026-09-28 17:26:29.20756+00	pro	t	\N	5	10	2026-09-28 16:31:36.561363+00	f	0	0	0	0	0	0	0
\.


--
-- Data for Name: settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.settings (id, key, value, created_at, updated_at, user_id) FROM stdin;
bde68479-33d0-42c6-99c3-df3187f46cc4	welcome_message	{"text": "Welcome! How can I help you today?"}	2026-09-28 16:31:28.704019+00	2026-09-28 16:31:28.704019+00	d5acf738-672d-4cd9-8257-3a726f51503b
875369ce-ad32-472a-8309-c591e9ea0955	payment_info	{"bank_name": "", "account_name": "", "account_number": ""}	2026-09-28 16:31:28.704019+00	2026-09-28 16:31:28.704019+00	d5acf738-672d-4cd9-8257-3a726f51503b
7bbee82d-0925-4080-ba35-367b2f549098	auto_responses	{"enabled": true}	2026-09-28 16:31:28.704019+00	2026-09-28 16:31:28.704019+00	d5acf738-672d-4cd9-8257-3a726f51503b
ce4d6def-97b1-442b-bf8e-a0191d889e9f	auto_responses	{"enabled": true}	2026-09-28 16:31:36.561363+00	2026-09-28 16:31:36.561363+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
19df9694-7835-4235-9624-b94cf14ab0e8	order_followup_message	{"text": "ගෙවීම් කල පසු Slip එකේ Photo එකක් හෝ Screenshot එකක් සමග \\n\\nName :\\nAddress :\\nContact : 2ක් අපිට එවන්න \\n\\nWholesale සහ Retails දෙපාර්ශවයටම අදාල වේ.  ස්තූතියි\\n\\nඅපගේ කුරියර් සේවාව පැය 16ක් වැනි ඉතාමත් කෙටි කාලයකින් ලබා දෙන බව වගකීමෙන් දැනුම් දෙමි .... 💓\\nඅපගේ පැය 16 සේවාව පොහෝ දිනයන් හා ඉරිදා දිනට වලන්ගු නොවන බව සලකන්න.....\\nසිකුරාදා දමන ඇනවුම් සෙනසුරාදා දින ලගම ශාඛාව වෙත ඇමතුමක් ලගා දී ලබා ගන්න.... \\nසමහර ප්‍රදේශ වලට ඉදින බෙදාහැර්‍රම් සිදු නොකරන බැවිනි 😟\\n\\nඔබගේ ඇණවුම Track කිරීමට කරුණාකර පහත Link එක ක්ලික් කරන්න: \\nhttps://promptxpress.lk/TrackItem.aspx#\\n\\nඔබට වැඩිදුර සහාය අවශ්‍ය නම්, ඔබට Prompt Express 0114 422 733 ට සම්බන්ධ කර ගත හැකිය, නැතහොත් 0777 887 881 ට අපව කෙලින්ම සම්බන්ධ කර ගත හැකිය.\\n\\n\\nAfter payment, send us a photo or screenshot of the slip with \\n\\nName :\\nAddress :\\nContact : 2 \\n\\nApplicable to both Wholesale and Retails. Thank you\\n\\nI would like to inform you that our courier service is provided in a very short time of 16 hours .... 💓\\nPlease note that our 16 hour service is not available on Poya days and Sundays.....\\nOrders placed on Fridays should be picked up by calling the nearest branch on Saturday.... \\nBecause some areas are", "enabled": true}	2026-09-28 17:04:12.044681+00	2026-09-28 17:04:12.044681+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
cf37d98d-033b-4f06-9968-784e26325a02	payment_info	{"accounts": [{"account_name": "A.D.K.D.C. APPUHAMY", "account_type": "bank", "account_label": "NDB Bank - Katana", "account_number": "106080700965"}], "bank_name": "NDB Bank - Katana", "account_name": "A.D.K.D.C. APPUHAMY", "account_number": "106080700965"}	2026-09-28 16:31:36.561363+00	2026-09-28 17:34:23.610387+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
9fbab18b-db7e-4e97-bc1c-2719b0ea99eb	delivery_settings	{"delivery_info": "ඩිලිවරි ගාස්තු සදහා පලමු 1kg අනිවාර්යයෙන් 480/=ක් ගෙවිය යුතු අතර වැඩි වන සෑම 1kg සදහාම 140/= ගානේ එකතු වේ.\\n\\nඋදාහරණයක් වශයෙන් 5kg පැකේජයක් සදහා 1, 060/= වැය වේ. \\nමෙයා ලන්කාවේ සෑම තැනකටම අදාල වේ.\\n\\nඔව් සර් ලන්කාව වටේම පැය 16ක් ඇතුලත Diliver කරල දෙන්න පුලුවන් අපිට.\\n\\nසෙනසුරාදා ඉරිදා හා පෝය දින හැර සතියේ ඕනම දවසක හවස 5 වන තෙක් orders දාන්න පුලුවන්\\n\\nDelivery charges are 480/= for the first 1kg and 140/= for each additional 1kg.\\n\\nFor example, a 5kg package costs 1, 060/=. \\nThis applies to all parts of Sri Lanka.\\n\\nYes sir, we can deliver within 16 hours all over Sri Lanka.\\n\\nOrders can be placed on any day of the week except Saturday, Sunday and Poya days until 5.00 p.m.", "location_info": "Arawwala Motors\\nකටාන පන්සල ඉදිරිපිට \\n100/79, \\nCity Gate Temple Junction Katana North, \\nKatana.\\n\\n077-3844123\\n077-4811555", "delivery_tracking": "සෙනසුරාදා දින වල සමහර branches dilivery කරන්නේ 12 වෙනක්ල් විතරයි.\\nඒ නිසා අනිවාරෙන් උදේ 10ට වගේ කෝල් එකක් ආවෙ නැත්තම් branch එකට කෝල් එකක් අරන් අහන්න අද එනවද නැද්ද කියලා....\\n\\nඔයාගෙ package එක අනිවාරෙන් උදේ වෙද්දි ලන්කාවේ කොහෙ හිටියත් Branch එකට එනවා. එතනින් තමා බෙදන්න පරක්කු උනොත් වෙන්නේ.\\n\\nතමාගේ package එක තියෙන තැන දැනගන්න 👇\\nhttps://www.promptxpress.lk/TrackItem.aspx# \\nකොල පාට ස්ටිකරේ තියෙන RPxxxxxxxx නම්බර් එක Type කරල search කරන්න.\\n\\nඅදාල  branch එක පහල link එකෙන් හොයලා කෝල් එකක් දෙන්න 👇\\nhttps://www.promptxpress.lk/BranchNetwork.aspx#\\n\\nසතියෙ දින වල කිසිම ප්‍රමාදයක් නැතිව පැය 16න් ලන්කාවේ කොතනට උනත් ඩිලිවරි වෙනවා. සෙනසුරාදා තමා සමහර branch වල ප්‍රශ්නයක් වෙන්නේ", "location_maps_link": "https://maps.app.goo.gl/hG3BtEuqJ1e7m27AA?g_st=com.google.maps.preview.copy", "free_delivery_threshold": 0}	2026-09-28 17:52:25.34435+00	2026-09-28 17:52:25.34435+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
5de0f18a-7974-40c3-bb97-62bbbede7702	welcome_message	{"text": "ඔව් කියන්න සර්\\nමොනාද ඕනේ\\n\\nකරුණාකර ඔබට අවශ්‍ය භාණ්ඩයේ නම සහ ඔබගේ වාහනයේ මාදිලිය අපට එවන්න. ඔබට භාණ්ඩයේ නම හෝ වාහනයේ මාදිලිය ගැන විශ්වාසයක් නොමැති නම්, කරුණාකර භාණ්ඩයේ හෝ වාහනයේ ඡායාරූපයක් එවන්න.\\n\\nYes sir, tell me what you want.\\n\\nPlease send us the name of the product you need and the model of your vehicle. If you are not sure about the product name or the vehicle model, please send a photo of the product or the vehicle.\\n\\nஆம் ஐயா, சொல்லுங்கள்\\nஉங்களுக்கு என்ன வேண்டும்\\n\\nஉங்களுக்கு தேவையான பொருளின் பெயரையும் உங்கள் வாகனத்தின் மாதிரியையும் எங்களுக்கு அனுப்பவும். பொருளின் பெயர் அல்லது வாகனத்தின் மாதிரி உங்களுக்குத் தெரியாவிட்டால், தயவுசெய்து பொருளின் அல்லது வாகனத்தின் புகைப்படத்தை அனுப்பவும்.\\n", "media_url": null, "media_urls": [], "bypass_triggers": [], "welcome_sequence": [{"type": "text"}]}	2026-09-28 16:31:36.561363+00	2026-10-01 09:52:22.577667+00	05bea8cb-2e17-4593-9004-b8abacc7ee58
\.


--
-- Data for Name: staff_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.staff_accounts (id, owner_id, staff_user_id, staff_email, staff_name, permissions, is_active, created_at, updated_at, whatsapp_number) FROM stdin;
\.


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.user_roles (id, user_id, role, created_at) FROM stdin;
953b6f67-fe27-4ed9-ba3c-a77f7149825d	d5acf738-672d-4cd9-8257-3a726f51503b	business_user	2026-09-28 16:31:28.704019+00
c249b6c6-dee6-4b7f-ae74-74d57ee5ec49	05bea8cb-2e17-4593-9004-b8abacc7ee58	business_user	2026-09-28 16:31:36.561363+00
\.


--
-- Data for Name: user_wsender_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY arawwala_motors_customization.user_wsender_sessions (id, user_id, session_id, session_name, created_at, session_api_key) FROM stdin;
d39a693e-1c5d-4933-bb3d-e3546b51c9c6	05bea8cb-2e17-4593-9004-b8abacc7ee58	u_05bea8cb2e1745939004	test	2026-10-01 10:12:19.838772+00	u_05bea8cb2e1745939004
\.


--
-- PostgreSQL database dump complete
--

\unrestrict uIIL95zWHxf06J6MmQbSzq1x5GZjbKeAnKSfkAiL3OosFu0ndJT8digHwyfDikP



-- 5. Add custom triggers for auth.users
CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.profiles (user_id, email, phone)
  VALUES (new.id, new.email, new.phone);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user_role()
RETURNS trigger AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.user_roles (user_id, role)
  VALUES (new.id, 'owner');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user_settings()
RETURNS trigger AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.settings (user_id, key, value)
  VALUES (new.id, 'leads_auto_assign', '{"enabled": false}'::jsonb);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.handle_new_user();

DROP TRIGGER IF EXISTS on_auth_user_created_role_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_role_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.handle_new_user_role();

DROP TRIGGER IF EXISTS on_auth_user_created_settings_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_settings_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.handle_new_user_settings();
