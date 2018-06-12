// Import this file to access global parameters, to be shared by
// various test_*.jsonnet

local wc = import "wirecell.jsonnet";

local base_params = import "base_params.jsonnet";

local uboone_params = base_params {
    lar : super.lar {
        drift_speed : 1.114*wc.mm/wc.us, // at microboone voltage
    },
    detector : super.detector {
        extent: [2.5604*wc.m,2.325*wc.m,10.368*wc.m],
        // Wires have a detector edge at X=0, Z=0, centered in Y.
        center: [0.5*self.extent[0], 0.0, 0.5*self.extent[2]],
    },
    elec : super.elec {
        postgain: -1.2,
    },
    files : {
        wires:"microboone-celltree-wires-v2.1.json.bz2",
        fields:["ub-10-half.json.bz2",
                "ub-10-uv-ground-half.json.bz2",
                "ub-10-vy-ground-half.json.bz2"],
        noise: "microboone-noise-spectra-v2.json.bz2",
    }
};


uboone_params


