BEGIN;

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

END;