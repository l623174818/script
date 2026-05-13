@echo off
chcp 65001 >nul
echo ========================================
echo   设置 Windows 自动登录
echo ========================================
echo.
echo 用户名：l623174818@outlook.com
echo.
echo 警告：请将此脚本存储在安全位置！
echo ========================================
echo.

REM 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 请以管理员权限运行此脚本！
    echo 右键点击脚本，选择"以管理员身份运行"
    pause
    exit /b 1
)

echo 正在修改注册表...
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d "l623174818@outlook.com" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "xiaolu123" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultDomainName /t REG_SZ /d "" /f

echo.
echo ========================================
echo   设置完成！
echo ========================================
echo.
echo 设置内容：
echo   AutoAdminLogon = 1 (启用自动登录)
echo   DefaultUserName = l623174818@outlook.com
echo   DefaultPassword = *** (已设置)
echo.
echo 重启后生效。
echo.
echo 如需取消自动登录，请运行：
echo   reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /f
echo   并将 AutoAdminLogon 改为 0
echo ========================================
pause
