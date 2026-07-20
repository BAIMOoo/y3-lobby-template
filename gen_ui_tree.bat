@echo off
REM Y3 UI Tree 生成脚本
REM 使用方式: gen_ui_tree.bat <map_root_path>
REM 示例: gen_ui_tree.bat .

if "%1"=="" (
    echo 错误: 请提供地图根目录路径
    echo 用法: gen_ui_tree.bat <map_root_path>
    echo 示例: gen_ui_tree.bat .
    pause
    exit /b 1
)

echo ========================================
echo Y3 UI Tree 生成工具
echo ========================================
echo 目标地图: %1
echo.

python gen_ui_tree.py "%1%"

if %errorlevel% neq 0 (
    echo.
    echo 生成失败，按任意键退出...
    pause
    exit /b 1
) else (
    echo.
    echo 生成完成！
    pause
)
