pushd %TEMP%
conda create -p %TEMP%\_py37_dll_bug python=3.7 numba=0.42 -y
call activate -p %TEMP%\_py37_dll_bug
conda info
%PYTHON% --version
set fname="aot.py"
del %fname%
del test_mod.pyd

@echo "" > %fname%
@echo from numba.pycc import CC >> %fname%
@echo import math >> %fname%
@echo cc = CC('test_mod') >> %fname%
@echo @cc.export('func', 'f8(f8)') >> %fname%
@echo def foo(x): >> %fname%
@echo     return math.cos(x) + math.sin(x) >> %fname%
@echo if __name__ == '__main__': >> %fname%
@echo    cc.compile() >> %fname%

%PYTHON% %fname%
%PYTHON% -c "import test_mod"
