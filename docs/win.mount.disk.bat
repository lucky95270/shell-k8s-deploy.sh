@echo off
REM ����Ŀ¼Ϊ�̷�

set count=3
echo.
echo ע�⣺ ������������˳�.
echo.

:get_pass
set /p mima=���������룺
if \"%mima%\"==\"1234\" goto :set_drive
set /a count-=1
if \"%count%\"==\"0\" cls&echo.&echo =û�����޷�����=&echo.&pause&echo.&exit
cls&echo.&echo �㻹�� %count% �λ���&echo.&goto :get_pass

:set_drive
cls&echo.
echo= ������ȷ������ =
md D:\RECYCLED\UDrives.{25336920-03F9-11CF-8FD0-00AA00686F13}>NUL
if exist M:\NUL goto :remove
subst M: D:\RECYCLED\UDrives.{25336920-03F9-11CF-8FD0-00AA00686F13}
start M:\
goto :end

:remove
subst /D M:
goto :end

:end
echo.&pause&exit.