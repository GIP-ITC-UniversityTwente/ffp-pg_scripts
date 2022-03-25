--===========================================================================================================================
--				EXTENSIONES Y ESQUEMAS PARA EL TRABAJO DE FFP EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--			Universidad Distrital Francisco José de Caldas
--			Facultad de Ingeniería
--			aeortizd@udistrital.edu.co
--  Lugar:	Bogotá D. C. - Colombia
--  Fecha:	25-08-2020	08-03-2022
--===========================================================================================================================
-- Definición de las áreas de conflicto entre predios en la base de datos para FFP
-----------------------------------------------------------------------------------------------------------------------------
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
