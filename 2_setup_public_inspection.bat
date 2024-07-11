@echo off

set param=%1
set value=%2
set conn_string=

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
  goto :eof
::---


:: Roles Creation
:roles
  set roles_executed=1
  call :message in %port% flag0
  call :message in %port% flag1
  echo Creating %flag0% & %flag1% roles
  psql -d "%conn_string%" -v ON_ERROR_STOP=1 --single-transaction --file=%script_path%/create_roles.sql
  if %errorlevel% NEQ 0 set roles_ok=false
  goto :eof


:: Colored message function
:message
  set %~3=
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
  echo %lbl_msg2%
  echo.


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
  set "proceed="
  call :message in y flag0
  set /p proceed="%lbl_q1% <%flag0%/n>?: "
  if "%proceed%"=="" set proceed=y
  call :message out %proceed% flag0
  echo %flag0%
  echo.
  if %proceed% NEQ y goto :end



  set scripts=ffp_step_3_Limits ffp_step_4a_load_to_survey_Update ffp_step_4b_load_to_survey_Insert
  set scripts=%scripts% ffp_step_5_survey_to_Inspection create_roles app_init physical_ids

  echo.
  echo ----------


  ::Check server status
  echo.
  pg_isready.exe -h %host% -p %port%
  if %errorlevel% NEQ 0 goto :error

  set conn_string=host=%host% port=%port% user=%user% password=%pwd% dbname=%db%

  ::Check credentials
  psql -d "%conn_string%" -c ""
  if %errorlevel% NEQ 0 goto :error

  call :message in %db% flag0
  echo Credentials for "%flag0%" OK


  echo.
  set roles_ok=true
  set roles_executed=0
  set "proceed="
  call :message in n flag0
  set /p proceed="%lbl_q2% <y/%flag0%>?: "
  if "%proceed%"=="" set proceed=n
  call :message out %proceed% flag0
  echo %flag0%
  echo.
  if %proceed% EQU y call :roles
  if %roles_ok%==false goto :error


  psql -d "%conn_string%" -v ON_ERROR_STOP=1 --single-transaction --file=%script_path%/merged.sql
  if %errorlevel% NEQ 0 goto :error


  :: Report success
  echo.
  echo ------------------------------------------------------
  echo.
  set succmsg=Database update completed succesfully...
  call :message out "%succmsg%" flag0
  echo %flag0:"=%

  echo.
  call :message in Results: flag0
  echo %flag0%
  if %roles_executed%==1 echo "%ESC%[93mcreate_roles%ESC%[0m" script executed
  (for %%a in (%scripts%) do (
    echo "%ESC%[93m%%a%ESC%[0m" script executed
  ))
  echo.
  call :message out %db% flag0
  echo - Database %flag0% ready for the public inspection app!
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