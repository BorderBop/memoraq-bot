--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: gnote; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA gnote;


ALTER SCHEMA gnote OWNER TO postgres;

--
-- Name: message_metadata_fts_trigger(); Type: FUNCTION; Schema: gnote; Owner: supabase_admin
--

CREATE FUNCTION gnote.message_metadata_fts_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _lang_full TEXT;
BEGIN
  -- Маппинг ISO кодов в текстовые названия для поиска
  _lang_full := CASE LOWER(NEW.language)
    WHEN 'he' THEN 'hebrew ivrit иврит'
    WHEN 'ru' THEN 'russian русский russkiy'
    WHEN 'en' THEN 'english английский inglish'
    WHEN 'zh' THEN 'chinese китайский'
    WHEN 'es' THEN 'spanish испанский'
    WHEN 'fr' THEN 'french французский'
    WHEN 'de' THEN 'german немецкий'
    ELSE ''
  END;

  -- Сборка fts_vector (учитываем, что keywords — это JSONB)
  NEW.fts_vector := 
    setweight(to_tsvector('simple', COALESCE(NEW.summary, '')), 'A') ||
    setweight(to_tsvector('simple', COALESCE(NEW.category, '')), 'B') ||
    setweight(to_tsvector('simple', COALESCE(NEW.detected_type, '')), 'B') ||
    setweight(to_tsvector('simple', COALESCE(_lang_full, '')), 'A') || 
    setweight(to_tsvector('simple', COALESCE(NEW.language, '')), 'B') ||
    setweight(jsonb_to_tsvector('simple', COALESCE(NEW.keywords, '[]'::jsonb), '["string"]'), 'A');
    
  RETURN NEW;
END;
$$;


ALTER FUNCTION gnote.message_metadata_fts_trigger() OWNER TO supabase_admin;

--
-- Name: sync_message_counters(); Type: FUNCTION; Schema: gnote; Owner: supabase_admin
--

CREATE FUNCTION gnote.sync_message_counters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- New message inserted
  IF TG_OP = 'INSERT' THEN
    UPDATE gnote.users
    SET all_messages = COALESCE(all_messages, 0) + 1,
        last_visit = NOW()
    WHERE id = NEW.user_id;

    UPDATE gnote.topics
    SET all_messages = COALESCE(all_messages, 0) + 1
    WHERE id = NEW.topic_id;

    RETURN NEW;
  END IF;

  -- Message deleted
  IF TG_OP = 'DELETE' THEN
    UPDATE gnote.users
    SET all_messages = GREATEST(COALESCE(all_messages, 0) - 1, 0)
    WHERE id = OLD.user_id;

    UPDATE gnote.topics
    SET all_messages = GREATEST(COALESCE(all_messages, 0) - 1, 0)
    WHERE id = OLD.topic_id;

    RETURN OLD;
  END IF;

  -- Message moved to another topic or user
  IF TG_OP = 'UPDATE' THEN
    IF OLD.user_id IS DISTINCT FROM NEW.user_id THEN
      UPDATE gnote.users
      SET all_messages = GREATEST(COALESCE(all_messages, 0) - 1, 0)
      WHERE id = OLD.user_id;

      UPDATE gnote.users
      SET all_messages = COALESCE(all_messages, 0) + 1,
          last_visit = NOW()
      WHERE id = NEW.user_id;
    END IF;

    IF OLD.topic_id IS DISTINCT FROM NEW.topic_id THEN
      UPDATE gnote.topics
      SET all_messages = GREATEST(COALESCE(all_messages, 0) - 1, 0)
      WHERE id = OLD.topic_id;

      UPDATE gnote.topics
      SET all_messages = COALESCE(all_messages, 0) + 1
      WHERE id = NEW.topic_id;
    END IF;

    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;


ALTER FUNCTION gnote.sync_message_counters() OWNER TO supabase_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ai_usage_log; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.ai_usage_log (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    chat_id bigint,
    feature text NOT NULL,
    status text DEFAULT 'reserved'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


ALTER TABLE gnote.ai_usage_log OWNER TO supabase_admin;

--
-- Name: ai_usage_log_id_seq; Type: SEQUENCE; Schema: gnote; Owner: supabase_admin
--

CREATE SEQUENCE gnote.ai_usage_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gnote.ai_usage_log_id_seq OWNER TO supabase_admin;

--
-- Name: ai_usage_log_id_seq; Type: SEQUENCE OWNED BY; Schema: gnote; Owner: supabase_admin
--

ALTER SEQUENCE gnote.ai_usage_log_id_seq OWNED BY gnote.ai_usage_log.id;


--
-- Name: ai_user_limits; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.ai_user_limits (
    user_id bigint NOT NULL,
    hourly_limit integer DEFAULT 10 NOT NULL,
    is_unlimited boolean DEFAULT false NOT NULL,
    plan text DEFAULT 'free'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE gnote.ai_user_limits OWNER TO supabase_admin;

--
-- Name: app_settings; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.app_settings (
    key text NOT NULL,
    value jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    description text
);


ALTER TABLE gnote.app_settings OWNER TO supabase_admin;

--
-- Name: message_ai_metadata; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.message_ai_metadata (
    id bigint NOT NULL,
    message_id bigint,
    pending_message_id bigint,
    message_uuid uuid,
    user_id bigint NOT NULL,
    source_status text DEFAULT 'pending'::text NOT NULL,
    summary text,
    detected_type text,
    language text,
    keywords jsonb DEFAULT '[]'::jsonb NOT NULL,
    important_details jsonb DEFAULT '[]'::jsonb NOT NULL,
    suggested_topics jsonb DEFAULT '[]'::jsonb NOT NULL,
    confidence numeric(4,3) DEFAULT 0,
    raw_ai_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    ai_provider text DEFAULT 'gemini'::text,
    ai_model text DEFAULT 'gemini-2.5-flash'::text,
    analysis_status text,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    category text,
    ai_content text,
    model_name text DEFAULT 'gemini'::text,
    entities jsonb DEFAULT '[]'::jsonb,
    fts_vector tsvector,
    CONSTRAINT chk_message_ai_metadata_source_status CHECK ((source_status = ANY (ARRAY['pending'::text, 'active'::text, 'deleted'::text, 'failed'::text, 'orphan'::text])))
);


ALTER TABLE gnote.message_ai_metadata OWNER TO supabase_admin;

--
-- Name: message_ai_metadata_id_seq; Type: SEQUENCE; Schema: gnote; Owner: supabase_admin
--

CREATE SEQUENCE gnote.message_ai_metadata_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gnote.message_ai_metadata_id_seq OWNER TO supabase_admin;

--
-- Name: message_ai_metadata_id_seq; Type: SEQUENCE OWNED BY; Schema: gnote; Owner: supabase_admin
--

ALTER SEQUENCE gnote.message_ai_metadata_id_seq OWNED BY gnote.message_ai_metadata.id;


--
-- Name: message_rate_limit_settings; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.message_rate_limit_settings (
    id smallint DEFAULT 1 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    max_messages integer DEFAULT 10 NOT NULL,
    window_minutes integer DEFAULT 60 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT only_one_message_rate_limit_settings_row CHECK ((id = 1)),
    CONSTRAINT positive_max_messages CHECK ((max_messages > 0)),
    CONSTRAINT positive_window_minutes CHECK ((window_minutes > 0))
);


ALTER TABLE gnote.message_rate_limit_settings OWNER TO supabase_admin;

--
-- Name: messages; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.messages (
    id bigint NOT NULL,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    user_id bigint NOT NULL,
    topic_id bigint,
    message_type text DEFAULT 'text'::text,
    file_id text,
    file_unique_id text,
    file_name text,
    mime_type text,
    caption text,
    telegram_file_path text,
    file_url text,
    deleted_at timestamp without time zone,
    latitude double precision,
    longitude double precision,
    location_title text,
    location_address text,
    maps_url text,
    message_uuid uuid DEFAULT gen_random_uuid()
);


ALTER TABLE gnote.messages OWNER TO supabase_admin;

--
-- Name: messages_id_seq; Type: SEQUENCE; Schema: gnote; Owner: supabase_admin
--

CREATE SEQUENCE gnote.messages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gnote.messages_id_seq OWNER TO supabase_admin;

--
-- Name: messages_id_seq; Type: SEQUENCE OWNED BY; Schema: gnote; Owner: supabase_admin
--

ALTER SEQUENCE gnote.messages_id_seq OWNED BY gnote.messages.id;


--
-- Name: pending_messages; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.pending_messages (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    message text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    message_type text DEFAULT 'text'::text,
    file_id text,
    file_unique_id text,
    file_name text,
    mime_type text,
    caption text,
    telegram_file_path text,
    file_url text,
    latitude double precision,
    longitude double precision,
    location_title text,
    location_address text,
    maps_url text,
    message_uuid uuid DEFAULT gen_random_uuid()
);


ALTER TABLE gnote.pending_messages OWNER TO supabase_admin;

--
-- Name: pending_messages_id_seq; Type: SEQUENCE; Schema: gnote; Owner: supabase_admin
--

CREATE SEQUENCE gnote.pending_messages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gnote.pending_messages_id_seq OWNER TO supabase_admin;

--
-- Name: pending_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: gnote; Owner: supabase_admin
--

ALTER SEQUENCE gnote.pending_messages_id_seq OWNED BY gnote.pending_messages.id;


--
-- Name: search_session_results; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.search_session_results (
    id bigint NOT NULL,
    search_session_id uuid NOT NULL,
    message_id bigint NOT NULL,
    result_position integer NOT NULL,
    relevance_score numeric,
    result_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE gnote.search_session_results OWNER TO supabase_admin;

--
-- Name: search_session_results_id_seq; Type: SEQUENCE; Schema: gnote; Owner: supabase_admin
--

CREATE SEQUENCE gnote.search_session_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gnote.search_session_results_id_seq OWNER TO supabase_admin;

--
-- Name: search_session_results_id_seq; Type: SEQUENCE OWNED BY; Schema: gnote; Owner: supabase_admin
--

ALTER SEQUENCE gnote.search_session_results_id_seq OWNED BY gnote.search_session_results.id;


--
-- Name: search_sessions; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.search_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id bigint NOT NULL,
    chat_id bigint NOT NULL,
    search_query text,
    search_keywords text[],
    total_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE gnote.search_sessions OWNER TO supabase_admin;

--
-- Name: topics; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.topics (
    id bigint NOT NULL,
    title text NOT NULL,
    user_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    all_messages bigint DEFAULT 0,
    removable boolean DEFAULT true NOT NULL
);


ALTER TABLE gnote.topics OWNER TO supabase_admin;

--
-- Name: topics_id_seq; Type: SEQUENCE; Schema: gnote; Owner: supabase_admin
--

CREATE SEQUENCE gnote.topics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gnote.topics_id_seq OWNER TO supabase_admin;

--
-- Name: topics_id_seq; Type: SEQUENCE OWNED BY; Schema: gnote; Owner: supabase_admin
--

ALTER SEQUENCE gnote.topics_id_seq OWNED BY gnote.topics.id;


--
-- Name: user_state; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.user_state (
    user_id bigint NOT NULL,
    state text,
    created_at timestamp with time zone DEFAULT now(),
    search_query text,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE gnote.user_state OWNER TO supabase_admin;

--
-- Name: users; Type: TABLE; Schema: gnote; Owner: supabase_admin
--

CREATE TABLE gnote.users (
    id bigint NOT NULL,
    name text NOT NULL,
    first_visit timestamp with time zone DEFAULT now(),
    last_visit timestamp with time zone DEFAULT now(),
    all_messages bigint DEFAULT 0,
    username text,
    first_name text,
    last_name text,
    unlimited boolean DEFAULT false NOT NULL
);


ALTER TABLE gnote.users OWNER TO supabase_admin;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: gnote; Owner: supabase_admin
--

CREATE SEQUENCE gnote.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE gnote.users_id_seq OWNER TO supabase_admin;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: gnote; Owner: supabase_admin
--

ALTER SEQUENCE gnote.users_id_seq OWNED BY gnote.users.id;


--
-- Name: ai_usage_log id; Type: DEFAULT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.ai_usage_log ALTER COLUMN id SET DEFAULT nextval('gnote.ai_usage_log_id_seq'::regclass);


--
-- Name: message_ai_metadata id; Type: DEFAULT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.message_ai_metadata ALTER COLUMN id SET DEFAULT nextval('gnote.message_ai_metadata_id_seq'::regclass);


--
-- Name: messages id; Type: DEFAULT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.messages ALTER COLUMN id SET DEFAULT nextval('gnote.messages_id_seq'::regclass);


--
-- Name: pending_messages id; Type: DEFAULT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.pending_messages ALTER COLUMN id SET DEFAULT nextval('gnote.pending_messages_id_seq'::regclass);


--
-- Name: search_session_results id; Type: DEFAULT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.search_session_results ALTER COLUMN id SET DEFAULT nextval('gnote.search_session_results_id_seq'::regclass);


--
-- Name: topics id; Type: DEFAULT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.topics ALTER COLUMN id SET DEFAULT nextval('gnote.topics_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.users ALTER COLUMN id SET DEFAULT nextval('gnote.users_id_seq'::regclass);


--
-- Name: ai_usage_log ai_usage_log_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.ai_usage_log
    ADD CONSTRAINT ai_usage_log_pkey PRIMARY KEY (id);


--
-- Name: ai_user_limits ai_user_limits_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.ai_user_limits
    ADD CONSTRAINT ai_user_limits_pkey PRIMARY KEY (user_id);


--
-- Name: app_settings app_settings_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (key);


--
-- Name: message_ai_metadata message_ai_metadata_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.message_ai_metadata
    ADD CONSTRAINT message_ai_metadata_pkey PRIMARY KEY (id);


--
-- Name: message_rate_limit_settings message_rate_limit_settings_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.message_rate_limit_settings
    ADD CONSTRAINT message_rate_limit_settings_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: pending_messages pending_messages_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.pending_messages
    ADD CONSTRAINT pending_messages_pkey PRIMARY KEY (id);


--
-- Name: search_session_results search_session_results_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.search_session_results
    ADD CONSTRAINT search_session_results_pkey PRIMARY KEY (id);


--
-- Name: search_sessions search_sessions_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.search_sessions
    ADD CONSTRAINT search_sessions_pkey PRIMARY KEY (id);


--
-- Name: topics topics_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.topics
    ADD CONSTRAINT topics_pkey PRIMARY KEY (id);


--
-- Name: search_session_results uq_search_session_message; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.search_session_results
    ADD CONSTRAINT uq_search_session_message UNIQUE (search_session_id, message_id);


--
-- Name: user_state user_state_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.user_state
    ADD CONSTRAINT user_state_pkey PRIMARY KEY (user_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_ai_usage_log_user_created; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX idx_ai_usage_log_user_created ON gnote.ai_usage_log USING btree (user_id, created_at DESC);


--
-- Name: idx_ai_usage_log_user_status_created; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX idx_ai_usage_log_user_status_created ON gnote.ai_usage_log USING btree (user_id, status, created_at DESC);


--
-- Name: idx_message_metadata_fts; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX idx_message_metadata_fts ON gnote.message_ai_metadata USING gin (fts_vector);


--
-- Name: idx_search_results_message; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX idx_search_results_message ON gnote.search_session_results USING btree (message_id);


--
-- Name: idx_search_results_session_position; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX idx_search_results_session_position ON gnote.search_session_results USING btree (search_session_id, result_position);


--
-- Name: idx_search_sessions_user_created; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX idx_search_sessions_user_created ON gnote.search_sessions USING btree (user_id, created_at DESC);


--
-- Name: ix_message_ai_metadata_detected_type; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX ix_message_ai_metadata_detected_type ON gnote.message_ai_metadata USING btree (detected_type);


--
-- Name: ix_message_ai_metadata_keywords_gin; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX ix_message_ai_metadata_keywords_gin ON gnote.message_ai_metadata USING gin (keywords);


--
-- Name: ix_message_ai_metadata_orphans; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX ix_message_ai_metadata_orphans ON gnote.message_ai_metadata USING btree (source_status, created_at);


--
-- Name: ix_message_ai_metadata_raw_json_gin; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX ix_message_ai_metadata_raw_json_gin ON gnote.message_ai_metadata USING gin (raw_ai_json);


--
-- Name: ix_message_ai_metadata_status_created; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX ix_message_ai_metadata_status_created ON gnote.message_ai_metadata USING btree (source_status, created_at);


--
-- Name: ix_message_ai_metadata_user; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX ix_message_ai_metadata_user ON gnote.message_ai_metadata USING btree (user_id);


--
-- Name: ix_message_ai_metadata_user_uuid; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE INDEX ix_message_ai_metadata_user_uuid ON gnote.message_ai_metadata USING btree (user_id, message_uuid) WHERE (message_uuid IS NOT NULL);


--
-- Name: unique_user_topic_title; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE UNIQUE INDEX unique_user_topic_title ON gnote.topics USING btree (user_id, lower(title));


--
-- Name: ux_message_ai_metadata_message; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE UNIQUE INDEX ux_message_ai_metadata_message ON gnote.message_ai_metadata USING btree (message_id) WHERE (message_id IS NOT NULL);


--
-- Name: ux_message_ai_metadata_pending; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE UNIQUE INDEX ux_message_ai_metadata_pending ON gnote.message_ai_metadata USING btree (pending_message_id) WHERE (pending_message_id IS NOT NULL);


--
-- Name: ux_messages_user_uuid; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE UNIQUE INDEX ux_messages_user_uuid ON gnote.messages USING btree (user_id, message_uuid) WHERE (message_uuid IS NOT NULL);


--
-- Name: ux_pending_messages_user_uuid; Type: INDEX; Schema: gnote; Owner: supabase_admin
--

CREATE UNIQUE INDEX ux_pending_messages_user_uuid ON gnote.pending_messages USING btree (user_id, message_uuid) WHERE (message_uuid IS NOT NULL);


--
-- Name: message_ai_metadata trg_message_metadata_fts; Type: TRIGGER; Schema: gnote; Owner: supabase_admin
--

CREATE TRIGGER trg_message_metadata_fts BEFORE INSERT OR UPDATE ON gnote.message_ai_metadata FOR EACH ROW EXECUTE FUNCTION gnote.message_metadata_fts_trigger();


--
-- Name: messages trg_sync_message_counters; Type: TRIGGER; Schema: gnote; Owner: supabase_admin
--

CREATE TRIGGER trg_sync_message_counters AFTER INSERT OR DELETE OR UPDATE ON gnote.messages FOR EACH ROW EXECUTE FUNCTION gnote.sync_message_counters();


--
-- Name: message_ai_metadata fk_message_ai_metadata_message; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.message_ai_metadata
    ADD CONSTRAINT fk_message_ai_metadata_message FOREIGN KEY (message_id) REFERENCES gnote.messages(id) ON DELETE CASCADE;


--
-- Name: message_ai_metadata fk_message_ai_metadata_pending; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.message_ai_metadata
    ADD CONSTRAINT fk_message_ai_metadata_pending FOREIGN KEY (pending_message_id) REFERENCES gnote.pending_messages(id) ON DELETE SET NULL;


--
-- Name: message_ai_metadata fk_message_ai_metadata_user; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.message_ai_metadata
    ADD CONSTRAINT fk_message_ai_metadata_user FOREIGN KEY (user_id) REFERENCES gnote.users(id) ON DELETE CASCADE;


--
-- Name: pending_messages fk_pending_user; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.pending_messages
    ADD CONSTRAINT fk_pending_user FOREIGN KEY (user_id) REFERENCES gnote.users(id) ON DELETE CASCADE;


--
-- Name: search_session_results fk_search_results_message; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.search_session_results
    ADD CONSTRAINT fk_search_results_message FOREIGN KEY (message_id) REFERENCES gnote.messages(id) ON DELETE CASCADE;


--
-- Name: search_session_results fk_search_results_session; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.search_session_results
    ADD CONSTRAINT fk_search_results_session FOREIGN KEY (search_session_id) REFERENCES gnote.search_sessions(id) ON DELETE CASCADE;


--
-- Name: search_sessions fk_search_sessions_user; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.search_sessions
    ADD CONSTRAINT fk_search_sessions_user FOREIGN KEY (user_id) REFERENCES gnote.users(id) ON DELETE CASCADE;


--
-- Name: messages fk_topic; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.messages
    ADD CONSTRAINT fk_topic FOREIGN KEY (topic_id) REFERENCES gnote.topics(id) ON DELETE CASCADE;


--
-- Name: topics fk_topics_user; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.topics
    ADD CONSTRAINT fk_topics_user FOREIGN KEY (user_id) REFERENCES gnote.users(id) ON DELETE CASCADE;


--
-- Name: messages fk_user; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.messages
    ADD CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES gnote.users(id) ON DELETE CASCADE;


--
-- Name: user_state fk_user_state_user; Type: FK CONSTRAINT; Schema: gnote; Owner: supabase_admin
--

ALTER TABLE ONLY gnote.user_state
    ADD CONSTRAINT fk_user_state_user FOREIGN KEY (user_id) REFERENCES gnote.users(id) ON DELETE CASCADE;


--
-- Name: TABLE ai_usage_log; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE gnote.ai_usage_log TO postgres;


--
-- Name: SEQUENCE ai_usage_log_id_seq; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE gnote.ai_usage_log_id_seq TO postgres;


--
-- Name: TABLE ai_user_limits; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE gnote.ai_user_limits TO postgres;


--
-- Name: TABLE app_settings; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,INSERT,UPDATE ON TABLE gnote.app_settings TO postgres;


--
-- Name: TABLE message_ai_metadata; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE gnote.message_ai_metadata TO postgres;


--
-- Name: SEQUENCE message_ai_metadata_id_seq; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE gnote.message_ai_metadata_id_seq TO postgres;


--
-- Name: TABLE messages; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON TABLE gnote.messages TO postgres;


--
-- Name: SEQUENCE messages_id_seq; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE gnote.messages_id_seq TO postgres;


--
-- Name: TABLE pending_messages; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON TABLE gnote.pending_messages TO postgres;


--
-- Name: SEQUENCE pending_messages_id_seq; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE gnote.pending_messages_id_seq TO postgres;


--
-- Name: TABLE search_session_results; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE gnote.search_session_results TO postgres;


--
-- Name: SEQUENCE search_session_results_id_seq; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,USAGE ON SEQUENCE gnote.search_session_results_id_seq TO postgres;


--
-- Name: TABLE search_sessions; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE gnote.search_sessions TO postgres;


--
-- Name: TABLE topics; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON TABLE gnote.topics TO postgres;


--
-- Name: SEQUENCE topics_id_seq; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE gnote.topics_id_seq TO postgres;


--
-- Name: TABLE user_state; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON TABLE gnote.user_state TO postgres;


--
-- Name: TABLE users; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON TABLE gnote.users TO postgres;


--
-- Name: SEQUENCE users_id_seq; Type: ACL; Schema: gnote; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE gnote.users_id_seq TO postgres;


--
-- PostgreSQL database dump complete
--

