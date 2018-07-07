// in support of https://github.com/WireCell/wire-cell-gen/issues/8

local wc = import "wirecell.jsonnet";
local params = import "params.jsonnet";

local cmdline = {
    type: "wire-cell",
    data: {
        plugins: ["WireCellGen", "WireCellPgraph", "WireCellSio", "WireCellSigProc"],
        apps: ["Pgrapher"]
    }
};

local random = {
    type: "Random",
    data: {
        generator: "default",
        seeds: [0,1,2,3,4],
    }
};

local fields = [
    {
        type: "FieldResponse",
        name: "field%d"%n,
        data: { filename: params.files.fields[n] }
    } for n in [0,1,2]];

local wires = {
    type: "WireSchemaFile",
    data: { filename: params.files.wires }
};

// 0:nominal, 1:uv-grounded, 2:vy-grounded
local anode {
    type : "AnodePlane",
    data : params.elec + params.daq {
        ident : 0,              // must match what's in wires
        wire_schema: wc.tn(wires),
        faces : [
            { 
                response: params.sim.response_plane,
                cathode: params.sim.cathode_plane,
            },
        ],
    },
};
local pirs : std.mapWithIndex(function (n, fr) [
        {
            type: "PlaneImpactResponse",
            name : "PIR%splane%d" % [fr.name, plane],
            data : {
                plane: plane,
                tick: params.sim.tick,
                nticks: params.sim.nticks,
                field_response: wc.tn(fr),
                // note twice we give rc so we have rc^2 in the final convolution
                other_responses: [wc.tn($.elec_resp), wc.tn($.rc_resp), wc.tn($.rc_resp)],
            },
            uses: [fr, $.elec_resp, $.rc_resp],
        } for plane in [0,1,2]], $.fields),

  
local shared = [cmdline, random, wires] + fields + [anode];

//
//  Some basic/bogus "cosmic rays"
// 
local zstart=6500;      // mm
local zend=zstart+1500; // mm
local depos = {
    type: "TrackDepos",
    data: {
        step_size: 1.0 * wc.millimeter,
        tracks: [
            {
                time: 0.0*wc.us,
                charge: -5000, // negative means charge per step
                ray: wc.ray(wc.point(100,50,6500,wc.mm), wc.point(110,50,6510,wc.mm))
            },
            {
                time: 50.0*wc.us,
                charge: -5000, // negative means charge per step
                ray: wc.ray(wc.point(100,-50,6500,wc.mm), wc.point(110,-50,6510,wc.mm))
            },
        ]
    }
};
local drifter = {
    type : "Drifter",
    data : params.lar + params.sim  {
        anode: wc.tn(anodes[0]),
    }
};
local fanout = {
    type: "DepoFanout",
    data: {
        multiplicity: 2,
    }
};

local ductors = [
    {
        type : 'Ductor',
        name : 'ductor%d' % n,
        data : params.daq + params.lar + params.sim {
            continuous: false,
            nsigma : 3,
	    anode: wc.tn(anode),
        }
    } for n in [0,1,2]];

local ductors = std.mapWithIndex(function (n, pirs) {
    type: 'Ductor',
    name: 'ductor%d' % n,
    data: par.daq + par.lar + par.sim {
        rng: wc.tn(random),
        anode: wc.tn(anode),
        pirs: std.map(function(pir) wc.tn(pir), pirs),
    },
    uses: [random, anode] + pirs,
}, com.pirs);

local multi_ductor_chain = [
    {
        ductor: wc.tn(ductors[1]),
        rule: "wirebounds",
        args: [ 
            [ { plane:0, min:296, max:296 } ],
            [ { plane:0, min:298, max:315 } ],
            [ { plane:0, min:317, max:317 } ],
            [ { plane:0, min:319, max:327 } ],
            [ { plane:0, min:336, max:337 } ],
            [ { plane:0, min:343, max:345 } ],
            [ { plane:0, min:348, max:351 } ],
            [ { plane:0, min:376, max:400 } ],
            [ { plane:0, min:410, max:445 } ],
            [ { plane:0, min:447, max:484 } ],
            [ { plane:0, min:501, max:503 } ],
            [ { plane:0, min:505, max:520 } ],
            [ { plane:0, min:522, max:524 } ],
            [ { plane:0, min:536, max:559 } ],
            [ { plane:0, min:561, max:592 } ],
            [ { plane:0, min:595, max:598 } ],
            [ { plane:0, min:600, max:632 } ],
            [ { plane:0, min:634, max:652 } ],
            [ { plane:0, min:654, max:654 } ],
            [ { plane:0, min:656, max:671 } ],
        ],
    },

    {
        ductor: wc.tn(ductors[2]),
        rule: "wirebounds",
        args: [
            [ { plane:2, min:2336, max:2399 } ],
            [ { plane:2, min:2401, max:2414 } ],
            [ { plane:2, min:2416, max:2463 } ],
        ],
    },
    {               // catch all if the above do not match.
        ductor: wc.tn(ductors[0]),
        rule: "bool",
        args: true,
    },
];
local multi_ductor = {
    type: "MultiDuctor",
    data : {
        anode: wc.tn(anodes[0]),
        continuous: params.sim.continuous,
        chains : [
            multi_ductor_chain,
        ],
    }
};
local signal = [depos, drifter, fanout] + ductors + [multi_ductor];


local static_csdb = {
    type: "StaticChannelStatus",
    name: "urasai",
};

local noise_model = {
    type: "EmpiricalNoiseModel",
    data: {
        anode: wc.tn(anodes[0]),
        spectra_file: params.files.noise,
        chanstat: wc.tn(static_csdb),
        nsamples: params.daq.ticks_per_readout,
    }
};
local noise_source = {
    type: "NoiseSource",
    data: params.daq {
        model: wc.tn(noise_model),
	anode: wc.tn(anodes[0]),
        start_time: params.daq.start_time,
        stop_time: params.daq.stop_time,
        readout_time: params.daq.readout_time,
    }
};
local frame_summer = {
    type: "FrameSummer",
    data: {
        align: true,
        offset: 0.0*wc.s,
    }
};
local digitizer = {
    type: "Digitizer",
    data : params.adc {
        anode: wc.tn(anodes[0]),
    },
};
local noise = [static_csdb, noise_model, noise_source, frame_summer, digitizer];

local truth_ductor = {
    type: "Truth",
    data: params.sim + params.daq + params.lar {
        anode: wc.tn(anodes[0]),        
    }
};
local frame_joiner = {
    type: "FrameFanin",
    data: {
        multiplicity: 2,
        tags: ["simulation", "truth"], // needs to match order of fanin edges 
    }
};
local base_saver = {
    data: params.daq {
        filename: "uboone-wctsim-signal-noise-truth-%(digi)s.npz" % {
            digi: if params.sim.digitize then "adc" else "volts",
        },
        frame_tags: ["simulation", "truth"],       // untagged.
        scale: if params.sim.digitize then 1.0 else wc.uV,
    },
};
local depo_saver = base_saver { type: "NumpyDepoSaver" };
local frame_saver = base_saver { type: "NumpyFrameSaver" };
local frame_sink = { type: "DumpFrames" };
local endgame = [truth_ductor, frame_joiner, depo_saver, frame_saver, frame_sink];

local edges = [
    {
        tail: {node: wc.tn(depos)},
        head: {node: wc.tn(drifter)},
    },
    {
        tail: {node: wc.tn(drifter)},
        head: {node: wc.tn(depo_saver)},
    },
    {
        tail: {node: wc.tn(depo_saver)},
        head: {node: wc.tn(fanout)},
    },
    {
        tail: {node: wc.tn(fanout), port:0},
        head: {node: wc.tn(multi_ductor)},
    },
    {
        tail: {node: wc.tn(multi_ductor)},
        head: {node: wc.tn(frame_summer), port:0},
    },
    {
        tail: {node: wc.tn(noise_source)},
        head: {node: wc.tn(frame_summer), port:1},
    },
    {
        tail: {node: wc.tn(frame_summer)},
        head: {node: wc.tn(digitizer)},
    },
    {
        tail: {node: wc.tn(digitizer)},
        head: {node: wc.tn(frame_joiner), port:0},
    },
    {
        tail: {node: wc.tn(fanout), port:1},
        head: {node: wc.tn(truth_ductor)},
    },
    {
        tail: {node: wc.tn(truth_ductor)},
        head: {node: wc.tn(frame_joiner), port:1},
    },
    {
        tail: {node: wc.tn(frame_joiner)},
        head: {node: wc.tn(frame_saver)},
    },
    {
        tail: {node: wc.tn(frame_saver)},
        head: {node: wc.tn(frame_sink)},
    },
];
local app = {
    type: "Pgrapher",
    data: {
        edges: edges,
    }
};



// final configuration sequence
shared + signal + noise + endgame + [app]
