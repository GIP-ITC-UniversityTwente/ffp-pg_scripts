@echo off

set param=%1
set value=%2

if /i "%param%"=="--lang" (set lang=%value%) else (set lang=en)
if /i "%param%"=="--reset" call :resetvars


:: Define the ESC sequence for coloring text
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

set script_path=./src

goto :init


:: Reset user variables
:resetvars
  set "host="
  set "port="
  set "db="
  set "fgdb="
  set "user="
  echo.
  echo Variables cleared
  echo.
  goto :eof
::---


::------------------------------------------------------------------------------
:: Masks user input and returns the input as a variable.
:: Password-masking code based on http://www.dostips.com/forum/viewtopic.php?p=33538#p33538
::
:: Arguments: %1 - the variable to store the password in
::            %2 - the prompt to display when receiving input
::------------------------------------------------------------------------------
:getPassword
  set "_password="

  :: We need a backspace to handle character removal
  for /f %%a in ('"prompt;$H&for %%b in (0) do rem"') do set "BS=%%a"

  :: Prompt the user
  set /p "=%~2" <nul

  :keyLoop
  :: Retrieve a keypress
  set "key="
  for /f "delims=" %%a in ('xcopy /l /w "%~f0" "%~f0" 2^>nul') do if not defined key set "key=%%a"
  set "key=%key:~-1%"

  :: If No keypress (enter), then exit
  :: If backspace, remove character from password and console
  :: Otherwise, add a character to password and go ask for next one
  if defined key (
      if "%key%"=="%BS%" (
          if defined _password (
              set "_password=%_password:~0,-1%"
              set /p "=!BS! !BS!"<nul
          )
      ) else (
          set "_password=%_password%%key%"
          set /p "="<nul
      )
      goto :keyLoop
  )
  echo/

  :: Return password to caller
  set "%~1=%_password%"
  goto :eof
::---


:: Populating locale variables
:locale
  for /F "tokens=1,2 delims=|" %%A in (locale/vars.%lang%%) do (
    set lbl_%%A=%%B
  )
  exit /B 0
::---


:: Colored message function
:message
  set "%~3="
  if %~1==in set %~3=%ESC%[94m%2%ESC%[0m
  if %~1==out set %~3=%ESC%[92m%2%ESC%[0m
  if %~1==err set %~3=%ESC%[91m%2%ESC%[0m
  if %~1==res set %~3=%ESC%[93m%2%ESC%[0m
  goto :eof
::---


:init
  set default.host=localhost
  set default.port=5432
  set default.user=postgres
  set "pwd="

  for /f "delims=" %%a in ('dir /b "C:\Program Files\PostgreSQL\1*"') do (
    set pg=%%a
  )
  set PATH=%SystemRoot%\system32;C:\ms4w\Apache\cgi-bin;C:\ms4w\tools\gdal-ogr;C:\Program Files\PostgreSQL\%pg%\bin;%PATH%
  set GDAL_DATA=C:\ms4w\gdaldata

  call :locale

  echo.
  echo %lbl_msg1%
  echo.


  ::FileGDB
  set lbl=%lbl_fgdb%
  if not "%fgdb%"=="" call :message in %fgdb% flag0
  if not "%fgdb%"=="" set "lbl=%lbl_fgdb% <%flag0%>"
  :get_fgdb
    set /p fgdb="%lbl%: "
    if "%fgdb%"=="" goto :get_fgdb

    call :message out %fgdb% flag1
    call :message err %fgdb% flag2
    if exist %fgdb% (
      echo %flag1%
    ) else (
      echo The file %flag2% could not be found
      goto :get_fgdb
    )


  ::host
  if "%host%"=="" set host=%default.host%
  call :message in %host% flag0
  set /p host="%lbl_host% <%flag0%>: "
  if "%host%"=="" set host=%default.host%
  call :message out %host% flag0
  echo %flag0%


  ::port
  if "%port%"=="" set port=%default.port%
  call :message in %port% flag0
  set /p port="%lbl_port% <%flag0%>: "
  if "%port%"=="" set port=%default.port%
  call :message out %port% flag0
  echo %flag0%


  ::database
  set lbl=%lbl_db%
  if not "%db%"=="" call :message in %db% flag0
  if not "%db%"=="" set "lbl=%lbl_db% <%flag0%>"
  :get_db
    set /p db="%lbl%: "
    if "%db%"=="" goto :get_db

  call :message out %db% flag0
  echo %flag0%


  ::user
  if "%user%"=="" set user=%default.user%
  call :message in %user% flag0
  set /p user="%lbl_user% <%flag0%>: "
  if "%user%"=="" set user=%default.user%
  call :message out %user% flag0
  echo %flag0%


  ::password
  call :getPassword pwd "%lbl_pwd%: "


  echo.
  call :message in y flag0
  set /p proceeed="%lbl_q1% <%flag0%/n>?: "
  if "%proceeed%"=="" set proceeed=y
  echo.
  if %proceeed% NEQ y goto :end


  echo.
  echo ----------

  set db_exist=0


  ::Check server status
  echo.
  pg_isready.exe -h %host% -p %port%
  if %errorlevel% NEQ 0 goto :error

  set conn=host=%host% port=%port% user=%user% password=%pwd%


  ::Check credentials
  psql -d "%conn% dbname=postgres" -c ""
  if %errorlevel% NEQ 0 goto :error

  call :message in %db% flag0
  echo Credentials %flag0%


  :: Creating the new database
  echo.
  call :message in %db% flag0
  echo Creating database '%flag0%'
  createdb --maintenance-db="%conn%" %db%
  if %errorlevel% NEQ 0 goto :error

  set db_exist=1
  set conn_string=%conn% dbname=%db%


  :: Execute the ffp_step_1_Creation script
  echo.
  call :message out "Running database initialization script" flag0
  echo %flag0%
  echo.
  psql -d "%conn_string%" -v ON_ERROR_STOP=1 --single-transaction --file=%script_path%/ffp_step_1_Creation.sql
  if %errorlevel% NEQ 0 goto :error


  :: Upload field data
  echo.
  echo ----------
  echo.
  call :message in %fgdb% flag0
  echo Uploading field data from %flag0%
  ogr2ogr.exe -overwrite -f "PostgreSQL" PG:"%conn_string% ACTIVE_SCHEMA=load" -lco GEOMETRY_NAME=geom -lco DIM=3 -skipfailures "%fgdb%" -progress
  if %errorlevel% NEQ 0 goto :error


  echo.
  echo ----------


  :: Execute the ffp_step_2_Edition script
  echo.
  call :message out "Running functions creation script" flag0
  echo %flag0%
  echo.
  psql -d "%conn_string%" -v ON_ERROR_STOP=1 --single-transaction --file=%script_path%/ffp_step_2_Edition.sql
  if %errorlevel% NEQ 0 goto :error


  :: Report success
  echo.
  echo ------------------------------------------------------
  echo.
  set succmsg=Database initalization completed succesfully...
  call :message out "%succmsg%" flag0
  echo %flag0:"=%

  echo.
  call :message in Results: flag0
  echo %flag0%
  call :message res %db% flag0
  echo - database "%flag0%" created
  call :message res ffp_step_1_Creation flag0
  echo - "%flag0%" script executed
  call :message res %fgdb% flag0
  echo - "%flag0%" data uploaded to the database
  call :message res ffp_step_2_Edition flag0
  echo - "%flag0%" script executed
  echo.
  call :message out %db% flag0
  echo - Database %flag0% ready to use!
  echo.
  echo ------------------------------------------------------
  echo.

  goto :end
::---


:: Report failure to complete
:error
  echo.
  set "errmsg=Execution Unsuccessful"
  call :message err "%errmsg%" flag0
  echo %flag0%
  if "%db_exist%"=="1" dropdb --maintenance-db="%conn%" %db%
  echo.
  echo Stoping...
  echo.
::---


:: Terminate execution
:end
  exit /B %errorlevel%