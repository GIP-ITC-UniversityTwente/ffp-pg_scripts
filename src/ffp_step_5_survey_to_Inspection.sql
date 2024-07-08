--===========================================================================================================================
--				EXTENSIONES Y ESQUEMAS PARA EL TRABAJO DE FFP EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--			Universidad Distrital Francisco José de Caldas
--			Facultad de Ingeniería
--			aeortizd@udistrital.edu.co
--  Lugar:	Bogotá D. C. - Colombia
--  Fecha:	25-08-2020
--
--  Script Name:	ffp_step_5_survey_to_Inspection
--
--===========================================================================================================================
-- Cargue de información en el esquema Inspection a partir de la información del esquema Load en la base de datos para FFP
-----------------------------------------------------------------------------------------------------------------------------
set search_path to survey,public;
-----------------------------------------------------------------------------------------------------------------------------
-- Tabla para seleccionar los predios que se copiarán a Inspection a partir de Survey
create table if not exists survey.load_inspection (objectid int);
-----------------------------------------------------------------------------------------------------------------------------
create temporary table t_spatialunit as select * from spatialunit where 1=2;
create temporary table t_anchorpoint as select * from anchorpoint where 1=2;
create temporary table t_vertexpoint as select * from vertexpoint where 1=2;
create temporary table t_firma_l as select * from firma_l where 1=2;
create temporary table t_party as select * from party where 1=2;
create temporary table t_party__attach as select * from party__attach where 1=2;
create temporary table t_partyattachment as select * from partyattachment where 1=2;
create temporary table t_puntos_predio as select * from puntos_predio where 1=2;
create temporary table t_referenceobject as select * from referenceobject where 1=2;
create temporary table t_right as select * from "right" where 1=2;
create temporary table t_right__attach as select * from right__attach where 1=2;
create temporary table t_rightattachment as select * from rightattachment where 1=2;
create temporary table t_limites as select * from limites where 1=2;
-----------------------------------------------------------------------------------------------------------------------------

	insert into t_spatialunit select * from spatialunit;
	insert into t_anchorpoint select * from anchorpoint;
	insert into t_vertexpoint select * from vertexpoint;
	insert into t_firma_l select * from firma_l;
	insert into t_party select * from party;
	insert into t_party__attach select * from party__attach;
	insert into t_partyattachment select * from partyattachment;
	insert into t_right select * from "right";
	insert into t_right__attach select * from right__attach;
	insert into t_rightattachment select * from rightattachment;
	insert into t_puntos_predio select * from puntos_predio;
	insert into t_limites select * from limites;
	insert into t_referenceobject select * from referenceobject;
-----------------------------------------------------------------------------------------------------------------------------
insert into inspection.spatialunit select * from t_spatialunit
	where globalid not in (select globalid from inspection.spatialunit);
insert into inspection.anchorpoint select * from t_anchorpoint
	where globalid not in (select globalid from inspection.anchorpoint);
insert into inspection.vertexpoint select * from t_vertexpoint
	where globalid not in (select globalid from inspection.vertexpoint);
insert into inspection.firma_l select * from t_firma_l
	where limitid||' '||id_party not in (select limitid||' '||id_party from inspection.firma_l);
insert into inspection.party select * from t_party
	where globalid not in (select globalid from inspection.party);
insert into inspection.party__attach select * from t_party__attach
	where globalid not in (select globalid from inspection.party__attach);
insert into inspection.partyattachment select * from t_partyattachment
	where globalid not in (select globalid from inspection.partyattachment);
insert into inspection.puntos_predio select * from t_puntos_predio
	where id_pol||' '||num_pto not in (select id_pol||' '||num_pto from inspection.puntos_predio);
insert into inspection.referenceobject select * from t_referenceobject
	where globalid not in (select globalid from inspection.referenceobject);
insert into inspection.right select * from t_right
	where globalid not in (select globalid from inspection.right);
insert into inspection.right__attach select * from t_right__attach
	where globalid not in (select globalid from inspection.right__attach);
insert into inspection.rightattachment select * from t_rightattachment
	where globalid not in (select globalid from inspection.rightattachment);
insert into inspection.limites select * from t_limites
	where limitid not in (select limitid from inspection.limites);
-----------------------------------------------------------------------------------------------------------------------------


-----------------------------------------------------------------------------------------------------------------------------
drop table if exists t_spatialunit;
drop table if exists t_anchorpoint;
drop table if exists t_vertexpoint;
drop table if exists t_firma_l;
drop table if exists t_party;
drop table if exists t_party__attach;
drop table if exists t_partyattachment;
drop table if exists t_puntos_predio;
drop table if exists t_referenceobject;
drop table if exists t_right;
drop table if exists t_right__attach;
drop table if exists t_rightattachment;
-----------------------------------------------------------------------------------------------------------------------------