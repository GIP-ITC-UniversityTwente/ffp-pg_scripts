--===========================================================================================================================
--			TABLAS Y FUNCIONES QUE GENERAN LOS PUNTOS PARA CADA PREDIO EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--		Universidad Distrital Francisco José de Caldas
--  Lugar:	Bogotá D. C.	Colombia
--  Fecha:	18-08-2020	08-03-2022
--
--  Script Name:	ffp_step_2_Edition
--
--===========================================================================================================================
-- NOTA: Se usan cuando los predios se han capturado como poligonos y hay que generar los puntos que los conforman
-----------------------------------------------------------------------------------------------------------------------------
set search_path to load,public;
-----------------------------------------------------------------------------------------------------------------------------
create table puntos_predio (
	pto serial not null,
	id_pol int,
	num_pto int,
	label varchar(20),
	accuracy numeric(38,8));
select AddGeometryColumn('puntos_predio','geom',(select st_srid(geom) from spatialunit limit 1),'POINT',4);
-----------------------------------------------------------------------------------------------------------------------------
select ffp_puntos_predio(objectid) from spatialunit;
create table if not exists survey.puntos_predio as select * from load.puntos_predio where 1=2;
do $insertar$
	begin
		if (select count(*) from survey.puntos_predio) <1 then
			insert into survey.puntos_predio values (0,null,null,null,null,null);
		end if;
	end;
$insertar$;
update puntos_predio set pto = (select max(pto) from survey.puntos_predio)+pto;
-----------------------------------------------------------------------------------------------------------------------------
-- Los puntos que no son "Ancla" se marcan como puntos de "Terreno" (T)
--	update puntos_predio set label = 'T' where label is null;
-----------------------------------------------------------------------------------------------------------------------------
-- se crea una copia de la tabla con los puntos originales

do $crear$
	begin
		execute 'create table puntos_predio_'||translate(current_date::varchar,'-','_')||' as select * from puntos_predio';
	end;
$crear$;
-----------------------------------------------------------------------------------------------------------------------------
delete from survey.puntos_predio where pto=0;
-----------------------------------------------------------------------------------------------------------------------------
-- Asociar a puntos_predios la información de anchorpoint y vertexpoint
-----------------------------------------------------------------------------------------------------------------------------
update puntos_predio set label='T', accuracy = vp.esrignss_h_rms
	from vertexpoint vp
	where st_equals(st_point(st_x(puntos_predio.geom),st_y(puntos_predio.geom)),st_point(st_x(vp.geom),st_y(vp.geom)))
		and puntos_predio.label is null;

update puntos_predio set label='A', accuracy = ap.esrignss_h_rms
	from anchorpoint ap
	where st_equals(st_point(st_x(puntos_predio.geom),st_y(puntos_predio.geom)),st_point(st_x(ap.geom),st_y(ap.geom)))
		and puntos_predio.label is null;

update puntos_predio set geom=st_setsrid(st_makepoint(st_x(geom),st_y(geom),st_z(geom),coalesce(accuracy,0)),
	(select st_srid(geom) from puntos_predio limit 1));
-----------------------------------------------------------------------------------------------------------------------------
set search_path to load,public;
-----------------------------------------------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------------------------------------------
-- Correct table names (wrong names generated by the geodatabase export function of ArcGIS online)
ALTER TABLE IF EXISTS partyattachment__attach RENAME TO party__attach;
ALTER TABLE IF EXISTS rightattachment__attach RENAME TO right__attach;
-----------------------------------------------------------------------------------------------------------------------------

create table if not exists survey.spatialunit as select * from load.spatialunit where 1=2;
create table if not exists inspection.spatialunit as select * from load.spatialunit where 1=2;
create table if not exists survey.right as select * from load.right where 1=2;
create table if not exists inspection.right as select * from load.right where 1=2;
create table if not exists inspection.rightattachment as select * from load.rightattachment where 1=2;
create table if not exists survey.rightattachment as select * from load.rightattachment where 1=2;
create table if not exists inspection.right__attach as select * from load.right__attach where 1=2;
create table if not exists survey.right__attach as select * from load.right__attach where 1=2;
create table if not exists inspection.party as select * from load.party where 1=2;
create table if not exists survey.party as select * from load.party where 1=2;
alter table party__attach add column la_partyid character varying;
alter table party__attach add column attachment_type character varying;
create table if not exists inspection.party__attach as select * from load.party__attach where 1=2;
create table if not exists survey.party__attach as select * from load.party__attach where 1=2;
create table if not exists inspection.partyattachment as select * from load.partyattachment where 1=2;
create table if not exists survey.partyattachment as select * from load.partyattachment where 1=2;
create table if not exists survey.puntos_predio as select * from load.puntos_predio where 1=2;
create table if not exists inspection.puntos_predio as select * from load.puntos_predio where 1=2;
create table if not exists inspection.puntos_predio as select * from load.puntos_predio where 1=2;
create table if not exists survey.ReferenceObject as select * from load.ReferenceObject where 1=2;
create table if not exists inspection.ReferenceObject as select * from load.ReferenceObject where 1=2;
create table if not exists survey.anchorpoint as select * from load.anchorpoint where 1=2;
create table if not exists inspection.anchorpoint as select * from load.anchorpoint where 1=2;
create table if not exists survey.vertexpoint as select * from load.vertexpoint where 1=2;
create table if not exists inspection.vertexpoint as select * from load.vertexpoint where 1=2;
create table if not exists survey.boundary_signature (
    party_id integer,
    globalid character varying COLLATE pg_catalog."default",
    details character varying COLLATE pg_catalog."default",
    signed_on timestamp without time zone,
    signature character varying COLLATE pg_catalog."default",
    agree_to_terms boolean,
    fingerprint bytea);
create table if not exists inspection.boundary_signature as select * from survey.boundary_signature where 1=2;
create sequence inspection.la_party_objectid_seq increment 5 start 1000;
create table if not exists inspection.la_party (
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
    CONSTRAINT la_party_globalid_uk UNIQUE (globalid));
-----------------------------------------------------------------------------------------------------------------------------
create table if not exists load.pto_ajuste (id int);
select addgeometrycolumn('load','pto_ajuste','geom',(select st_srid(geom) from load.spatialunit limit 1),'POINT',4);
create table if not exists survey.pto_ajuste as select * from load.pto_ajuste where 1=2;
create table if not exists inspection.pto_ajuste as select * from load.pto_ajuste where 1=2;
-----------------------------------------------------------------------------------------------------------------------------


-----------------------------------------------------------------------------------------------------------------------------
-- Table to store records deleted during editing
CREATE TABLE IF NOT EXISTS "dump"
(
    table_name character varying(50),
    objectid integer,
    record character varying,
    data bytea,
    deleted_on character varying(30)
);
-----------------------------------------------------------------------------------------------------------------------------


-----------------------------------------------------------------------------------------------------------------------------
-- Codelists
-----------------------------------------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS inspection.codelists;
CREATE TABLE inspection.codelist (
    objectid integer NOT NULL,
    list character varying NOT NULL,
    code integer NOT NULL,
    en character varying NOT NULL,
    es character varying NOT NULL
);

CREATE SEQUENCE inspection.codelist_objectid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE inspection.codelist_objectid_seq OWNED BY inspection.codelist.objectid;
ALTER TABLE ONLY inspection.codelist ALTER COLUMN objectid SET DEFAULT nextval('inspection.codelist_objectid_seq'::regclass);

INSERT INTO inspection.codelist VALUES (1, 'yesno', 0, 'No', 'No');
INSERT INTO inspection.codelist VALUES (2, 'yesno', 1, 'Yes', 'Si');
INSERT INTO inspection.codelist VALUES (3, 'spatialunittype', 1, 'House', 'Casa');
INSERT INTO inspection.codelist VALUES (4, 'spatialunittype', 2, 'House Lot', 'Casa Lote');
INSERT INTO inspection.codelist VALUES (5, 'spatialunittype', 3, 'Business', 'Negocio');
INSERT INTO inspection.codelist VALUES (6, 'spatialunittype', 4, 'Farm', 'Finca');
INSERT INTO inspection.codelist VALUES (7, 'spatialunittype', 0, 'Other', 'Otro');
INSERT INTO inspection.codelist VALUES (8, 'gender', 1, 'Male', 'Masculino');
INSERT INTO inspection.codelist VALUES (9, 'gender', 2, 'Female', 'Femenino');
INSERT INTO inspection.codelist VALUES (10, 'civilstatus', 1, 'Single', 'Soltero(a)');
INSERT INTO inspection.codelist VALUES (11, 'civilstatus', 2, 'Married', 'Casado(a)');
INSERT INTO inspection.codelist VALUES (12, 'civilstatus', 3, 'Living Common', 'Unión Libre');
INSERT INTO inspection.codelist VALUES (13, 'righttype', 1, 'Ownership', 'Dominio o Propiedad');
INSERT INTO inspection.codelist VALUES (14, 'righttype', 2, 'Common Ownership', 'Propiedad Comunitaria');
INSERT INTO inspection.codelist VALUES (15, 'righttype', 3, 'Tenancy', 'Arriendo');
INSERT INTO inspection.codelist VALUES (16, 'righttype', 4, 'Usufruct', 'Usufructo');
INSERT INTO inspection.codelist VALUES (17, 'righttype', 5, 'Customary', 'Consuetudinario');
INSERT INTO inspection.codelist VALUES (18, 'righttype', 6, 'Occupation', 'Ocupación');
INSERT INTO inspection.codelist VALUES (19, 'righttype', 7, 'Ownership Assumed', 'Posesión');
INSERT INTO inspection.codelist VALUES (20, 'righttype', 8, 'Superficies', 'Superficies');
INSERT INTO inspection.codelist VALUES (21, 'righttype', 9, 'Mining', 'Minero');
INSERT INTO inspection.codelist VALUES (22, 'righttype', 0, 'Unknown', 'Desconocido');
INSERT INTO inspection.codelist VALUES (23, 'righttype', 99, 'Conflict', 'Conflicto');
INSERT INTO inspection.codelist VALUES (24, 'rightsource', 1, 'Title', 'Titulo');
INSERT INTO inspection.codelist VALUES (25, 'rightsource', 2, 'Deed', 'Escritura');
INSERT INTO inspection.codelist VALUES (26, 'rightsource', 3, 'Verbal Agreement', 'Acuerdo Verbal');
INSERT INTO inspection.codelist VALUES (27, 'rightsource', 4, 'Purchase Agreement', 'Carta de Compraventa');
INSERT INTO inspection.codelist VALUES (28, 'rightsource', 5, 'Adjudication', 'Adjudicación');
INSERT INTO inspection.codelist VALUES (29, 'rightsource', 6, 'Prescription', 'Prescripción');
INSERT INTO inspection.codelist VALUES (30, 'rightsource', 7, 'Inheritance', 'Herencia');
INSERT INTO inspection.codelist VALUES (31, 'rightsource', 0, 'Other', 'Otro');
INSERT INTO inspection.codelist VALUES (32, 'landuse', 1, 'Agriculture', 'Agricultura');
INSERT INTO inspection.codelist VALUES (33, 'landuse', 2, 'Cattle Raising', 'Ganadería');
INSERT INTO inspection.codelist VALUES (34, 'landuse', 3, 'Residential', 'Residencial');
INSERT INTO inspection.codelist VALUES (35, 'landuse', 4, 'Commercial', 'Comercial');
INSERT INTO inspection.codelist VALUES (36, 'landuse', 5, 'Industrial', 'Industrial');
INSERT INTO inspection.codelist VALUES (37, 'landuse', 6, 'Conservation', 'Conservación');
INSERT INTO inspection.codelist VALUES (38, 'landuse', 7, 'Government', 'Gubernamental');
INSERT INTO inspection.codelist VALUES (39, 'landuse', 9, 'Mixed', 'Mixto');
INSERT INTO inspection.codelist VALUES (40, 'landuse', 0, 'None', 'Ninguno');
INSERT INTO inspection.codelist VALUES (41, 'rightattachment', 1, 'Title', 'Titulo');
INSERT INTO inspection.codelist VALUES (42, 'rightattachment', 2, 'Deed', 'Escritura');
INSERT INTO inspection.codelist VALUES (43, 'rightattachment', 3, 'Utility Receipt', 'Recibo Servicios Públicos');
INSERT INTO inspection.codelist VALUES (44, 'rightattachment', 4, 'Purchase Agreement', 'Carta de Compraventa');
INSERT INTO inspection.codelist VALUES (45, 'rightattachment', 5, 'Tax Receipt', 'Recibo de Impuestos');
INSERT INTO inspection.codelist VALUES (46, 'rightattachment', 6, 'Certificate of Honest Posseion', 'Certificado de Sana Posesión');
INSERT INTO inspection.codelist VALUES (47, 'rightattachment', 7, 'Certificate of Tradition and Freedom', 'Certiificado de Tradicion y Libertad');
INSERT INTO inspection.codelist VALUES (48, 'rightattachment', 0, 'Other', 'Otro');
INSERT INTO inspection.codelist VALUES (49, 'partyattachment', 1, 'ID Card Minor', 'Tarjeta de Identidad');
INSERT INTO inspection.codelist VALUES (50, 'partyattachment', 2, 'ID Card Foreigner', 'Cedula de Extranjería');
INSERT INTO inspection.codelist VALUES (51, 'partyattachment', 3, 'ID Card', 'Cedula de Ciudadanía');
INSERT INTO inspection.codelist VALUES (52, 'partyattachment', 4, 'Passport', 'Pasaporte');
INSERT INTO inspection.codelist VALUES (53, 'partyattachment', 5, 'Face Photo', 'Foto del Rostro');
INSERT INTO inspection.codelist VALUES (54, 'partyattachment', 6, 'Fingerprint', 'Huella Digital');
INSERT INTO inspection.codelist VALUES (55, 'partyattachment', 7, 'Signature', 'Firma');
INSERT INTO inspection.codelist VALUES (56, 'partyattachment', 0, 'Other', 'Otro');

SELECT pg_catalog.setval('inspection.codelist_objectid_seq', 56, true);
ALTER TABLE ONLY inspection.codelist ADD CONSTRAINT codelist_pk PRIMARY KEY (objectid);
-----------------------------------------------------------------------------------------------------------------------------
