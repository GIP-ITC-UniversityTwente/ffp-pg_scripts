@echo off

set param=%1
set value=%2

if /i "%param%"=="--lang" (set lang=%value%) else (set lang=en)


:: Define the ESC sequence for coloring text
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

goto :init


:: Populating locale variables
:locale
  for /F "tokens=1,2 delims=|" %%A in (locale/vars.%lang%%) do (
    set lbl_%%A=%%B
  )
  goto :eof
::---


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

  set default_path=C:\code\ffp
  call :locale

  echo.
  echo.
  echo ------------------------------------------------------
  echo.
  echo %lbl_msg5%
  echo.

  call :message in %default_path% flag0
  set /p ffp_path="%lbl_q3% <%flag0%>?: "
  if "%ffp_path%"=="" set ffp_path=%default_path%
  if "%ffp_path:~-1%" EQU "\" set ffp_path=%ffp_path:~0,-1%
  call :message out %ffp_path% flag0
  echo %flag0%
  set errorlevel=0
  echo.


  call :message err %ffp_path% flag0
  if %ffp_path:~1,2% NEQ :\ (
    echo Invalid path ^(%flag0%^)
    goto :error
  )

  if not exist %ffp_path%\index.html (
    echo Inspection app files not found in %flag0%
    goto :error
  )

  set "pi_folder=%ffp_path:\=" & set "pi_folder=%"
  set httpd_folders=%pi_folder% basedata
  set ms4w=C:\ms4w\httpd.d\


  FOR %%a in (%httpd_folders%) do (
    SETLOCAL ENABLEDELAYEDEXPANSION

    if not exist %ms4w%httpd_%%a.conf (
      echo Alias /%%a/ "!ffp_path:%pi_folder%=%%a!" > %ms4w%httpd_%%a.conf
      if %errorlevel% NEQ 0 goto :error
      echo.>>%ms4w%httpd_%%a.conf
      echo ^<Directory "!ffp_path:%pi_folder%=%%a!"^>^

  AllowOverride All^

  Options Indexes FollowSymLinks Multiviews ExecCGI^

  AddHandler cgi-script .py^

  Order allow,deny^

  Allow from all^

  Require all granted^

^</Directory^> >> %ms4w%httpd_%%a.conf
    )
  )

  set "errorlevel="
  findstr /I "<9377>" c:\ms4w\proj\nad\epsg
  if %errorlevel% EQU 1 (
    echo # MAGNA-SIRGAS / Origen-Nacional >> c:\ms4w\proj\nad\epsg
    echo ^<9377^> +proj=tmerc +lat_0=4 +lon_0=-73 +k=0.9992 +x_0=5000000 +y_0=2000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +type=cr ^<^> >> c:\ms4w\proj\nad\epsg
    set origin_msg=y
  )

  C:\ms4w\Python\Scripts\pip.exe install -r requirements.txt

  :: Report success
  echo.
  echo ------------------------------------------------------
  echo.

  call :message res "%httpd_folders%" flag0
  set flag0=%flag0: =, %
  echo Web folders %flag0% created succesfully...

  call :message res MAGNA-SIRGAS flag0
  if defined origin_msg (
    echo %flag0% parameters added to MapServer
  ) else (
    echo %flag0% parameters already exists
  )

  call :message res Python flag0
  set flag0=%flag0: =, %
  echo %flag0% requirements checked...

  echo.
  echo ------------------------------------------------------
  echo.

  goto :end


:setName
  echo 3344 %1
  set %~2=5566

:: Report failure to complete
:error
  echo.
  set "errmsg=Execution Unsuccessful"
  call :message err "%errmsg%" flag0
  echo %flag0%

  echo.
  echo Stoping...
  echo.
::---


:: Terminate execution
:end
  exit /B %errorlevel%