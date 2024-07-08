--===========================================================================================================================
--				EXTENSIONES Y ESQUEMAS PARA EL TRABAJO DE FFP EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--			Universidad Distrital Francisco José de Caldas
--			Facultad de Ingeniería
--			aeortizd@udistrital.edu.co
--  Lugar:	Bogotá D. C. - Colombia
--  Fecha:	23-08-2020
--
--  Script Name:	ffp_step_4b_load_to_survey_Insert
--
--===========================================================================================================================
-- Extensiones y esquemas utilizados en la base de datos para FFP
-----------------------------------------------------------------------------------------------------------------------------
set search_path to load,public;
-----------------------------------------------------------------------------------------------------------------------------
insert into survey.spatialunit select * from spatialunit
	where globalid not in (select globalid from survey.spatialunit);
insert into survey.anchorpoint select * from anchorpoint
	where globalid not in (select globalid from survey.anchorpoint);
insert into survey.vertexpoint select * from vertexpoint
	where globalid not in (select globalid from survey.vertexpoint);
insert into survey.firma_l select * from firma_l
	where limitid not in (select limitid from survey.firma_l) and id_party not in (select id_party from survey.firma_l);
insert into survey.party select * from party
	where globalid not in (select globalid from survey.party);
insert into survey.party__attach select * from party__attach
	where globalid not in (select globalid from survey.party__attach);
insert into survey.partyattachment select * from partyattachment
	where globalid not in (select globalid from survey.partyattachment);
insert into survey.puntos_predio select * from puntos_predio
	where id_pol not in (select id_pol from survey.puntos_predio) and num_pto not in (select num_pto from survey.puntos_predio);
insert into survey.referenceobject select * from referenceobject
	where globalid not in (select globalid from survey.referenceobject);
insert into survey.right select * from "right"
	where globalid not in (select globalid from survey.right);
insert into survey.right__attach select * from right__attach
	where globalid not in (select globalid from survey.right__attach);
insert into survey.rightattachment select * from rightattachment
	where globalid not in (select globalid from survey.rightattachment);
insert into survey.limites select * from limites
	where limitid not in (select limitid from survey.limites);
-----------------------------------------------------------------------------------------------------------------------------
