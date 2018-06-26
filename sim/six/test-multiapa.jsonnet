// WCT simulation with 6 protoDUNE-SP APAs

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

local fields = {
    type: "FieldResponse",
    data: { filename: params.files.fields }
};

local wires = {
    type: "WireSchemaFile",
    data: { filename: params.files.wires }
};


// depo source
local depos = {
    type: "TrackDepos",
    data: {
        step_size: 1.0 * wc.millimeter,
        tracks: [
            {
                time: 0.0*wc.us,
                charge: -5000, // negative means charge per step
                ray: wc.ray(wc.point(-1,2,1,wc.m), wc.point(1,4,6,wc.m))
            },
        ]
    }
};

local zeropt = {x:0.0, y:0.0, z:0.0};
local cathodedz = params.detector.extent[2];
// [front, back] cathode Z location for each APA
local cathode_pts= [
    [zeropt { z:0.5*cathodedz}, null],
    [null, zeropt { z:0.5*cathodedz}],
    [zeropt { z:1.5*cathodedz}, null],
    [null, zeropt { z:1.5*cathodedz}],
    [zeropt { z:2.5*cathodedz}, null],
    [null, zeropt { z:2.5*cathodedz}],
];    


// drifter/vagabondx.  
local drifter = {
    type: "VagabondX",
    data : params.lar + params.sim  {
        // see commentary in VagabondX.h
        xregions: [
            {
                anode: -3594.16*wc.mm + 10*wc.cm,
                cathode: 0.0,
            },
            {
                anode: +3594.16*wc.mm - 10*wc.cm,
                cathode: 0.0,
            },
        ],
    }
};


// 6 ductors/anodes
local multiplicity = std.range(0,5);

local fanout = {
    type: "DepoFanout",
    data: {
        multiplicity: 6,
    }
};


local anodes = [
    {
        type : "AnodePlane",
        name: "ductor%d" % n,
        data : params.elec + params.daq {
            ident : n,
            field_response: wc.tn(fields),
            wire_schema: wc.tn(wires),
            cathode: cathode_pts[n],
        },
    } for n in multiplicity ];

local ductors = [
    {
        type: "Ductor",
        name: "ductor%d" % n,
        data : params.daq + params.lar + params.sim {
            continuous: false,
            nsigma : 3,
	    anode: wc.tn(anodes[n]),
        },
    } for n in multiplicity ];

local digitizers = [
    {
        type: "Digitizer",
        name: "digitizer%d" % n,
        data : params.adc {
            anode: wc.tn(anodes[n]),
        },
    } for n in multiplicity ];


// 6-to-1 fanin
local fanin = {
    type: "FrameFanin",
    data: {
        multiplicity: 6,
    }
};

// numpy savers
local base_saver = {
    data: params.daq {
        filename: "protodune-wctsim-%(src)s-%(digi)s-%(noise)s.npz" % {
            src: "tracks",
            digi: if params.sim.digitize then "adc" else "volts",
            noise: if params.sim.noise then "noise" else "signal",
        },
        frame_tags: [""],       // untagged.
        scale: if params.sim.digitize then 1.0 else wc.uV,
    },
};
local depo_saver = base_saver { type: "NumpyDepoSaver" };
local frame_saver = base_saver { type: "NumpyFrameSaver" };


local frame_sink = { type: "DumpFrames" };

// edges

local initial_edges = [
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
];
local fanned_edges = [
    {
        tail: {node: wc.tn(fanout), port: n},
        head: {node: wc.tn(ductors[n])},
    } for n in multiplicity ] + [
    {
        tail: {node: wc.tn(ductors[n])},
        head: {node: wc.tn(digitizers[n])},
    } for n in multiplicity ] + [
    {
        tail: {node: wc.tn(digitizers[n])},
        head: {node: wc.tn(fanin), port: n},
    } for n in multiplicity];

local final_edges = [
    {
        tail: {node: wc.tn(fanin)},
        head: {node: wc.tn(frame_saver)},
    },
    {
        tail: {node: wc.tn(frame_saver)},
        head: {node: wc.tn(frame_sink)},
    },
];
local edges = initial_edges + fanned_edges + final_edges;

local app = {
    type: "Pgrapher",
    data: {
        edges: edges,
    }
};

// final configuration sequence
[cmdline, random, fields, wires, depos, drifter, fanout] + anodes + ductors + digitizers + [fanin, depo_saver, frame_saver, frame_sink, app]
