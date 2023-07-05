project('hello', 'c',
    version: '1.0')

if host_machine.system() == 'windows'
    winmod = import('windows')
    rc_obj = winmod.compile_resources('hello.rc')
else
    rc_obj = []
endif

executable('hello', 'hello.c', rc_obj)
