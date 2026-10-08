-- 001 · Esquema inicial de la base ventas (estado al 2026-10-07, antes de la migración 002).
-- Generado con pg_dump --schema-only. Crear la base antes: CREATE DATABASE ventas;

--
-- PostgreSQL database dump
--



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
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA public;


--
-- Name: EXTENSION fuzzystrmatch; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION fuzzystrmatch IS 'determine similarities and distance between strings';


--
-- Name: unaccent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;


--
-- Name: EXTENSION unaccent; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION unaccent IS 'text search dictionary that removes accents';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: acciones_panel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.acciones_panel (
    accion_id bigint NOT NULL,
    fecha timestamp without time zone DEFAULT now() NOT NULL,
    accion text NOT NULL,
    captura_id text,
    pago_id text,
    estado_anterior text,
    estado_nuevo text,
    detalle jsonb
);


--
-- Name: acciones_panel_accion_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.acciones_panel_accion_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: acciones_panel_accion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.acciones_panel_accion_id_seq OWNED BY public.acciones_panel.accion_id;


--
-- Name: capturas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capturas (
    captura_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    whatsapp text NOT NULL,
    message_id text,
    nickname text,
    precio numeric,
    tipo_imagen text,
    confianza numeric,
    estado_captura text DEFAULT 'nueva'::text NOT NULL,
    fecha_recepcion timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: clientes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clientes (
    cliente_id text NOT NULL,
    whatsapp text NOT NULL,
    nombre_real text,
    push_name text,
    fecha_registro timestamp without time zone DEFAULT now() NOT NULL,
    notas text
);


--
-- Name: configuracion_pago; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.configuracion_pago (
    config_id text NOT NULL,
    metodo_pago text,
    nombre_receptor text,
    qr_base64 text,
    instrucciones text,
    activo boolean DEFAULT true NOT NULL,
    fecha_actualizacion timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: mensajes_procesados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mensajes_procesados (
    message_id text NOT NULL,
    whatsapp text,
    fecha_recepcion timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: pagos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pagos (
    pago_id text DEFAULT (gen_random_uuid())::text NOT NULL,
    whatsapp text NOT NULL,
    message_id text,
    monto_pagado numeric,
    monto_esperado numeric,
    confianza numeric,
    comprobante_base64 text,
    capturas_ids text[],
    resultado text,
    estado_pago text DEFAULT 'reportado'::text NOT NULL,
    fecha_recepcion timestamp without time zone DEFAULT now() NOT NULL,
    notas text,
    referencia_pago text,
    receptor_comprobante text,
    fecha_comprobante text,
    banco_app text,
    referencia_normalizada text,
    enviado_por text,
    motivo_revision text,
    fecha_verificacion timestamp without time zone
);


--
-- Name: acciones_panel accion_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.acciones_panel ALTER COLUMN accion_id SET DEFAULT nextval('public.acciones_panel_accion_id_seq'::regclass);


--
-- Name: acciones_panel acciones_panel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.acciones_panel
    ADD CONSTRAINT acciones_panel_pkey PRIMARY KEY (accion_id);


--
-- Name: capturas capturas_message_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capturas
    ADD CONSTRAINT capturas_message_id_key UNIQUE (message_id);


--
-- Name: capturas capturas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capturas
    ADD CONSTRAINT capturas_pkey PRIMARY KEY (captura_id);


--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (cliente_id);


--
-- Name: clientes clientes_whatsapp_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_whatsapp_key UNIQUE (whatsapp);


--
-- Name: configuracion_pago configuracion_pago_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.configuracion_pago
    ADD CONSTRAINT configuracion_pago_pkey PRIMARY KEY (config_id);


--
-- Name: mensajes_procesados mensajes_procesados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mensajes_procesados
    ADD CONSTRAINT mensajes_procesados_pkey PRIMARY KEY (message_id);


--
-- Name: pagos pagos_message_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_message_id_key UNIQUE (message_id);


--
-- Name: pagos pagos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pagos
    ADD CONSTRAINT pagos_pkey PRIMARY KEY (pago_id);


--
-- Name: acciones_panel_captura_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX acciones_panel_captura_idx ON public.acciones_panel USING btree (captura_id);


--
-- Name: capturas_whatsapp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX capturas_whatsapp_idx ON public.capturas USING btree (whatsapp);


--
-- Name: pagos_referencia_norm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pagos_referencia_norm_idx ON public.pagos USING btree (referencia_normalizada);


--
-- Name: pagos_whatsapp_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pagos_whatsapp_idx ON public.pagos USING btree (whatsapp);


--
-- PostgreSQL database dump complete
--


