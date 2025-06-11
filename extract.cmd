@echo off
set "output_file=%CD%\gd_tscn_data.txt"
echo. > "%output_file%"
for /r %%f in (*.gd *.tres) do (
    echo ==== %%f ==== >> "%output_file%"
    type "%%f" >> "%output_file%"
    echo. >> "%output_file%"
)
echo Extraction complete! Data saved to %output_file%