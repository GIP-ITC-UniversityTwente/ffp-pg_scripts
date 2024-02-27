------------------------------------------------------------------------------------------
-- 1. AGREGAR TABLAS Y FUNCIONES
------------------------------------------------------------------------------------------
create extension unaccent;
------------------------------------------
alter table inspection.firma_l
add column remarks character varying;
------------------------------------------
ALTER TABLE inspection.party__attach
ADD COLUMN attachment_type character varying(50) COLLATE pg_catalog."default";
------------------------------------------
CREATE OR REPLACE FUNCTION inspection.concepto_propietario_limite(

     integer,

     integer,

     boolean,

     date,

     character varying)

    RETURNS void

    LANGUAGE 'plpgsql'

 
    COST 100

    VOLATILE

AS $BODY$

     declare

     begin

           update inspection.firma_l set concepto = $3,fecha = $4, remarks = $5

                where limitid=$1 and id_party = $2;

     end

$BODY$;
------------------------------------------------------------------------------------------
-- 2. GENERAR VISTAS
------------------------------------------------------------------------------------------

CREATE OR REPLACE VIEW inspection.firma_p AS
 SELECT DISTINCT trunc((firma_l.limitid / 100)::double precision) AS id,
    firma_l.globalid,
    firma_l.titulo
   FROM inspection.firma_l;  
   

CREATE OR REPLACE VIEW inspection.v_firma_p AS
 SELECT f.id AS predio,
    (upper(pt.first_name::text) || ' '::text) || upper(pt.last_name::text) AS nombre,
    f.titulo
   FROM inspection.firma_p f
     LEFT JOIN inspection.party pt ON f.globalid::text = pt.right_id::text;  


CREATE OR REPLACE VIEW inspection.representante AS
 SELECT v_firma_p.predio,
    min(v_firma_p.nombre) AS nombre
   FROM inspection.v_firma_p
  GROUP BY v_firma_p.predio
  ORDER BY v_firma_p.predio;  
  
 
CREATE OR REPLACE VIEW inspection.representante AS
 SELECT v_firma_p.predio,
    min(v_firma_p.nombre) AS nombre
   FROM inspection.v_firma_p
  GROUP BY v_firma_p.predio
  ORDER BY v_firma_p.predio;  

 
CREATE OR REPLACE VIEW inspection.representante AS
 SELECT v_firma_p.predio,
    min(v_firma_p.nombre) AS nombre
   FROM inspection.v_firma_p
  GROUP BY v_firma_p.predio
  ORDER BY v_firma_p.predio;  
  
  
CREATE OR REPLACE VIEW inspection.c_t AS
 SELECT l1.limitid AS limit1,
    l1.id_pol AS pol1,
    l2.limitid AS limit2,
    l2.id_pol AS pol2
   FROM inspection.limites l1,
    inspection.limites l2
  WHERE st_equals(l1.geom, l2.geom) AND l1.limitid <> l2.limitid
  ORDER BY l1.id_pol;   
   

CREATE OR REPLACE VIEW inspection.vecinos_representantes AS
 SELECT DISTINCT c_t.pol1 AS predio,
    c_t.pol2 AS vecino,
    r.nombre AS nombre_vecino
   FROM inspection.c_t,
    inspection.representante r
  WHERE c_t.pol2::double precision = r.predio;    


CREATE OR REPLACE VIEW inspection.c_t AS
 SELECT l1.limitid AS limit1,
    l1.id_pol AS pol1,
    l2.limitid AS limit2,
    l2.id_pol AS pol2
   FROM inspection.limites l1,
    inspection.limites l2
  WHERE st_equals(l1.geom, l2.geom) AND l1.limitid <> l2.limitid
  ORDER BY l1.id_pol;     


CREATE OR REPLACE VIEW inspection.v_firma_l AS
 SELECT f.limitid,
    f.limitid / 100 AS predio,
    f.limitid % 100 AS limite,
    (upper(pt.first_name::text) || ' '::text) || upper(pt.last_name::text) AS nombre,
    pt.objectid AS id_party,
    f.concepto,
    f.fecha,
    f.titulo
   FROM inspection.firma_l f 
   LEFT JOIN inspection.party pt ON f.globalid::text = pt.right_id::text;  
   

CREATE OR REPLACE VIEW inspection.firma_colinda_todos AS
 SELECT c_t.limit1,
    c_t.pol1,
    c_t.limit2,
    c_t.pol2,
    fp.globalid,
    fl.titulo,
    fl.concepto,
    fl.fecha,
    fl.remarks
   FROM inspection.c_t
     JOIN inspection.firma_p fp ON c_t.pol2::double precision = fp.id
     LEFT JOIN inspection.firma_l fl ON c_t.limit2 = fl.limitid 
     

CREATE OR REPLACE VIEW inspection.v_firma_colinda_todos AS
 SELECT f.pol1 AS predio,
    f.pol2 AS predio_vecino,
    (upper(pt.first_name::text) || ' '::text) || upper(pt.last_name::text) AS nombre_vecino,
    f.titulo,
    f.concepto,
    f.fecha
   FROM inspection.firma_colinda_todos f
     LEFT JOIN inspection.party pt ON f.globalid::text = pt.right_id::text;
	 

CREATE OR REPLACE VIEW inspection.cuenta_limite
 AS
 SELECT total.limitid,
    total.total,
    nulos.nulos,
    si.si
   FROM ( SELECT firma_l.limitid,
            count(*) AS total
           FROM inspection.firma_l
          GROUP BY firma_l.limitid
          ORDER BY firma_l.limitid) total
     LEFT JOIN ( SELECT firma_l.limitid,
            count(*) AS nulos
           FROM inspection.firma_l
          WHERE firma_l.concepto IS NULL
          GROUP BY firma_l.limitid
          ORDER BY firma_l.limitid) nulos USING (limitid)
     LEFT JOIN ( SELECT firma_l.limitid,
            count(*) AS si
           FROM inspection.firma_l
          WHERE firma_l.concepto = true
          GROUP BY firma_l.limitid
          ORDER BY firma_l.limitid) si USING (limitid);


CREATE OR REPLACE VIEW inspection.muestra_limite_p AS
 SELECT cuenta_limite.limitid,
        CASE
        --    WHEN cuenta_limite.titulo = true THEN 9
            WHEN cuenta_limite.nulos = cuenta_limite.total THEN 1
            WHEN cuenta_limite.si = cuenta_limite.total THEN 3
            WHEN cuenta_limite.si IS NULL AND (cuenta_limite.total - cuenta_limite.nulos) > 0 THEN 4
            WHEN (cuenta_limite.total - cuenta_limite.nulos - cuenta_limite.si) > 0 THEN 4
            WHEN cuenta_limite.nulos IS NULL THEN 4
            ELSE 2
        END AS color
   FROM inspection.cuenta_limite;


CREATE OR REPLACE VIEW inspection.cuenta_limite_vecinos AS
 SELECT total.limit1,
    total.total,
    nulos.nulos,
    si.si,
    titulos.titulos
   FROM ( SELECT firma_colinda_todos.limit1,
            count(*) AS total
           FROM inspection.firma_colinda_todos
          GROUP BY firma_colinda_todos.limit1
          ORDER BY firma_colinda_todos.limit1) total
     LEFT JOIN ( SELECT firma_colinda_todos.limit1,
            count(*) AS nulos
           FROM inspection.firma_colinda_todos
          WHERE firma_colinda_todos.concepto IS NULL
          GROUP BY firma_colinda_todos.limit1
          ORDER BY firma_colinda_todos.limit1) nulos USING (limit1)
     LEFT JOIN ( SELECT firma_colinda_todos.limit1,
            count(*) AS si
           FROM inspection.firma_colinda_todos
          WHERE firma_colinda_todos.concepto = true
          GROUP BY firma_colinda_todos.limit1
          ORDER BY firma_colinda_todos.limit1) si USING (limit1)
     LEFT JOIN ( SELECT firma_colinda_todos.limit1,
            count(*) AS titulos
           FROM inspection.firma_colinda_todos
          WHERE firma_colinda_todos.titulo = true
          GROUP BY firma_colinda_todos.limit1
          ORDER BY firma_colinda_todos.limit1) titulos ON titulos.limit1 = total.limit1;   
	 
	 

CREATE OR REPLACE VIEW inspection.muestra_limite_v AS
 SELECT cuenta_limite_vecinos.limit1 AS limitid,
        CASE
            WHEN cuenta_limite_vecinos.titulos > 0 THEN 9
            WHEN cuenta_limite_vecinos.nulos = cuenta_limite_vecinos.total THEN 1
            WHEN cuenta_limite_vecinos.si = cuenta_limite_vecinos.total THEN 3
            WHEN cuenta_limite_vecinos.si IS NULL AND (cuenta_limite_vecinos.total - cuenta_limite_vecinos.nulos) > 0 THEN 4
            WHEN (cuenta_limite_vecinos.total - cuenta_limite_vecinos.nulos - cuenta_limite_vecinos.si) > 0 THEN 4
            WHEN cuenta_limite_vecinos.nulos IS NULL THEN 4
            ELSE 2
        END AS color
   FROM inspection.cuenta_limite_vecinos;

	 

CREATE OR REPLACE VIEW inspection.revisa_limite AS
 SELECT c_t.limit1 AS limite,
    c_t.pol1,
    vfl_1.nombre AS nombre1,
    vfl_1.concepto AS concepto1,
    c_t.pol2,
    vfl_2.nombre AS nombre2,
    vfl_2.concepto AS concepto2
   FROM inspection.c_t,
    inspection.v_firma_l vfl_1,
    inspection.v_firma_l vfl_2
  WHERE c_t.limit1 = vfl_1.limitid AND c_t.limit2 = vfl_2.limitid
  ORDER BY c_t.limit1;	 
	 
------------------------------------------------------------------------------------------
-- 3. VISTAS MATERIALIZADAS
------------------------------------------------------------------------------------------

CREATE MATERIALIZED VIEW inspection.concepto_predio_con_vecinos_view
	TABLESPACE pg_default
	AS
	 SELECT f.predio,
		f.limitid,
		f.id_party,
		vr.vecino,
		vr.nombre_vecino,
		f.concepto,
		f.fecha,
		json_build_object('type', 'Feature', 'id', l.limitid, 'geometry', st_asgeojson(l.geom)::json, 'properties', json_build_object('limitid', l.limitid)) AS geom
	   FROM inspection.v_firma_l f
		 JOIN inspection.c_t c ON f.limitid = c.limit1
		 JOIN inspection.limites l ON l.limitid = f.limitid,
		inspection.vecinos_representantes vr
	  WHERE c.pol1 = vr.predio AND c.pol2 = vr.vecino
	WITH DATA;


CREATE MATERIALIZED VIEW inspection.muestra_limite_view AS
 SELECT p.limitid,
        CASE
            WHEN p.color_p = 9 OR v.color_v = 9 THEN 9
            WHEN p.color_p = 4 OR v.color_v = 4 THEN 4
            WHEN p.color_p = 2 OR v.color_v = 2 THEN 2
            WHEN p.color_p = 3 AND v.color_v = 3 THEN 3
            WHEN p.color_p = 3 OR v.color_v = 3 THEN 2
            WHEN p.color_p = 1 AND v.color_v = 1 THEN 1
            ELSE NULL::integer
        END AS estate
   FROM ( SELECT muestra_limite_p.limitid,
            muestra_limite_p.color AS color_p
           FROM inspection.muestra_limite_p) p
     LEFT JOIN ( SELECT muestra_limite_v.limitid,
            muestra_limite_v.color AS color_v
           FROM inspection.muestra_limite_v) v USING (limitid)
  ORDER BY p.limitid;
  
------------------------------------------------------------------------------------------
-- 4. ROLES Y PERMISOS
------------------------------------------------------------------------------------------

BEGIN;

CREATE ROLE kadaster LOGIN
ENCRYPTED PASSWORD 'kadaster**'
NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;


CREATE ROLE kadaster_admin LOGIN
ENCRYPTED PASSWORD '**kadaster**'
NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION;

grant select on all tables in schema inspection to kadaster;
grant connect on database ffpdata to kadaster_admin;
grant usage on schema inspection to kadaster_admin;
grant all on all tables in schema inspection to kadaster_admin;
grant all on all sequences in schema inspection to kadaster_admin;

grant connect on database ffpdata to kadaster;
grant usage on schema inspection to kadaster;
grant all on all tables in schema inspection to kadaster;
grant all on all sequences in schema inspection to kadaster;

grant connect on database ffpdata to postgres;
grant usage on schema inspection to postgres;
grant all on all tables in schema inspection to postgres;
grant all on all sequences in schema inspection to postgres;

END;


------------------------------------------------------------------------------------------
-- 5. REFRESCAR VISTAS MATERIALIZADAS
------------------------------------------------------------------------------------------

REFRESH MATERIALIZED VIEW inspection.muestra_limite_view;
REFRESH MATERIALIZED VIEW inspection.concepto_predio_con_vecinos_view;


