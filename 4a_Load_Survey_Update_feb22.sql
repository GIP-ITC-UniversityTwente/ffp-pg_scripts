--===========================================================================================================================
--				EXTENSIONES Y ESQUEMAS PARA EL TRABAJO DE FFP EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--			Universidad Distrital Francisco José de Caldas
--			Facultad de Ingeniería
--			aeortizd@udistrital.edu.co
--  Lugar:	Bogotá D. C. - Colombia
--  Fecha:	23-08-2020
--===========================================================================================================================
-- Extensiones y esquemas utilizados en la base de datos para FFP
-----------------------------------------------------------------------------------------------------------------------------
set search_path to load,public;
-----------------------------------------------------------------------------------------------------------------------------


-----------------------------------------------------------------------------------------------------------------------------
create or replace function public.copia_esquema (varchar, varchar) returns void as $$
declare
begin
		drop table if exists temporal;
		execute 'create temporary table temporal as select * from '||$2||
			' where globalid in (select globalid from '||$1||'.'||$2||')';
		execute 'delete from '||$1||'.'||$2||' where globalid in (select globalid from temporal)';
		execute 'insert into '||$1||'.'||$2||' select * from temporal';
		drop table if exists temporal;
end;
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------

select copia_esquema('survey','spatialunit');
select copia_esquema('survey','anchorpoint');
select copia_esquema('survey','vertexpoint');
select copia_esquema('survey','party');
select copia_esquema('survey','party__attach');
select copia_esquema('survey','partyattachment');
select copia_esquema('survey','referenceobject');
select copia_esquema('survey','"right"');
select copia_esquema('survey','right__attach');
select copia_esquema('survey','rightattachment');

drop table if exists temporal;
create temporary table temporal as select * from firma_l
	where limitid||' '||id_party in (select limitid||' '||id_party from survey.firma_l);
delete from survey.firma_l where limitid||' '||id_party in (select limitid||' '||id_party from temporal);
insert into survey.firma_l select * from temporal;
drop table if exists temporal;

create temporary table temporal as select * from puntos_predio
	where id_pol||' '||num_pto in (select id_pol||' '||num_pto from survey.puntos_predio);
delete from survey.puntos_predio where id_pol||' '||num_pto in (select id_pol||' '||num_pto from temporal);
insert into survey.puntos_predio select * from temporal;
drop table if exists temporal;

-----------------------------------------------------------------------------------------------------------------------------
