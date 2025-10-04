--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4
-- Dumped by pg_dump version 17.4

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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bank_account; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bank_account (
    id uuid NOT NULL,
    label character varying(120) NOT NULL,
    bank_name character varying(120) NOT NULL,
    bank_code character varying(64),
    agency character varying(64),
    currency character varying(8) NOT NULL,
    iban_encrypted text,
    account_number_encrypted text,
    iban_normalized character varying(64),
    masked_account character varying(64),
    status character varying(32) NOT NULL,
    verification_metadata jsonb,
    verified_at timestamp with time zone,
    is_primary boolean NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    profile_id uuid NOT NULL
);


ALTER TABLE public.bank_account OWNER TO postgres;

--
-- Data for Name: bank_account; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bank_account (id, label, bank_name, bank_code, agency, currency, iban_encrypted, account_number_encrypted, iban_normalized, masked_account, status, verification_metadata, verified_at, is_primary, created_at, updated_at, profile_id) FROM stdin;
ea174d68-44bf-4dbd-ac4c-70ccc00c2901	Test	TestBank	\N	\N	EUR	gAAAAABo4aOG7cMd-cz-yVEaDD0p-Kxfk1Jrpm5c_szJdNbv1FaWvpUxE2lqPZrOBXnuCiqnt0tKA15hNGVrctK-sHLWPPOwXNWWuvBJ2oFFa5ZMX9HClCw=	gAAAAABo4aOGQ3OHLlbHVKv-ftqbT1q1Pqi3jnny1nKUniL1fh4UXulAZeEU61YtcacRwpAXyReBGqEKSK_ubtqckicLEcLaYQ==	FR1420041010050500013M02606	1234******7890	active	\N	\N	f	2025-10-04 23:45:26.615778+01	2025-10-04 23:45:26.628115+01	4536f7d8-17e6-4a22-b003-69c0b3d7f316
\.


--
-- Name: bank_account bank_accounts_bankaccount_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bank_account
    ADD CONSTRAINT bank_accounts_bankaccount_pkey PRIMARY KEY (id);


--
-- Name: bank_accoun_masked__e8855f_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accoun_masked__e8855f_idx ON public.bank_account USING btree (masked_account);


--
-- Name: bank_accoun_profile_7391fb_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accoun_profile_7391fb_idx ON public.bank_account USING btree (profile_id);


--
-- Name: bank_accoun_status_4669f3_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accoun_status_4669f3_idx ON public.bank_account USING btree (status);


--
-- Name: bank_accounts_bankaccount_iban_normalized_e39634ad; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accounts_bankaccount_iban_normalized_e39634ad ON public.bank_account USING btree (iban_normalized);


--
-- Name: bank_accounts_bankaccount_iban_normalized_e39634ad_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accounts_bankaccount_iban_normalized_e39634ad_like ON public.bank_account USING btree (iban_normalized varchar_pattern_ops);


--
-- Name: bank_accounts_bankaccount_masked_account_ac064c78; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accounts_bankaccount_masked_account_ac064c78 ON public.bank_account USING btree (masked_account);


--
-- Name: bank_accounts_bankaccount_masked_account_ac064c78_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accounts_bankaccount_masked_account_ac064c78_like ON public.bank_account USING btree (masked_account varchar_pattern_ops);


--
-- Name: bank_accounts_bankaccount_profile_id_4bd0fe14; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accounts_bankaccount_profile_id_4bd0fe14 ON public.bank_account USING btree (profile_id);


--
-- Name: bank_accounts_bankaccount_status_ac457a0d; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accounts_bankaccount_status_ac457a0d ON public.bank_account USING btree (status);


--
-- Name: bank_accounts_bankaccount_status_ac457a0d_like; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX bank_accounts_bankaccount_status_ac457a0d_like ON public.bank_account USING btree (status varchar_pattern_ops);


--
-- Name: bank_account bank_accounts_bankac_profile_id_4bd0fe14_fk_manage_pe; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bank_account
    ADD CONSTRAINT bank_accounts_bankac_profile_id_4bd0fe14_fk_manage_pe FOREIGN KEY (profile_id) REFERENCES public.manage_personnel_profile(id) DEFERRABLE INITIALLY DEFERRED;


--
-- PostgreSQL database dump complete
--

