from waflib.Tools import waf_unit_test

top = '.'
out = 'build'

def options(opt):
    opt.load('compiler_cxx')
    opt.load('waf_unit_test')

def configure(cfg):
    cfg.load('compiler_cxx')
    cfg.load('waf_unit_test')

    cfg.find_program('python', mandatory=True)
    cfg.find_program('bash', mandatory=True)
    cfg.find_program('wire-cell', var='WIRECELL', mandatory=True)

def build(bld):
    bld.recurse("sim")
    bld.add_post_fun(waf_unit_test.summary)
    
