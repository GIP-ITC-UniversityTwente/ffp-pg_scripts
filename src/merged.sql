-- "Merged Scripts"
--===========================================================================================================================
--				EXTENSIONES Y ESQUEMAS PARA EL TRABAJO DE FFP EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--			Universidad Distrital Francisco José de Caldas
--			Facultad de Ingeniería
--			aeortizd@udistrital.edu.co
--  Lugar:	Bogotá D. C. - Colombia
--  Fecha:	25-08-2020	08-03-2022
--
--  Script Name:	ffp_step_3_Limits
--
--===========================================================================================================================
-- Definición de las áreas de conflicto entre predios en la base de datos para FFP
-----------------------------------------------------------------------------------------------------------------------------
--
set search_path to load,public;
-----------------------------------------------------------------------------------------------------------------------------
-- Adicionado 28/10/2021
select ffp_renumera_ptos ();
with a as
(select id_pol,min(num_pto) min
	from puntos_predio
	group by id_pol order by id_pol)
select ffp_renum_ancles(a.id_pol) from a, puntos_predio p
	where p.id_pol=a.id_pol and min=p.num_pto and label <> 'A'
	order by a.id_pol;
-----------------------------------------------------------------------------------------------------------------------------
drop table if exists conflictos;
create table conflictos as
	select p1.objectid id_p1,p2.objectid id_p2,st_force3d(st_difference(p1.geom,st_difference(p1.geom,p2.geom))) geom
		from spatialunit p1, spatialunit p2
		where st_intersects(p1.geom,p2.geom) and p1.objectid <> p2.objectid  and
		st_area(st_transform(st_intersection(p1.geom,p2.geom),(select s_id from ffp_parameters)))>0;
delete from conflictos where id_p1 > id_p2;
delete from conflictos where st_area(st_transform(geom,(select s_id from ffp_parameters)))<1;
-- select * from conflictos;
drop table if exists spatialunit_conflicts;
create table spatialunit_conflicts as
	select objectid, st_force3d(geom) as geom from spatialunit where objectid in
		(select distinct * from (select id_p1 from conflictos union select id_p2 from conflictos) a);
select * from spatialunit_conflicts;
do $conf$
	declare
		s record;
		c record;
	begin
		for s in select * from spatialunit_conflicts loop
			for c in select * from conflictos loop
				update spatialunit_conflicts set geom = st_force3d(st_difference(spatialunit_conflicts.geom, conflictos.geom))
					from conflictos
					where spatialunit_conflicts.objectid=s.objectid  and conflictos.id_p1=c.id_p1;
			end loop;
		end loop;
	end;
$conf$;
-- select * from spatialunit_conflicts;
-----------------------------------------------------------------------------------------------------------------------------
create table spatialunit_back as select * from spatialunit;
update spatialunit set geom = st_multi(s.geom) from spatialunit_conflicts s
	where spatialunit.objectid = s.objectid;
alter table conflictos add column num serial not null;
update conflictos set num=num+(select max(objectid) from spatialunit);
do $inr_conf$
	declare
		r record;
	begin
		for r in select * from conflictos loop
			insert into spatialunit (objectid, geom, spatialunit_name, globalid, landuse, survey_unit)
				select num,st_force3d(st_multi(c.geom)),'CONFLICTO','{'||(select upper(cast((select uuid_generate_v4()) as varchar)))||'}',0,''
					from conflictos c where r.id_p1=c.id_p1 and r.id_p2=c.id_p2;
		end loop;
	end;
$inr_conf$;
-- select objectid,globalid from spatialunit;
-----------------------------------------------------------------------------------------------------------------------------
drop table if exists t_r;
create temporary table t_r (n serial not null, globalid varchar,spatialunit_id varchar,description varchar,objectid_su int);
insert into t_r (globalid,spatialunit_id,description,objectid_su)
	select null, (select globalid from spatialunit where objectid=num), 'CONFLICTO',num
		from conflictos;
-- select * from t_r;
do $gid$
	declare
		r record;
	begin
		for r in select * from t_r loop
			update t_r set globalid='{'||(select upper(cast((select uuid_generate_v4()) as varchar)))||'}'
				where t_r.n=r.n;
		end loop;
	end;
$gid$;
update t_r set n=n+(select max(objectid) from "right");
-- select * from t_r;
insert into "right" (objectid,globalid,spatialunit_id,description,right_type)
	select n,globalid,spatialunit_id,description,99 from t_r;
drop table if exists t_pt;
create temporary table t_pt as
	select distinct pt.*,c.num objectid_su from "right" r, party pt, spatialunit su,
		(select distinct * from (select id_p1 id_p,num from conflictos union select id_p2 id_p,num from conflictos) t1) c
		where r.globalid=pt.right_id and su.globalid=r.spatialunit_id
			and  c.id_p=su.objectid;
update t_pt set right_id = t2.globalid
	from (select su.objectid, r.globalid from spatialunit su, "right" r
			where su.globalid=r.spatialunit_id and lower(r.description)='conflicto') t2
		where t2.objectid=t_pt.objectid_su;
do $id$
	declare
		r record;
	begin
		for r in select * from t_pt loop
			update t_pt set globalid='{'||(select upper(cast((select uuid_generate_v4()) as varchar)))||'}'
				where t_pt.objectid=r.objectid;
		end loop;
	end;
$id$;
-- select * from t_pt;
alter table t_pt add column n serial not null;
update t_pt set objectid=n+(select max(objectid) from party);
alter table t_pt drop column n; alter table t_pt drop column objectid_su;
insert into party select * from t_pt;
-----------------------------------------------------------------------------------------------------------------------------
create schema work_area;
set search_path to work_area,public;
create table spatialunit as select * from load.spatialunit where objectid in
	(select id_p1 from load.conflictos union select id_p2 from load.conflictos union select num from load.conflictos);
create table puntos_predio as select * from load.puntos_predio where 1=2;
select ffp_puntos_predio(objectid) from spatialunit;
update puntos_predio set label= pp.label, accuracy=pp.accuracy from load.puntos_predio pp
	where st_equals(puntos_predio.geom,pp.geom); -- and puntos_predio.id_pol=pp.id_pol;
select puntos_predio.* from puntos_predio, load.puntos_predio pp
	where st_equals(puntos_predio.geom,pp.geom) and puntos_predio.id_pol=pp.id_pol;
update puntos_predio set label='T' where label is null;
alter table puntos_predio add column n serial not null;
update puntos_predio set pto=n+(select max(pto) from load.puntos_predio);
alter table puntos_predio drop column n;
with a as
(select id_pol,min(num_pto) min
	from puntos_predio 	group by id_pol order by id_pol)
select ffp_renum_ancles(a.id_pol) from a, puntos_predio p
	where p.id_pol=a.id_pol and min=p.num_pto and label <> 'A'
	order by a.id_pol;
delete from load.puntos_predio where id_pol in (select id_pol from puntos_predio);
insert into load.puntos_predio select * from puntos_predio;
drop table spatialunit; drop table puntos_predio;
set search_path to load,public;
drop schema work_area;
update puntos_predio set label=pp.label from puntos_predio pp
	where puntos_predio.pto<>pp.pto and st_equals(puntos_predio.geom,pp.geom)
		and puntos_predio.id_pol in (select num from load.conflictos);
select ffp_renumera_ptos ();
with a as
(select id_pol,min(num_pto) min
	from puntos_predio
	group by id_pol order by id_pol)
select ffp_renum_ancles(a.id_pol) from a, puntos_predio p
	where p.id_pol=a.id_pol and min=p.num_pto and label <> 'A'
	order by a.id_pol;
--===========================================================================================================================
--			PROCESO DE CREACIÓN DE LIMITES EB LA BASE DE DATOS PARA FFP
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--			Universidad Distrital Francisco José de Caldas
--			Facultad de Ingeniería
--			aeortizd@udistrital.edu.co
--  Lugar:	Bogotá D. C.	Colombia
--  Fecha:	18-08-2020
--===========================================================================================================================
-- Funciones para la creación de los límites en la base de datos para FFP Versión 9
-----------------------------------------------------------------------------------------------------------------------------
set search_path to load,public;
-----------------------------------------------------------------------------------------------------------------------------
create table if not exists limits (
	limitid int,
	id_pol int,
	seq_limit int,
	ancla1 int,
	ancla2 int);
select AddGeometryColumn('limits','geom',(select st_srid(geom) from spatialunit limit 1),'LINESTRING',3);
create table if not exists limites as select * from limits where 1=2;
-----------------------------------------------------------------------------------------------------------------------------
select ffp_limites();
-----------------------------------------------------------------------------------------------------------------------------
-- Funciones y vistas para el proceso de visualización y firmas de los límites
-----------------------------------------------------------------------------------------------------------------------------
create table firma_l as
	select limitid, r.GlobalID,pt.objectid id_party
		from spatialunit p left outer join "right" r on (p.GlobalID = r.spatialunit_ID)
		left outer join Party pt on (r.GlobalID = pt.right_ID) inner join limites l on (p.objectid = l.id_pol)
		order by p.objectid, limitid;
alter table firma_l add column concepto boolean;
alter table firma_l add column fecha date;
alter table firma_l add column titulo boolean default false;
alter table firma_l add column conflicto boolean default false;
alter table firma_l add column remarks varchar;
create or replace view colinda as
	select distinct	case when l1.limitid < l2.limitid then l1.limitid  else l2.limitid end limit1,
			case when l1.limitid < l2.limitid then l1.id_pol  else l2.id_pol end pol1,
			case when l1.limitid < l2.limitid then l2.limitid  else l1.limitid end limit2,
			case when l1.limitid < l2.limitid then l2.id_pol  else l1.id_pol end pol2
		from limites l1, limites l2
		where (st_equals(l1.geom, l2.geom)) and (l1.limitid <> l2.limitid)
		order by pol1;
update firma_l set conflicto=true where limitid in
	(select distinct * from (
		select limitid from limites, conflictos c
			where id_pol = num
		union
		select limit1 from colinda col, conflictos con
			where (pol1=num or pol2=num) and (pol1 = id_p1 or pol2 = id_p1 or pol1 = id_p2 or pol2 = id_p2)
		union
		select limit2 from colinda col, conflictos con
			where (pol1=num or pol2=num) and (pol1 = id_p1 or pol2 = id_p1 or pol1 = id_p2 or pol2 = id_p2)) t2);
-----------------------------------------------------------------------------------------------------------------------------
-- Vistas
CREATE OR REPLACE FUNCTION public.ffp_limits_views() returns void as $$
	declare
	begin
		create or replace view v_firma_l as
			select limitid,limitid/100 predio, limitid%100 limite, upper(first_name)||' '||upper(last_name) nombre,
					pt.objectid id_party, concepto, fecha, titulo, remarks
				from firma_l f left outer join Party pt on (f.GlobalID = pt.right_ID) and f.id_party=pt.objectid;
		create or replace view firma_p as
			select distinct trunc(limitid/100) id, GlobalID, titulo from firma_l;
		create or replace view v_firma_p as
			select f.id predio,upper(first_name)||' '||upper(last_name) nombre, titulo
				from firma_p f left outer join Party pt on (f.GlobalID = pt.right_ID);
		create or replace view c_t as
			select l1.limitid limit1, l1.id_pol pol1, l2.limitid limit2, l2.id_pol pol2
				from limites l1, limites l2
				where (st_equals(l1.geom, l2.geom)) and (l1.limitid <> l2.limitid)
				order by pol1;
		create or replace view firma_colinda_todos as
			select c_t.*,fp.GlobalID,fl.id_party, fl.titulo, fl.concepto, fl.fecha, fl.conflicto from
				c_t inner join firma_p fp on (c_t.pol2 = fp.id)
				left join firma_l fl on (c_t.limit2 = fl.limitid and fp.GlobalID = fl.GlobalID);
		create or replace view v_firma_colinda_todos as
			select pol1 predio, pol2 predio_vecino, upper(first_name)||' '||upper(last_name) nombre_vecino, concepto, fecha
				from firma_colinda_todos f left outer join Party pt on (f.GlobalID = pt.right_ID and f.id_party = pt.objectid);
		create or replace view representante as
			select predio, min(nombre) nombre from v_firma_p
				group by predio order by predio;
		create or replace view vecinos_representantes as
			select distinct pol1 predio, pol2 vecino, nombre nombre_vecino from c_t, representante r
				where pol2=predio;
		create or replace view cuenta_limite as
			select limitid,coalesce(total,0) total,coalesce(nulos,0) nulos,coalesce(si,0) si,titulo,conflicto from
			( select limitid, count(*) total from firma_l group by limitid order by limitid ) total natural left join
			( select limitid, count(*) nulos from firma_l where concepto is null group by limitid order by limitid ) nulos natural left join
			( select limitid, count(*) si from firma_l where concepto = true group by limitid order by limitid ) si natural left join
			(select distinct limitid, titulo from firma_l) titulo natural left join (select distinct limitid, conflicto from firma_l) conflicto;
		create or replace view muestra_limite_p as
			select limitid,
				 case when titulo = true then 9
					when conflicto = true and si = total then 6
					when conflicto = true and total-nulos-si > 0  then 7
					when conflicto and si > 0 then 5
					when conflicto = true then 8
					when nulos = total then 1
					when si = total then 3
					when si is null and total-nulos > 0 then 4
					when total-nulos-si > 0 then 4
					when nulos is null then 4
					else 2
				 end color
				from cuenta_limite;
		create or replace view cuenta_limite_vecinos as
			select limit1,coalesce(total,0) total,coalesce(nulos,0) nulos,coalesce(si,0) si,titulo,conflicto from
			(select limit1, count(*) total from firma_colinda_todos group by limit1 order by limit1) total natural left join
			(select limit1, count(*) nulos from firma_colinda_todos where concepto is null group by limit1 order by limit1) nulos  natural left join
			(select limit1, count(*) si from firma_colinda_todos where concepto = true group by limit1 order by limit1) si natural left join
			(select distinct limit1, titulo from firma_colinda_todos) titulos natural left join
			(select distinct limit1, conflicto from firma_colinda_todos) conflicto;
		create or replace view muestra_limite_v as
			select limit1 limitid,
				 case 	when titulo then 9
					when conflicto = true and si = total then 6
					when conflicto = true and total-nulos-si > 0  then 7
					when conflicto = true and si > 0 then 5
					when conflicto = true then 8
					when nulos = total then 1
					when si = total then 3
					when si is null and total-nulos > 0 then 4
					when total-nulos-si > 0 then 4
					when nulos is null then 4
					else 2
				 end color
				from cuenta_limite_vecinos;
		-- (1- Sin conceptos  2- Faltan conceptos  3- Todos los conceptos True  4- Algún concepto False  9- Tiene título)
		-- (5- Conflicto pero faltan conceptos  6- Conflicto pero todos aprobados 7- Conflicto con algún concepto falso )
		create or replace view muestra_limite as
			select limitid,
				case 	when color_p = 9 or color_v = 9 then 9
					when color_p = 7 or color_v = 7 then 7
					when color_p = 4 and color_v > 4  then 7
					when color_p > 4 and color_v = 4 then 7
					when color_p = 6 and color_v = 3 then 6
					when color_p = 6 and color_v = 1 then 5
					when color_p = 4 or color_v = 4 then 4
					when color_p = 5 or color_v = 5 then 5
					when color_p = 6 and color_v = 6 then 6
					when color_p = 2 and color_v = 6 then 5
					when color_p = 6 and color_v = 2 then 5
					when color_p = 6 and color_v = 8 then 5
					when color_p = 8 and color_v = 6 then 5
					when color_p = 2 and color_v = 8 then 5
					when color_p = 2 or color_v = 2 then 2
					when color_p = 3 and color_v = 3 then 3
					when color_p = 3 and color_v = 6 then 6
					when color_p = 3 and color_v = 8 then 5
					when color_p = 8 and color_v = 3 then 5
					when color_p = 3 or color_v = 3 then 2
					when color_p = 1 and color_v = 1 then 1
					when color_p = 1 and color_v = 8 then 1
					when color_p = 8 and color_v = 1 then 1
					when color_p = 1 and color_v = 6 then 5
					when color_p = 8 and color_v = 8 then 1
				end estate
				from
				(select limitid, color color_p from muestra_limite_p) p
				natural left join
				(select limitid, color color_v from muestra_limite_v) v
				order by limitid;
		create or replace view concepto_predio_con_vecinos as
			select f.predio,f.limitid,id_party,vr.vecino,nombre_vecino,concepto,fecha,json_build_object(
					'type', 'Feature','id', l.limitid, 'geometry', ST_AsGeoJSON(geom)::json, 'properties', json_build_object('limitid',
					l.limitid)) geom, remarks
				from v_firma_l f inner join c_t c on (f.limitid = c.limit1) inner join limites l on (l.limitid=f.limitid), vecinos_representantes vr
				where pol1 = vr.predio and pol2 = vr.vecino;
		create or replace view revisa_limite as
			select c_t.limit1 limite, c_t.pol1, vfl_1.nombre nombre1, vfl_1.concepto concepto1,
				c_t.limit2 limite2, c_t.pol2, vfl_2.nombre nombre2, vfl_2.concepto concepto2
				from c_t,v_firma_l vfl_1, v_firma_l vfl_2
				where c_t.limit1=vfl_1.limitid and c_t.limit2=vfl_2.limitid
				order by c_t.limit1;
	end;
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
select ffp_limits_views();
-----------------------------------------------------------------------------------------------------------------------------
-- Crear la tablas en los otros esquemas si no existen
-----------------------------------------------------------------------------------------------------------------------------
create table if not exists survey.limites as select * from load.limites where 1=2;
create table if not exists inspection.limites as select * from load.limites where 1=2;
create table if not exists survey.limits as select * from load.limits where 1=2;
create table if not exists inspection.limits as select * from load.limits where 1=2;
create table if not exists survey.firma_l as select * from load.firma_l where 1=2;
create table if not exists inspection.firma_l as select * from load.firma_l where 1=2;
-----------------------------------------------------------------------------------------------------------------------------
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
--  Script Name:	ffp_step_4a_load_to_survey_Update
--
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

-- ---
-- Code to generate required DB components for the public inspection app 3.2.5
-- ---
--
--  Script Name:	app_init
--

	SET search_path = public;

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
			LEFT JOIN party AS p ON f.globalid::text = p.right_id::text AND p.objectid = f.id_party;
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

--
--  Script Name:	physical_ids
--

  SET search_path = inspection;
	ALTER TABLE spatialunit
    ADD COLUMN phy_ids character varying;
	UPDATE spatialunit
	SET phy_ids = physical_id;
	UPDATE spatialunit
	SET physical_id = null;
	ALTER TABLE spatialunit
	ALTER COLUMN physical_id TYPE text[] USING physical_id::text[];
	UPDATE spatialunit
	SET physical_id = array[split_part(replace(rtrim(replace(phy_ids, E'\n', ' ' )), ' ', ','),',',1),
                            split_part(replace(rtrim(replace(phy_ids, E'\n', ' ' )), ' ', ','),',',2),
                            split_part(replace(rtrim(replace(phy_ids, E'\n', ' ' )), ' ', ','),',',3)];
	UPDATE spatialunit
	SET physical_id = array_remove(physical_id, '');
	UPDATE spatialunit
	SET physical_id = array_remove(physical_id, null);
	ALTER TABLE spatialunit
	DROP COLUMN phy_ids;

