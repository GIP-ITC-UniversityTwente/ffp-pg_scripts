# _FfP_ &ndash; Database Configuration Scripts

These _FfP_ configuration scripts are used for processing data collected during FfP-based field surveys. These scripts make it possible  to edit a given dataset using the **_FfP_ QGIS plugin** and also configure the dataset for the **Public Inspection** Application.

&nbsp;

## Requirements

* PostgreSQL/PostGIS
* MS4W 4.0.5 &rarr; MapServer/Apache

&nbsp;

## Usage

&nbsp;

> Uses a FileGeodatabase [version 9.4] to create and populate a _FfP_ database and also create all the necessary functions to edit the data.

```
./1_initialize_editing
```

&nbsp;

> Configures a _FfP_ database after data editing is completed and configures it to be used in the Public Inspection application.

```
./2_setup_public_inspection
```
&nbsp;

> Creates, if required, the necessary configuration files in Apache to run the Public Inspection Application.

```
./web_folders
```
