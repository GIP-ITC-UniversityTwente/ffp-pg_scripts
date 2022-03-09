--===========================================================================================================================
--			TABLAS Y FUNCIONES QUE GENERAN LOS PUNTOS PARA CADA PREDIO EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--		Universidad Distrital Francisco José de Caldas
--  Lugar:	Bogotá D. C.	Colombia
--  Fecha:	18-08-2020	08-03-2022
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
update puntos_predio set geom=st_setsrid(st_makepoint(st_x(geom),st_y(geom),st_z(geom),accuracy),
		(select st_srid(geom) from puntos_predio limit 1));
-----------------------------------------------------------------------------------------------------------------------------
set search_path to load,public;
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
