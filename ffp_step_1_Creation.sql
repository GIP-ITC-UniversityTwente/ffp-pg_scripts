--===========================================================================================================================
--				EXTENSIONES Y ESQUEMAS PARA EL TRABAJO DE FFP EN LA BASE DE DATOS
--===========================================================================================================================
--  Autor:	Alvaro Enrique Ortiz Dávila
--			Universidad Distrital Francisco José de Caldas
--			Facultad de Ingeniería
--  Lugar:	Bogotá D. C. - Colombia
--  Fecha:	18-08-2020	07-03-2022
--===========================================================================================================================
-- Extensiones y esquemas utilizados en la base de datos para FFP
-----------------------------------------------------------------------------------------------------------------------------
set search_path to public;
create extension if not exists postgis;
create extension if not exists postgis_topology;
create extension if not exists "uuid-ossp";
create extension if not exists tablefunc;
create schema if not exists survey;
create schema if not exists load;
create schema if not exists inspection;
drop table if exists public.ffp_parameters;
create table public.ffp_parameters (s_id int);

INSERT INTO spatial_ref_sys (srid, auth_name, auth_srid, proj4text, srtext)
VALUES (9377, 'EPSG', 9377,
  '+proj=tmerc +lat_0=4.596200416666666 +lon_0=-74.07750791666666 +k=1 +x_0=1000000 +y_0=1000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs ',
  'PROJCS["MAGNA-SIRGAS / Origen-Nacional", GEOGCS["MAGNA-SIRGAS", DATUM["Marco_Geocentrico_Nacional_de_Referencia", SPHEROID["GRS 1980",6378137,298.257222101, AUTHORITY["EPSG","7019"]], TOWGS84[0,0,0,0,0,0,0], AUTHORITY["EPSG","6686"]], PRIMEM["Greenwich",0, AUTHORITY["EPSG","8901"]], UNIT["degree",0.0174532925199433, AUTHORITY["EPSG","9122"]], AUTHORITY["EPSG","4686"]], PROJECTION["Transverse_Mercator"], PARAMETER["latitude_of_origin",4.0], PARAMETER["central_meridian",-73.0], PARAMETER["scale_factor",0.9992], PARAMETER["false_easting",5000000], PARAMETER["false_northing",2000000], UNIT["metre",1, AUTHORITY["EPSG","9001"]], AUTHORITY["EPSG","9377"]]')
ON CONFLICT (srid) DO NOTHING;
insert into public.ffp_parameters values (9377);

-----------------------------------------------------------------------------------------------------------------------------
set search_path to load,public;
-----------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ffp_puntos_predio(integer) returns integer as $$
declare
	i integer := 1;
	r record;
begin
	drop table if exists vpoints;
	create temporary table vpoints as
		select (st_dumppoints(geom)).path[3],
			(st_dumppoints(geom)).geom
			 from spatialunit
			 where objectid=$1;
	alter table vpoints add column id serial not null;
	for r in select * from vpoints loop
		if i<(select count(*) from vpoints) then
			insert into puntos_predio (id_pol,num_pto,label,geom) values
				($1,i,null,(select st_force4d(geom) from vpoints where id=i));
		end if;
		i := i + 1;
	end loop;

	return i-1;
end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------
-- Funciones para marcar puntos como "Ancla" (A)
-----------------------------------------------------------------------------------------------------------------------------
	-- Marca un punto como Ancla (A), ingresando el id del polígono y el número de punto dentro del polígono
	--	(id_pol y num_pto de la tabla puntos_predio)

	CREATE OR REPLACE FUNCTION public.ffp_marca_ancla(integer, integer) returns text as $$
		declare
		begin
			update puntos_predio set label = 'A'
				where id_pol = $1 and num_pto = $2;
			return 'Punto '||$2||' del predio '||$1||' actualizado a punto de Ancla';
		end
	$$language plpgsql;
	---------------------------------------------------------------------------------------------------------------------
	-- Marca un punto como Ancla (A), ingresando el id del punto (campo pto de la tabla puntos_predio)

	CREATE OR REPLACE FUNCTION public.ffp_marca_ancla(integer) returns text as $$
		declare
		begin
			update puntos_predio set label = 'A'
				where pto = $1;
			return 'Punto '||$1||' actualizado a punto de Ancla';
		end
	$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función para crear y recuperar una copia de la tabla puntos_predios. Puede ser útil durante el proceso de edición de predios
-----------------------------------------------------------------------------------------------------------------------------
	CREATE OR REPLACE FUNCTION public.ffp_copia_puntos_predios () returns text as $$
		declare
		begin
			drop table if exists spatialunit_bck;
			create table spatialunit_bck as select * from spatialunit;
			drop table if exists puntos_predio_bck;
			create table puntos_predio_bck as select * from puntos_predio;
			return 'Copia de los puntos de los predios realizada con exito !';
		end
	$$language plpgsql;
	---------------------------------------------------------------------------------------------------------------------
	CREATE OR REPLACE FUNCTION public.ffp_recupera_puntos_predio () returns text as $$
		declare
		begin
			delete from spatialunit;
			insert into spatialunit select * from spatialunit_bck;
			delete from puntos_predio;
			insert into puntos_predio select * from puntos_predio_bck;
			return 'Recuperación de los puntos de los predios realizada con exito !';
		end
	$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función para cambiar de sistema de referencia (SRID)

CREATE OR REPLACE FUNCTION public.ffp_srid(varchar) returns text as $$
	declare
	begin
		drop table if exists public.ffp_parameters;
		create table public.ffp_parameters(s_id int);
		if lower($1) = 'colombia' then insert into public.ffp_parameters (s_id) values (3116); end if;
		if lower($1) = 'netherlands' then insert into public.ffp_parameters (s_id) values (28992); end if;
		if lower($1) = 'holanda' then insert into public.ffp_parameters (s_id) values (28992); end if;
		return 'El SRID de transformación a coordenadas planas del proyecto se ajustó a '||upper($1);
	end;
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Funciones para determinar el punto medio cuando se reciben tres o dos puntos
-----------------------------------------------------------------------------------------------------------------------------
-- Calcula el punto medio cuando se reciben tres puntos

	CREATE OR REPLACE FUNCTION public.ffp_pto_medio (geometry, geometry, geometry) returns geometry as $$
	declare
		x1 real; y1 real; x2 real; y2 real; x3 real; y3 real;
		b_x real; b_y real; bp_x real; bp_y real;
		dx1 real; dy1 real; dx2 real; dy2 real; dx3 real; dy3 real;
		dp1 real; dp2 real; dp3 real;
		p1x real; p1y real; p2x real; p2y real; p3x real; p3y real;
		porc1 real; porc2 real; porc3 real; m1 real; m2 real; m3 real;
		j integer:=1;
		sr_id int;
		begin
			sr_id:= (select s_id from ffp_parameters);
			x1:= (select st_x(st_transform($1,sr_id))); y1:= (select st_y(st_transform($1,sr_id)));
			x2:= (select st_x(st_transform($2,sr_id))); y2:= (select st_y(st_transform($2,sr_id)));
			x3:= (select st_x(st_transform($3,sr_id))); y3:= (select st_y(st_transform($3,sr_id)));
			b_x:= (x1+x2+x3)/3; b_y:= (y1+y2+y3)/3;
			dx1:= b_x-x1; dy1:= b_y-y1; dx2:= b_x-x2; dy2:= b_y-y2; dx3:= b_x-x3; dy3:= b_y-y3;
			dp1:= |/((dx1^2)+(dy1^2)); dp2:= |/((dx2^2)+(dy2^2)); dp3:= |/((dx3^2)+(dy3^2));
			m1:= (select st_m(st_transform($1,sr_id))); m2:= (select st_m(st_transform($2,sr_id))); m3:= (select st_m(st_transform($3,sr_id)));
			if dp1 <= 0.1 then porc1:=0;
				else if m1>dp1 then porc1:=1; else porc1:= m1/dp1; end if; end if;
			if dp2 <= 0.1 then porc2:=0;
				else if m2>dp2 then porc2:=1; else porc2:= m2/dp2; end if; end if;
			if dp3 <= 0.1 then porc3:=0;
				else if m3>dp3 then porc3:=1; else porc3:= m3/dp3; end if; end if;
			p1x:= x1+(dx1*porc1);p1y:= y1+(dy1*porc1);p2x:= x2+(dx2*porc2);p2y:= y2+(dy2*porc2);p3x:= x3+(dx3*porc3);p3y:= y3+(dy3*porc3);
			bp_x:= (p1x+p2x+p3x)/3; bp_y:= (p1y+p2y+p3y)/3;
			return (SELECT st_transform(ST_SetSRID(ST_Point(bp_x, bp_y),sr_id),(select st_srid(geom) from puntos_predio limit 1)));
		end
	$$language plpgsql;
	---------------------------------------------------------------------------------------------------------------------
	-- Calcula el punto medio cuando se reciben tres puntos y un valor de confianza para los tres puntos

	CREATE OR REPLACE FUNCTION public.ffp_pto_medio (geometry, geometry, geometry, int) returns geometry as $$
	declare
		x1 real; y1 real; x2 real; y2 real; x3 real; y3 real;
		b_x real; b_y real; bp_x real; bp_y real;
		dx1 real; dy1 real; dx2 real; dy2 real; dx3 real; dy3 real;
		dp1 real; dp2 real; dp3 real;
		p1x real; p1y real; p2x real; p2y real; p3x real; p3y real;
		porc1 real; porc2 real; porc3 real; m1 real; m2 real; m3 real;
		j integer:=1;
		sr_id int;
		begin
			sr_id:= (select s_id from ffp_parameters);
			x1:= (select st_x(st_transform($1,sr_id))); y1:= (select st_y(st_transform($1,sr_id)));
			x2:= (select st_x(st_transform($2,sr_id))); y2:= (select st_y(st_transform($2,sr_id)));
			x3:= (select st_x(st_transform($3,sr_id))); y3:= (select st_y(st_transform($3,sr_id)));
			b_x:= (x1+x2+x3)/3; b_y:= (y1+y2+y3)/3;
			dx1:= b_x-x1; dy1:= b_y-y1; dx2:= b_x-x2; dy2:= b_y-y2; dx3:= b_x-x3; dy3:= b_y-y3;
			dp1:= |/((dx1^2)+(dy1^2)); dp2:= |/((dx2^2)+(dy2^2)); dp3:= |/((dx3^2)+(dy3^2));
			m1:= (select st_m(st_transform($1,sr_id))); m2:= (select st_m(st_transform($2,sr_id))); m3:= (select st_m(st_transform($3,sr_id)));
			if dp1 <= 0.1 then porc1:=0;
				else if (m1*$4)>dp1 then porc1:=1; else porc1:= (m1*$4)/dp1; end if; end if;
			if dp2 <= 0.1 then porc2:=0;
				else if (m2*$4)>dp2 then porc2:=1; else porc2:= (m2*$4)/dp2; end if; end if;
			if dp3 <= 0.1 then porc3:=0;
				else if (m3*$4)>dp3 then porc3:=1; else porc3:= (m3*$4)/dp3; end if; end if;
			p1x:= x1+(dx1*porc1);p1y:= y1+(dy1*porc1);p2x:= x2+(dx2*porc2);p2y:= y2+(dy2*porc2);p3x:= x3+(dx3*porc3);p3y:= y3+(dy3*porc3);
			bp_x:= (p1x+p2x+p3x)/3; bp_y:= (p1y+p2y+p3y)/3;
			return (SELECT st_transform(ST_SetSRID(ST_Point(bp_x, bp_y),sr_id),(select st_srid(geom) from puntos_predio limit 1)));
		end
	$$language plpgsql;
	---------------------------------------------------------------------------------------------------------------------
	-- Calcula el punto medio cuando se reciben tres puntos y un valor de confianza para cada punto

	CREATE OR REPLACE FUNCTION public.ffp_pto_medio (geometry, geometry, geometry, int, int, int) returns geometry as $$
	declare
		x1 real; y1 real; x2 real; y2 real; x3 real; y3 real;
		b_x real; b_y real; bp_x real; bp_y real;
		dx1 real; dy1 real; dx2 real; dy2 real; dx3 real; dy3 real;
		dp1 real; dp2 real; dp3 real;
		p1x real; p1y real; p2x real; p2y real; p3x real; p3y real;
		porc1 real; porc2 real; porc3 real; m1 real; m2 real; m3 real;
		j integer:=1;
		sr_id int;
		begin
			sr_id:= (select s_id from ffp_parameters);
			x1:= (select st_x(st_transform($1,sr_id))); y1:= (select st_y(st_transform($1,sr_id)));
			x2:= (select st_x(st_transform($2,sr_id))); y2:= (select st_y(st_transform($2,sr_id)));
			x3:= (select st_x(st_transform($3,sr_id))); y3:= (select st_y(st_transform($3,sr_id)));
			b_x:= (x1+x2+x3)/3; b_y:= (y1+y2+y3)/3;
			dx1:= b_x-x1; dy1:= b_y-y1; dx2:= b_x-x2; dy2:= b_y-y2; dx3:= b_x-x3; dy3:= b_y-y3;
			dp1:= |/((dx1^2)+(dy1^2)); dp2:= |/((dx2^2)+(dy2^2)); dp3:= |/((dx3^2)+(dy3^2));
			m1:= (select st_m(st_transform($1,sr_id))); m2:= (select st_m(st_transform($2,sr_id))); m3:= (select st_m(st_transform($3,sr_id)));
			if dp1 <= 0.1 then porc1:=0;
				else if (m1*$4)>dp1 then porc1:=1; else porc1:= (m1*$4)/dp1; end if; end if;
			if dp2 <= 0.1 then porc2:=0;
				else if (m2*$5)>dp2 then porc2:=1; else porc2:= (m2*$5)/dp2; end if; end if;
			if dp3 <= 0.1 then porc3:=0;
				else if (m3*$6)>dp3 then porc3:=1; else porc3:= (m3*$6)/dp3; end if; end if;
			p1x:= x1+(dx1*porc1);p1y:= y1+(dy1*porc1);p2x:= x2+(dx2*porc2);p2y:= y2+(dy2*porc2);p3x:= x3+(dx3*porc3);p3y:= y3+(dy3*porc3);
			bp_x:= (p1x+p2x+p3x)/3; bp_y:= (p1y+p2y+p3y)/3;
			return (SELECT st_transform(ST_SetSRID(ST_Point(bp_x, bp_y),sr_id),(select st_srid(geom) from puntos_predio limit 1)));
		end
	$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Calcula el punto medio cuando se reciben dos puntos

	CREATE OR REPLACE FUNCTION public.ffp_pto_medio (geometry, geometry) returns geometry as $$
	declare
		x1 real; y1 real; x2 real; y2 real;
		b_x real; b_y real; bp_x real; bp_y real;
		dx1 real; dy1 real; dx2 real; dy2 real;
		dp1 real; dp2 real;
		p1x real; p1y real; p2x real; p2y real;
		porc1 real; porc2 real; m1 real; m2 real;
		j integer:=1;
		sr_id int;
		begin
			sr_id:= (select s_id from ffp_parameters);
			x1:= (select st_x(st_transform($1,sr_id))); y1:= (select st_y(st_transform($1,sr_id)));
			x2:= (select st_x(st_transform($2,sr_id))); y2:= (select st_y(st_transform($2,sr_id)));
			b_x:= (x1+x2)/2; b_y:= (y1+y2)/2;
			dx1:= b_x-x1; dy1:= b_y-y1; dx2:= b_x-x2; dy2:= b_y-y2;
			dp1:= |/((dx1^2)+(dy1^2)); dp2:= |/((dx2^2)+(dy2^2));
			m1:= (select st_m(st_transform($1,sr_id))); m2:= (select st_m(st_transform($2,sr_id)));
			if (m1>0)and(m2>0) then
				if m1>dp1 then porc1:=1; else porc1:= m1/dp1; end if;
				if m2>dp2 then porc2:=1; else porc2:= m2/dp2; end if;
				p1x:= x1+(dx1*porc1);p1y:= y1+(dy1*porc1);p2x:= x2+(dx2*porc2);p2y:= y2+(dy2*porc2);
				bp_x:= (p1x+p2x)/2; bp_y:= (p1y+p2y)/2;
			   else
				bp_x:=b_x; bp_y:=b_y;
			end if;
			return (SELECT st_transform(ST_SetSRID(ST_Point(bp_x, bp_y),sr_id),(select st_srid(geom) from puntos_predio limit 1)));
		end
	$$language plpgsql;

-----------------------------------------------------------------------------------------------------------------------------
	-- Función que permite ver la posicion media calculada cuando recibe como entrada la geometría de tres puntos

	CREATE OR REPLACE FUNCTION public.ffp_ver_pto_medio (int, int, int) returns text as $$
		declare
		begin
			delete from pto_ajuste;
			insert into pto_ajuste values (1,
				(SELECT st_force4d(ffp_pto_medio(
				(select geom from puntos_predio where pto = $1),
				(select geom from puntos_predio where pto = $2),
				(select geom from puntos_predio where pto = $3)))));
			return 'Ya puede ver el punto';
		end
	$$language plpgsql;
	---------------------------------------------------------------------------------------------------------------------
	-- Función que modifica y visualiza la posicion media calculada cuando recibe como entrada la geometría de tres puntos

	CREATE OR REPLACE FUNCTION public.ffp_ver_pto_medio (int, int, int, boolean) returns text as $$
		declare
		begin
			delete from pto_ajuste;
			insert into pto_ajuste values (1,
				(SELECT st_force4d(ffp_pto_medio(
				(select geom from puntos_predio where pto = $1),
				(select geom from puntos_predio where pto = $2),
				(select geom from puntos_predio where pto = $3)))));
			if $4 then
				update puntos_predio set geom =
					(select geom from pto_ajuste)
					where pto in ($1,$2,$3);
				perform ffp_actualice_geom_predio((select cast(id_pol as integer) from puntos_predio where pto=$1));
				perform ffp_actualice_geom_predio((select cast(id_pol as integer) from puntos_predio where pto=$2));
				perform ffp_actualice_geom_predio((select cast(id_pol as integer) from puntos_predio where pto=$3));
				return 'Ya se realizo el cambio';
			else
				return 'No se realizo el cambio';
			end if;
		end
	$$language plpgsql;
	---------------------------------------------------------------------------------------------------------------------
	-- visualizar el punto medio calculado a partir de dos puntos de entrada

	CREATE OR REPLACE FUNCTION public.ffp_ver_pto_medio (int, int) returns text as $$
		declare
		begin
			delete from pto_ajuste;
			insert into pto_ajuste values (1,
				(SELECT st_force4d(ffp_pto_medio(
				(select geom from puntos_predio where pto = $1),
				(select geom from puntos_predio where pto = $2)))));
			return 'Ya puede ver el punto';
		end
	$$language plpgsql;
	---------------------------------------------------------------------------------------------------------------------
	-- visualizar y modificar los puntos de entrada al punto medio calculado a partir de dos puntos de entrada

	CREATE OR REPLACE FUNCTION public.ffp_ver_pto_medio (int, int, boolean) returns text as $$
		declare
		begin
			delete from pto_ajuste;
			insert into pto_ajuste values (1,
				(SELECT st_force4d(ffp_pto_medio(
				(select geom from puntos_predio where pto = $1),
				(select geom from puntos_predio where pto = $2)))));
			if $3 then
				update puntos_predio set geom =
					(select geom from pto_ajuste)
					where pto in ($1,$2);
				perform ffp_actualice_geom_predio((select cast(id_pol as integer) from puntos_predio where pto=$1));
				perform ffp_actualice_geom_predio((select cast(id_pol as integer) from puntos_predio where pto=$2));
				return 'Ya se realizo el cambio';
			else
				return 'No se realizo el cambio';
			end if;
		end
	$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que recibe como parámetro el identificador de un predio y actualiza la geometría de la tabla "Predio"

CREATE OR REPLACE FUNCTION public.ffp_actualice_geom_predio (int) returns text as $$
	declare
	begin
		drop table if exists  borreme_ya;
		create temporary table borreme_ya as
			((select geom from puntos_predio where id_pol=$1 order by num_pto)
			union all
			select geom from puntos_predio where id_pol=$1 and num_pto=1);
--			select geom from puntos_predio where id_pol=$1 order by num_pto limit 1);
			update spatialunit set geom=
				(select st_force3d(ST_SetSRID(st_multi(st_makepolygon(st_makeline(geom))),(select st_srid(geom) from puntos_predio limit 1))) geom from borreme_ya)
				where objectid = $1;
		return 'Geometria actualizada'||$1;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Funciones para la edición de puntos
-----------------------------------------------------------------------------------------------------------------------------
-- Función que mueve el primer punto hasta donde se encuentra el segundo punto. Verdadero lo mueve, falso solo muestra la posición
CREATE OR REPLACE FUNCTION public.ffp_mueva_1_a_2 (int, int, boolean) returns text as $$
	declare
	begin
		delete from pto_ajuste;
		insert into pto_ajuste values (1,
			(select geom from puntos_predio where pto = $2));
		if $3 then
			update puntos_predio set geom =
				(select geom from pto_ajuste)
				where pto in ($1);
			perform ffp_actualice_geom_predio((select cast(id_pol as integer) from puntos_predio where pto=$1));
			return 'Ya se realizo el cambio';
		     else
			return 'Puede ver a donde se va a mover';
		end if;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que actualiza la posición de un punto a la misma posición del punto de ajuste. Verdadero realiza la actualización

CREATE OR REPLACE FUNCTION public.ffp_mueva_a_ajuste (int, boolean) returns text as $$
	declare
	begin
		if $2 then
			update puntos_predio set geom =
				(select geom from pto_ajuste)
				where pto in ($1);
			perform ffp_actualice_geom_predio((select cast(id_pol as integer) from puntos_predio where pto=$1));
			return 'Ya se realizo el cambio';
		     else
			return 'Puede ver a donde se va a mover';
		end if;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que renumera los puntos de un predio específico

CREATE OR REPLACE FUNCTION public.ffp_renumera_ptos_predio (int) returns void as $$
	declare
		i integer := 0;
	begin
		drop table if exists tm_pt_pred;
		create temporary table tm_pt_pred as
			select * from puntos_predio where id_pol=$1 order by num_pto;
		alter table tm_pt_pred add column n serial not null;
		update puntos_predio set num_pto=t.n
			from tm_pt_pred t
			where puntos_predio.id_pol=$1 and puntos_predio.pto=t.pto;
		drop table if exists tm_pt_pred;
		return;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ffp_renumera_ptos () returns void as $$
	declare

	begin
		perform ffp_renumera_ptos_predio(objectid) from spatialunit;
		drop table if exists tm_pt_pred;
		create table tm_pt_pred as
			select * from puntos_predio order by id_pol,num_pto;
		alter table tm_pt_pred add column n serial not null;
		update tm_pt_pred set pto=n;
		alter table tm_pt_pred drop column n;
		drop table if exists puntos_predio;
		alter table tm_pt_pred rename to puntos_predio;
		return;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que borra un punto. Verdadero lo borra, falso sólo muestra el punto seleccionado

CREATE OR REPLACE FUNCTION public.ffp_borre_punto (int, boolean) returns text as $$
	declare
		i integer := 0;
	begin
		delete from pto_ajuste;
		insert into pto_ajuste values (1,
			(select geom from puntos_predio where pto = $1));
		i := (select cast(id_pol as integer) from puntos_predio where pto=$1);
		if $2 then
			delete from puntos_predio
				where pto = $1;
			perform ffp_actualice_geom_predio(i);
			perform ffp_renumera_ptos_predio (i);
			return 'Ya se borro el punto';
		     else
			return 'Puede ver el punto que se pretende borrar';
		end if;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que inserta un punto en la mitad de los dos puntos indicados. El orden es importante, primero debe ser el menor

CREATE OR REPLACE FUNCTION public.ffp_nuevo_punto (int, int) returns text as $$
	declare
		n integer := 0;
		p1 integer := 0;
		p2 integer := 0;
	begin
		perform ffp_ver_pto_medio ($1, $2);
		n := (select num_pto from puntos_predio where pto = $1);
		p1 := (select id_pol from puntos_predio where pto = $1);
		p2 := (select id_pol from puntos_predio where pto = $2);
		update puntos_predio set num_pto = num_pto+1
			where id_pol = p1 and id_pol = p2 and num_pto > n;
		insert into puntos_predio values
			((select max(pto) from puntos_predio)+1,
			 p1,n+1,'T',0,
			 (select geom from pto_ajuste));
		return 'Ya se insertó el punto';
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función para la creación de los límites de un predio

CREATE OR REPLACE FUNCTION public.ffp_limites_predio (int) returns void as $$
declare
	i integer := 0;
	a1 integer := 0;
	a2 integer := 0;
	anchor1 integer := 0;
	anchor2 integer := 0;
	n integer := 0;
	r record;
	begin
		drop table if exists ptos_limite;
		create table ptos_limite as
			select pto, id_pol, num_pto, label tipo, geom from puntos_predio where id_pol = $1
				order by num_pto;
		drop table if exists t_borre;
		create table t_borre as
			select geom from ptos_limite where 1=2;
		for r in select * from ptos_limite loop
			if lower(r.tipo) = 'a' or i=0 then
				i:=i+1;
				if (select count(*) from limits) = 0 then n:=0; else n := (select max(limitid) from limits); end if;
				n := n+1;
				a2 := r.pto;
				a1 := a2;
				insert into limits (limitid,id_pol,seq_limit,ancla1) values
					(n,r.id_pol,i,r.pto);
				if i>1 then
					update limits set ancla2 = a2 where limitid = i-1;
					delete from t_borre;
					insert into t_borre
						select geom from ptos_limite where id_pol = $1 and num_pto between
						(select num_pto from ptos_limite
							where pto = (select ancla1 from limits where limitid = i-1))
						and
						(select num_pto from ptos_limite
							where pto = (select ancla2 from limits where limitid = i-1))
						order by num_pto;
					update limits set geom = (select st_force3d(st_makeline(geom)) from t_borre)
						where limitid = i-1;
				end if;
			end if;
		end loop;
		a2 = (select ancla1 from limits where id_pol = $1 and seq_limit=1);
		update limits set ancla2 = a2 where limitid = i;
				delete from t_borre;
					insert into t_borre
						select geom from ptos_limite where num_pto >=
							(select num_pto from ptos_limite
								where pto = (select ancla1 from limits where limitid = i));
					insert into t_borre
						select geom from ptos_limite where num_pto = (select min(num_pto) from ptos_limite);
					update limits set geom = (select st_force3d(st_makeline(geom)) from t_borre)
						where limitid = i;
		drop table if exists t_borre;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función para crear todos los límites que están en la tabla "Predio"

CREATE OR REPLACE FUNCTION public.ffp_limites() returns void as $$
	declare
		s record;
	begin
		delete from limites;
		for s in select * from spatialunit loop
			delete from limits;
			PERFORM ffp_limites_predio(s.objectid);
			insert into limites select * from limits;
		end loop;
		update limites set limitid = id_pol*100+seq_limit;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Funciones usadas en las firmas y límites
-----------------------------------------------------------------------------------------------------------------------------
-- Función que inicializa en NULL todos los valores de conceptos, fechas y firmas

CREATE OR REPLACE FUNCTION public.ffp_reset_firmas() returns void as $$
	declare

	begin
		update firma_l set concepto = null, fecha = null;
		-- update firma_colinda_todos set concepto = null, fecha = null;
		delete from boundary_signature;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Actualiza la información de los límites de un predio

CREATE OR REPLACE FUNCTION public.ffp_actualiza_limite(int) returns void as $$
	declare

	begin
		delete from limits;
		perform ffp_limites_predio((select id_pol from limites where limitid = $1));
		update limits set limitid = id_pol*100+seq_limit;
		update limites set geom = l.geom
			from limits l
			where limites.limitid = l.limitid and limites.limitid=$1;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que reemplaza los límites de un predio por la nueva generación de límites dado un identificador del predio

CREATE OR REPLACE FUNCTION public.ffp_reemplaza_limite(integer) RETURNS void AS $$
	begin
		delete from limits;
		perform ffp_limites_predio($1);
		update limits set limitid = id_pol*100+seq_limit;
		delete from limites where id_pol = $1;
		insert into limites select * from limits;
	end
$$LANGUAGE plpgsql VOLATILE;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que almacena el concepto del propietario por límite, recibe el primer parámetro que corresponde al identificador
--	de su predio, el segundo parámetro al identificador del predio vecino, y el tercer parámetro el GlobalID del vecino

CREATE OR REPLACE FUNCTION public.ffp_concepto_propietario_limite (int,int,varchar,boolean) returns void as $$
	declare
	begin
		update firma_l set concepto = $4 where limitid=
			(select limitid from firma_l f inner join c_t c on (f.limitid = c.limit1)
					where pol1=$1 and GlobalID = $3 and pol2=$2)
			and GlobalID = $3;
		update firma_l set fecha = current_date where limitid=
			(select limitid from firma_l f inner join c_t c on (f.limitid = c.limit1)
					where pol1=$1 and GlobalID = $3 and pol2=$2)
			and GlobalID = $3;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que almacena el concepto del propietario por límite, recibe el primer parámetro que corresponde al identificador
--	del límite del predio, el segundo parámetro es el GlobalID del vecino y el tercer parámetro el concepto del límite

CREATE OR REPLACE FUNCTION public.ffp_concepto_propietario_limite (int,varchar,boolean) returns void as $$
	declare

	begin
		update firma_l set concepto = $3,fecha = current_date
			where limitid=$1 and GlobalID = $2;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ffp_concepto_propietario_limite(integer,integer,boolean,date,character varying)
    RETURNS void LANGUAGE 'plpgsql'
    COST 100
    VOLATILE
AS $BODY$
     declare
     begin
           update inspection.firma_l set concepto = $3,fecha = $4, remarks = $5
                where limitid=$1 and id_party = $2;
     end
$BODY$;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que actualiza la información de la table firma_l (Tabla que almacena los conceptops de los propietarios respecto
--	de cada uno de los límites), cuando se realizan cambios entre los propietarios (ej. adicion o borrado de propietarios)
--	NOTA: sólo sirve cuando no hay cambios de geometría de límites

CREATE OR REPLACE FUNCTION public.ffp_actualizar_conceptos_propietarios () returns void as $$
	declare

	begin
		drop table if exists firma_l_nueva;
		create table firma_l_nueva as
			select limitid, r.GlobalID,pt.id id_party
				from spatialunit p left outer join "right" r on (p.GlobalID = r.spatialunit_ID)
				left outer join Party pt on (r.GlobalID = pt.right_ID) inner join limites l on (p.objectid = l.id_pol)
				order by p.objectid, limitid;
		alter table firma_l_nueva add column concepto boolean;
		alter table firma_l_nueva add column fecha date;

		update firma_l_nueva set concepto = fl.concepto
			from firma_l fl
			where firma_l_nueva.limitid = fl.limitid and firma_l_nueva.GlobalID = fl.GlobalID;
		update firma_l_nueva set fecha = fl.fecha
			from firma_l fl
			where firma_l_nueva.limitid = fl.limitid and firma_l_nueva.GlobalID = fl.GlobalID;

		drop table if exists firma_l_backup;
		create table firma_l_backup as select * from firma_l;

		delete from firma_l;
		insert into firma_l
			select * from firma_l_nueva;
		drop table firma_l_nueva;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que actualiza que copia un límite dado con su identificador, en otro limite dado con su identificador

CREATE OR REPLACE FUNCTION public.ffp_copia_limite (int,int) returns text as $$
	declare
	begin
		return 'Aún no Se ha copiado el limite '||$1||' en el limite '||$2;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función para adicionar los puntos de un nuevo predio a la tabla puntos_predio

CREATE OR REPLACE FUNCTION public.ffp_adiciona_puntos_predio(integer) returns integer as $$
declare
	i integer := 1;
	r record;
begin
	drop table if exists vpoints;
	create temporary table vpoints as
		select (st_dumppoints(geom)).path[3],
			(st_dumppoints(geom)).geom
			 from spatialunit
			 where objectid=$1;
	alter table vpoints add column id serial not null;
	for r in select * from vpoints loop
		if i<(select count(*) from vpoints) then
			insert into puntos_predio (pto,id_pol,num_pto,label,geom) values
				((select max(pto)+1 from puntos_predio),$1,i,null,(select st_force4d(geom) from vpoints where id=i));
		end if;
		i := i + 1;
	end loop;

	return i-1;
end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
-- Función que permite actualizar la información de los límites de un predio particular en la tabla firma_l
--	NOTA: la información de concepto, fecha y firma queda con valores NULL. Se debe usar cuando no hay conceptos en los límites

CREATE OR REPLACE FUNCTION public.ffp_actualiza_firma_l(int,boolean) returns void as $$
	declare

	begin
		delete from firma_l where limitid/100 = $1;
		insert into firma_l (limitid,GlobalID,id_party)
			select limitid, r.GlobalID,pt.objectid id_party
				from spatialunit p left outer join "right" r on (p.GlobalID = r.spatialunit_ID)
				left outer join Party pt on (r.GlobalID = pt.right_ID) inner join limites l on (p.objectid = l.id_pol)
				where limitid/100 = $1
				order by limitid;
		update firma_l set titulo = $2 where limitid/100 = $1;
	end
$$language plpgsql;
-----------------------------------------------------------------------------------------------------------------------------
create or replace function public.ffp_copia_esquema (varchar, varchar) returns void as $$
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
create or replace function public.ffp_renum_ancles(int) returns void as $$
	begin
		update puntos_predio
			set num_pto = num_pto-(select min(num_pto) from puntos_predio where label = 'A' and id_pol=$1)+1
			where id_pol=$1;
		update puntos_predio
			set num_pto=num_pto+(select count(*) from puntos_predio where id_pol=$1)
			where id_pol = $1 and num_pto < 1;
	end;
$$language plpgsql;
--===========================================================================================================================


--===========================================================================================================================
-- Autor: Javier Morales - 17-03-2021
--===========================================================================================================================
-- Computes and adds a point to a spatialunit in the middle of two given vertices
-- It requires the ordered ids (odered according to their position in the spatialunit) of the two chosen vertices

CREATE OR REPLACE FUNCTION public.ffp_nuevo_punto_medio(integer, integer)
    RETURNS text
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	n integer := 0;
	p1 integer := 0;
	p2 integer := 0;
	BEGIN
		PERFORM ffp_ver_pto_medio ($1, $2);
		n := (SELECT num_pto FROM puntos_predio WHERE pto = $1);
		p1 := (SELECT id_pol FROM puntos_predio WHERE pto = $1);
		p2 := (SELECT id_pol FROM puntos_predio WHERE pto = $2);
		UPDATE puntos_predio SET num_pto = num_pto+1
			WHERE id_pol = p1 AND id_pol = p2 AND num_pto > n;
		INSERT INTO puntos_predio VALUES
			((SELECT MAX(pto) FROM puntos_predio)+1,
			p1,n+1,'T',0,
			(SELECT geom FROM pto_ajuste));
		PERFORM ffp_actualice_geom_predio(p1);
		DELETE FROM pto_ajuste;
		RETURN (SELECT CAST(MAX(pto) AS text) FROM puntos_predio);
	END
$BODY$;


--===========================================================================================================================
-- Autor: Javier Morales - 17-03-2021
--===========================================================================================================================
-- Computes and displays a point at the closest distance from a given vertex to a target spatialunit
-- It requires the id of the source vertex and the id of the target polygon

CREATE OR REPLACE FUNCTION public.ffp_proyectar_punto(integer, integer)
	RETURNS text
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	BEGIN
		DELETE FROM pto_ajuste;
		INSERT INTO pto_ajuste
		WITH point AS (
			SELECT pto, geom
			FROM puntos_predio
			WHERE pto = $1
		),
		poly AS (
			SELECT objectid, geom, st_exteriorring((st_dump(geom)).geom) AS ringgeom
			FROM spatialunit
			WHERE objectid = $2
		)
		SELECT 1, ST_Force4D(ST_PointN(ST_ShortestLine(poly.ringgeom, point.geom),1))
		FROM point, poly;
		RETURN 'Ya se proyectó el punto';
	END
$BODY$;


--===========================================================================================================================
-- Autor: Javier Morales - 17-03-2021
--===========================================================================================================================
-- Adds a previosuly projected point to a spatialunit (it requires the function 'ffp_proyectar_punto' to be executed first)
-- It requires the id of the source vertex and the id of the target polygon

CREATE OR REPLACE FUNCTION public.ffp_nuevo_punto_proyectado(integer, integer)
	RETURNS text
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	n integer := 0;
	p1 integer := 0;
	p2 integer := 0;
	BEGIN
		n := (SELECT num_pto FROM puntos_predio WHERE pto = $1);
		p1 := (SELECT id_pol FROM puntos_predio WHERE pto = $1);
		p2 := (SELECT id_pol FROM puntos_predio WHERE pto = $2);
		UPDATE puntos_predio SET num_pto = num_pto+1
			WHERE id_pol = p1 AND id_pol = p2 AND num_pto > n;
		INSERT INTO puntos_predio VALUES
			((SELECT MAX(pto) FROM puntos_predio)+1,
			p1,n+1,'T',0,
			(SELECT geom FROM pto_ajuste));
		PERFORM ffp_actualice_geom_predio(p1);
		DELETE FROM pto_ajuste;
		RETURN (SELECT CAST(MAX(pto) AS text) FROM puntos_predio);
	END
$BODY$;



--===========================================================================================================================
-- Autor: Javier Morales - 15-03-2022
--===========================================================================================================================
-- Identifies and lists all the recordds associated qith a given spatialunit
-- (used as data source to delete spatilaunits during editing)

CREATE OR REPLACE FUNCTION public.ffp_spatialunit_recordset(integer)
    RETURNS TABLE (
		tbl VARCHAR,
		des VARCHAR,
		gid VARCHAR
	) AS $$
LANGUAGE 'plpgsql'

AS $BODY$
DECLARE
	su_id varchar;
	su_name varchar;
	r_id varchar;
	r_type varchar;
	p_id varchar;
	item record;
	att record;
	p_att record;
	BEGIN
		SELECT s.globalid, btrim(spatialunit_name) INTO su_id, su_name FROM spatialunit AS s WHERE s.objectid = $1;
		tbl := 'spatialunit';
		des := su_name;
		gid := su_id;
		RETURN NEXT;
		FOR item IN (SELECT * FROM spatialunit__attach AS r WHERE r.rel_globalid = su_id) LOOP
			tbl := 'spatialunit__attach';
			des := '';
			gid := item.globalid;
			RETURN NEXT;
		END LOOP;
		SELECT r.globalid, r.right_type INTO r_id, r_type FROM "right" AS r WHERE r.spatialunit_id = su_id;
		IF r_id IS NOT null THEN
			tbl := 'right';
			des := COALESCE((SELECT en FROM inspection.codelist WHERE list = 'righttype' AND code::TEXT = r_type), '');
			gid := r_id;
			RETURN NEXT;
			FOR item IN SELECT * FROM rightattachment as ra WHERE ra.right_id = r_id LOOP
				IF item.globalid IS NOT NULL THEN
					tbl := 'rightattachment';
					des := COALESCE((SELECT en FROM inspection.codelist WHERE list = 'rightattachment' AND code::TEXT = item.attachment_type), '');
					gid := item.globalid;
					RETURN NEXT;
					FOR att IN SELECT * FROM right__attach as a WHERE a.rel_globalid = item.globalid LOOP
						tbl := 'right__attach';
						des := '';
						gid := att.globalid;
						RETURN NEXT;
					END LOOP;
				END IF;
			END LOOP;
			FOR item IN SELECT * FROM party as p WHERE p.right_id = r_id LOOP
				IF item.globalid IS NOT null THEN
					tbl := 'party';
					des := btrim(item.first_name) || ' ' || btrim(item.last_name);
					gid := item.globalid;
					RETURN NEXT;
					FOR att IN SELECT * FROM partyattachment as pa WHERE pa.party_id = item.globalid LOOP
						tbl := 'partyattachment';
						des := COALESCE((SELECT en FROM inspection.codelist WHERE list = 'partyattachment' AND code::TEXT = att.attachment_type), '');
						gid := att.globalid;
						RETURN NEXT;
						FOR p_att IN SELECT * FROM party__attach as a WHERE a.rel_globalid = att.globalid LOOP
							tbl := 'party__attach';
							des := '';
							gid := p_att.globalid;
							RETURN NEXT;
						END LOOP;
					END LOOP;
				END IF;
			END LOOP;
		END IF;
	END;
$BODY$;
-----------------------------------------------------------------------------------------------------------------------------
