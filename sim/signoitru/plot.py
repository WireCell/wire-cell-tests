#!/usr/bin/env python
import sys
import numpy
import wirecell.gen.sim
from wirecell import units
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

try:
    npzfile = sys.argv[1]
except IndexError:
    npzfile = "uboone-wctsim-signal-noise-truth-adc.npz"
    
try:
    pdffile = sys.argv[2]
except IndexError:
    pdffile = "uboone-wctsim-signal-noise-truth-adc.pdf"
    

fp = numpy.load(npzfile)
fsim = wirecell.gen.sim.Frame(fp, tag='simulation')
ftru = wirecell.gen.sim.Frame(fp, tag='truth')

chtru = wirecell.gen.sim.group_channel_indices(ftru.channels)

with PdfPages(pdffile) as pdf:
    fig, axes = ftru.plot(tf=0.2*units.ms, raw=False, chinds=chtru[-1:])
    pdf.savefig(fig)
    plt.close()

    fig, axes = fsim.plot(tf=0.2*units.ms, raw=False, chinds=[(6955,6980)])
    pdf.savefig(fig)
    plt.close()
