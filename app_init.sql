-- ---
-- Code to generate required DB components for the public inspection app 3.2.5
-- ---

BEGIN;

	CREATE EXTENSION IF NOT EXISTS postgis;
	CREATE EXTENSION IF NOT EXISTS tablefunc;
	CREATE EXTENSION IF NOT EXISTS unaccent;
	CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    --

	SET search_path = inspection, public;

	-- ---
    -- Check with Alvaro
	-- ---

		ALTER TABLE firma_l
            ADD COLUMN IF NOT EXISTS conflicto boolean,
            ADD COLUMN IF NOT EXISTS remarks character varying;

		ALTER TABLE party
            ADD COLUMN IF NOT EXISTS la_partyid character varying;

        ALTER TABLE party__attach
            ADD COLUMN IF NOT EXISTS la_partyid character varying,
            ADD COLUMN IF NOT EXISTS attachment_type character varying;

    --

        CREATE OR REPLACE VIEW v_firma_l
        AS
        SELECT f.limitid,
            f.limitid / 100 AS predio,
            f.limitid % 100 AS limite,
            (upper(p.first_name) || ' '::text) || upper(p.last_name) AS nombre,
            p.objectid AS id_party,
            f.concepto,
            f.fecha,
            f.titulo,
            f.remarks
        FROM firma_l AS f
            LEFT JOIN party AS p ON f.globalid::text = p.right_id::text;

    --

        CREATE OR REPLACE VIEW firma_p AS
        SELECT DISTINCT trunc((firma_l.limitid / 100)::double precision) AS id,
            firma_l.globalid,
            firma_l.titulo
        FROM firma_l;

    --

        CREATE OR REPLACE VIEW v_firma_p
        AS
        SELECT f.id AS predio,
            (upper(p.first_name) || ' '::text) || upper(p.last_name) AS nombre,
            f.titulo
        FROM firma_p AS f
            LEFT JOIN party p ON f.globalid::text = p.right_id::text;

    --

        CREATE OR REPLACE VIEW representante
        AS
        SELECT predio,
            min(nombre) AS nombre
        FROM v_firma_p
        GROUP BY predio
        ORDER BY predio;

    --

        CREATE OR REPLACE VIEW c_t
        AS
        SELECT l1.limitid AS limit1,
            l1.id_pol AS pol1,
            l2.limitid AS limit2,
            l2.id_pol AS pol2
        FROM limites AS l1, limites AS l2
        WHERE ST_Equals(l1.geom, l2.geom) AND l1.limitid <> l2.limitid
        ORDER BY l1.id_pol;

    --

        CREATE OR REPLACE VIEW vecinos_representantes
        AS
        SELECT DISTINCT c_t.pol1 AS predio,
            c_t.pol2 AS vecino,
            r.nombre AS nombre_vecino
        FROM c_t, representante r
        WHERE c_t.pol2::double precision = r.predio;

    --

        CREATE OR REPLACE VIEW concepto_predio_con_vecinos
        AS
        SELECT f.predio,
            f.limitid,
            f.id_party,
            vr.vecino,
            vr.nombre_vecino,
            f.concepto,
            f.fecha,
            -- json_build_object('type', 'Feature', 'id', l.limitid, 'geometry', st_asgeojson(l.geom)::json, 'properties', json_build_object('limitid', l.limitid)) AS geom,
            f.remarks
        FROM v_firma_l f
            JOIN c_t AS c ON f.limitid = c.limit1
            JOIN limites AS l ON l.limitid = f.limitid,
            vecinos_representantes AS vr
        WHERE c.pol1 = vr.predio AND c.pol2 = vr.vecino;

    --

        CREATE OR REPLACE VIEW firma_colinda_todos
        AS
        SELECT c_t.limit1,
            c_t.pol1,
            c_t.limit2,
            c_t.pol2,
            fp.globalid,
            fl.id_party,
            fl.titulo,
            fl.concepto,
            fl.fecha,
            fl.conflicto
        FROM c_t
            JOIN firma_p fp ON c_t.pol2::double precision = fp.id
            LEFT JOIN firma_l fl ON c_t.limit2 = fl.limitid AND fp.globalid::text = fl.globalid::text;

    --

        CREATE OR REPLACE VIEW cuenta_limite
        AS
        SELECT tot.limitid,
            COALESCE(tot.total, 0::bigint) AS total,
            COALESCE(nul.nulos, 0::bigint) AS nulos,
            COALESCE(si.si, 0::bigint) AS si,
            titulo.titulo,
            conflicto.conflicto
        FROM (SELECT limitid, count(*) AS total
                FROM firma_l
                GROUP BY limitid
                ORDER BY limitid) AS tot
            LEFT JOIN (SELECT limitid, count(*) AS nulos
                FROM firma_l
                WHERE concepto IS NULL
                GROUP BY limitid
                ORDER BY limitid) AS nul USING (limitid)
            LEFT JOIN (SELECT limitid, count(*) AS si
                FROM firma_l
                WHERE concepto = true
                GROUP BY limitid
                ORDER BY limitid) AS si USING (limitid)
            LEFT JOIN (SELECT DISTINCT limitid, titulo
                FROM firma_l) AS titulo USING (limitid)
            LEFT JOIN (SELECT DISTINCT limitid, conflicto
                FROM firma_l) AS conflicto USING (limitid);

    --

        CREATE OR REPLACE VIEW cuenta_limite_vecinos AS
        SELECT tot.limit1,
            COALESCE(tot.total, 0::bigint) AS total,
            COALESCE(nul.nulos, 0::bigint) AS nulos,
            COALESCE(si.si, 0::bigint) AS si,
            titulos.titulo,
            conflicto.conflicto
        FROM (SELECT limit1, count(*) AS total
                FROM firma_colinda_todos
                GROUP BY limit1
                ORDER BY limit1) AS tot
            LEFT JOIN (SELECT limit1, count(*) AS nulos
                FROM firma_colinda_todos
                WHERE concepto IS NULL
                GROUP BY limit1
                ORDER BY limit1) AS nul USING (limit1)
            LEFT JOIN (SELECT limit1, count(*) AS si
                FROM inspection.firma_colinda_todos
                WHERE concepto = true
                GROUP BY limit1
                ORDER BY limit1) AS si USING (limit1)
            LEFT JOIN (SELECT DISTINCT limit1, titulo
                FROM firma_colinda_todos) AS titulos USING (limit1)
            LEFT JOIN (SELECT DISTINCT limit1, conflicto
                FROM firma_colinda_todos) AS conflicto USING (limit1);

    --

        CREATE OR REPLACE VIEW muestra_limite_p
        AS
        SELECT limitid,
            CASE
                WHEN titulo = true THEN 9
                WHEN conflicto = true AND si = total THEN 6
                WHEN conflicto = true AND (total - nulos - si) > 0 THEN 7
                WHEN conflicto AND si > 0 THEN 5
                WHEN conflicto = true THEN 8
                WHEN nulos = total THEN 1
                WHEN si = total THEN 3
                WHEN si IS NULL AND (total - nulos) > 0 THEN 4
                WHEN (total - nulos - si) > 0 THEN 4
                WHEN nulos IS NULL THEN 4
                ELSE 2
            END AS color
        FROM cuenta_limite;

    --

        CREATE OR REPLACE VIEW muestra_limite_v
        AS
        SELECT limit1 AS limitid,
            CASE
                WHEN titulo THEN 9
                WHEN conflicto = true AND si = total THEN 6
                WHEN conflicto = true AND (total - nulos - si) > 0 THEN 7
                WHEN conflicto = true AND si > 0 THEN 5
                WHEN conflicto = true THEN 8
                WHEN nulos = total THEN 1
                WHEN si = total THEN 3
                WHEN si IS NULL AND (total - nulos) > 0 THEN 4
                WHEN (total - nulos - si) > 0 THEN 4
                WHEN nulos IS NULL THEN 4
                ELSE 2
            END AS color
        FROM cuenta_limite_vecinos;

    --

        CREATE OR REPLACE VIEW muestra_limite
        AS
        SELECT p.limitid,
                CASE
                    WHEN p.color_p = 9 OR v.color_v = 9 THEN 9
                    WHEN p.color_p = 7 OR v.color_v = 7 THEN 7
                    WHEN p.color_p = 4 AND v.color_v > 4 THEN 7
                    WHEN p.color_p > 4 AND v.color_v = 4 THEN 7
                    WHEN p.color_p = 6 AND v.color_v = 3 THEN 6
                    WHEN p.color_p = 6 AND v.color_v = 1 THEN 5
                    WHEN p.color_p = 4 OR v.color_v = 4 THEN 4
                    WHEN p.color_p = 5 OR v.color_v = 5 THEN 5
                    WHEN p.color_p = 6 AND v.color_v = 6 THEN 6
                    WHEN p.color_p = 2 AND v.color_v = 6 THEN 5
                    WHEN p.color_p = 6 AND v.color_v = 2 THEN 5
                    WHEN p.color_p = 6 AND v.color_v = 8 THEN 5
                    WHEN p.color_p = 8 AND v.color_v = 6 THEN 5
                    WHEN p.color_p = 2 AND v.color_v = 8 THEN 5
                    WHEN p.color_p = 2 OR v.color_v = 2 THEN 2
                    WHEN p.color_p = 3 AND v.color_v = 3 THEN 3
                    WHEN p.color_p = 3 AND v.color_v = 6 THEN 6
                    WHEN p.color_p = 3 AND v.color_v = 8 THEN 5
                    WHEN p.color_p = 8 AND v.color_v = 3 THEN 5
                    WHEN p.color_p = 3 OR v.color_v = 3 THEN 2
                    WHEN p.color_p = 1 AND v.color_v = 1 THEN 1
                    WHEN p.color_p = 1 AND v.color_v = 8 THEN 1
                    WHEN p.color_p = 8 AND v.color_v = 1 THEN 1
                    WHEN p.color_p = 1 AND v.color_v = 6 THEN 5
                    WHEN p.color_p = 8 AND v.color_v = 8 THEN 1
                    ELSE NULL::integer
                END AS estate
        FROM (SELECT limitid, color AS color_p
                FROM muestra_limite_p) AS p
            LEFT JOIN (SELECT limitid, color AS color_v
                FROM muestra_limite_v) AS v USING (limitid)
        ORDER BY p.limitid;

    --

        CREATE OR REPLACE VIEW revisa_limite
        AS
        SELECT c_t.limit1 AS limite1,
            c_t.pol1,
            vfl_1.nombre AS nombre1,
            vfl_1.concepto AS concepto1,
            c_t.pol2,
            vfl_2.nombre AS nombre2,
            vfl_2.concepto AS concepto2,
            c_t.limit2 AS limite2
        FROM c_t,
            v_firma_l AS vfl_1,
            v_firma_l AS vfl_2
        WHERE c_t.limit1 = vfl_1.limitid AND c_t.limit2 = vfl_2.limitid
        ORDER BY c_t.limit1;

    --

        CREATE OR REPLACE VIEW v_firma_colinda_todos AS
        SELECT f.pol1 AS predio,
            f.pol2 AS predio_vecino,
            (upper(p.first_name) || ' '::text) || upper(p.last_name) AS nombre_vecino,
            f.concepto,
            f.fecha
        FROM firma_colinda_todos AS f
            LEFT JOIN party AS p ON f.globalid::text = p.right_id::text AND f.id_party = p.objectid;

    -- ---
    -- ---

    CREATE TABLE IF NOT EXISTS la_party
    (
        objectid integer NOT NULL DEFAULT nextval('inspection.la_party_objectid_seq'::regclass),
        globalid character varying COLLATE pg_catalog."default" NOT NULL,
        first_name character varying(150) COLLATE pg_catalog."default" NOT NULL,
        last_name character varying(150) COLLATE pg_catalog."default" NOT NULL,
        gender character varying(50) COLLATE pg_catalog."default" NOT NULL,
        party_type character varying(50) COLLATE pg_catalog."default" NOT NULL,
        phone_number character varying(150) COLLATE pg_catalog."default",
        id_number character varying(20) COLLATE pg_catalog."default",
        date_of_birth timestamp without time zone,
        created_on timestamp without time zone,
        checked_on timestamp without time zone,
        CONSTRAINT la_party_pk PRIMARY KEY (objectid),
        CONSTRAINT la_party_globalid_uk UNIQUE (globalid),
        CONSTRAINT la_party_ldnumber_uk UNIQUE (id_number)
    );

	--
	-- Views
	--

	DROP VIEW IF EXISTS v_firma_l_crt;

    CREATE OR REPLACE VIEW v_firma_l_crt
    AS
    SELECT f.limitid,
        f.limitid / 100 AS predio,
        f.limitid % 100 AS limite,
        (upper(pt.first_name::text) || ' '::text) || upper(pt.last_name::text) AS nombre,
        pt.id_number,
        pt.objectid AS party_id,
        pt.objectid AS id_party,
        f.concepto,
        f.fecha,
        f.titulo
    FROM firma_l f
        LEFT JOIN party pt ON f.globalid::text = pt.right_id::text;


	--

	DROP VIEW IF EXISTS revisa_limite_crt;

    CREATE OR REPLACE VIEW revisa_limite_crt
    AS
    SELECT c_t.limit1 AS limite,
        c_t.pol1,
        vfl_1.nombre AS nombre1,
        vfl_1.party_id AS party_id1,
        vfl_1.id_number AS id_number1,
        vfl_1.concepto AS concepto1,
        c_t.pol2,
        vfl_2.nombre AS nombre2,
        vfl_2.party_id AS party_id2,
        vfl_2.id_number AS id_number2,
        vfl_2.concepto AS concepto2
    FROM c_t,
        v_firma_l_crt vfl_1,
        v_firma_l_crt vfl_2
    WHERE c_t.limit1 = vfl_1.limitid AND c_t.limit2 = vfl_2.limitid
    ORDER BY c_t.limit1;

	--

	DROP MATERIALIZED VIEW IF EXISTS muestra_limite_view;

	CREATE MATERIALIZED VIEW muestra_limite_view
    AS
    SELECT limitid, estate as status
    FROM muestra_limite;

    --

	DROP MATERIALIZED VIEW IF EXISTS concepto_predio_con_vecinos_view;

	CREATE MATERIALIZED VIEW concepto_predio_con_vecinos_view
    AS
    SELECT vr.predio,
        f.limitid,
        f.id_party,
        vr.vecino,
        vr.nombre_vecino,
        f.concepto,
        f.fecha,
        f.remarks
        -- ,json_build_object('type', 'Feature', 'id', l.limitid, 'geometry', st_asgeojson(l.geom)::json, 'properties', json_build_object('limitid', l.limitid)) AS geom
    --FROM v_firma_l f
    FROM firma_l f
        JOIN c_t c ON f.limitid = c.limit1
        --JOIN limites l ON l.limitid = f.limitid
        ,vecinos_representantes vr
    WHERE c.pol1 = vr.predio AND c.pol2 = vr.vecino;

	--

	ALTER TABLE muestra_limite_view
        OWNER TO kadaster_admin;
    ALTER TABLE concepto_predio_con_vecinos_view
        OWNER TO kadaster_admin;

	--
	--	Triggers
	--

	CREATE TABLE IF NOT EXISTS status_log
	(
		limitid integer,
		rightid character varying,
		id_party integer,
		concept boolean,
		signed_on date,
		remarks character varying,
		signature character varying,
		fingerprint bytea,
		details character varying,
		changed_on timestamp
	);

	--

	CREATE TABLE IF NOT EXISTS signature_log
	(
		party_id integer,
		signed_on date,
		signature character varying,
		fingerprint bytea,
		details character varying
	);

	--

	CREATE OR REPLACE FUNCTION log_signature() RETURNS TRIGGER
	AS $$
		BEGIN
			INSERT INTO signature_log(party_id, signed_on, signature, fingerprint, details)
			VALUES (NEW.party_id, NEW.signed_on, NEW.signature, NEW.fingerprint, NEW.details);
			RETURN NEW;
		END;
	$$ LANGUAGE plpgsql;
	--
    DROP TRIGGER IF EXISTS signature_trigger ON boundary_signature;
	CREATE TRIGGER signature_trigger
		BEFORE INSERT OR UPDATE ON boundary_signature
		FOR EACH ROW
		EXECUTE PROCEDURE log_signature();

	--

	CREATE OR REPLACE FUNCTION log_status() RETURNS TRIGGER
	AS $$
		BEGIN
			IF OLD.concepto is null OR NEW.concepto <> OLD.concepto THEN
				WITH d AS (
					SELECT *
					FROM signature_log
				)
				INSERT INTO status_log(limitid, rightid, id_party, concept, signed_on,
												remarks, signature, fingerprint, details, changed_on)
				SELECT NEW.limitid, NEW.globalid, NEW.id_party, NEW.concepto, signed_on, NEW.remarks,
					d.signature, d.fingerprint, d.details, now()
				FROM d
				WHERE d.party_id = NEW.id_party;
			END IF;
			RETURN NEW;
		END;
	$$ LANGUAGE plpgsql;
	--
	DROP TRIGGER IF EXISTS status_trigger ON firma_l;
	CREATE TRIGGER status_trigger
		BEFORE UPDATE ON firma_l
		FOR EACH ROW
		EXECUTE PROCEDURE log_status();

	--

    CREATE SCHEMA IF NOT EXISTS basedata;
    GRANT USAGE ON SCHEMA basedata TO kadaster;
    ALTER DEFAULT PRIVILEGES IN SCHEMA basedata GRANT SELECT ON TABLES TO kadaster;

    GRANT USAGE ON SCHEMA inspection TO kadaster, kadaster_admin;
    GRANT SELECT ON ALL TABLES IN SCHEMA basedata TO kadaster;
    GRANT SELECT ON ALL TABLES IN SCHEMA inspection TO kadaster;
    GRANT ALL ON ALL TABLES IN SCHEMA inspection TO kadaster_admin;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA inspection TO kadaster_admin;

END;
