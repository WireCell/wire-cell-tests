local wc = import "wirecell.jsonnet";
local ar39 = import "ar39.jsonnet";
local v = import "vector.jsonnet";

{
    kine(params, tracklist, with_blips=true)::
    //
    // Define some regions and use them for regions in which to generate Ar39 events
    //
    local bigbox = {
        local half = v.scale(params.detector.extent, 0.5),
        tail: v.topoint(v.vsub(params.detector.center, half)),
        head: v.topoint(v.vadd(params.detector.center, half)),
    };
    local lilbox = {
        local half = v.frompoint(wc.point(1,1,1,0.5*wc.cm)),
        tail: v.topoint(v.vsub(params.detector.center, half)),
        head: v.topoint(v.vadd(params.detector.center, half)),
    };
    local ar39blips = { 
        type: "BlipSource",
        name: "fullrate",
        data: {
	    charge: ar39,
	    time: {
	        type: "decay",
	        start: params.daq.start_time,
                stop: params.daq.stop_time,
	        activity: params.lar.ar39activity * params.detector.drift_mass,
	    },
	    position: {
	        type:"box",
                extent: bigbox,
	    }
        }
    };
    local debugblips = { 
        type: "BlipSource",
        name: "lowrate",
        data: {
            charge: { type: "mono", value: 10000 },
	    time: {
	        type: "decay",
	        start: params.daq.start_time,
                stop: params.daq.stop_time,
                activity: 1.0/(1*wc.ms), // low rate
	    },
	    position: {
	        type:"box",
	        extent: lilbox,     // localized
	    }
        }
    };
    local blips = ar39blips;
    local tracks = {
        type: "TrackDepos",
        name: "cosmics",
        data: {
            step_size: 1.0 * wc.millimeter,
            tracks: tracklist,
        }
    };
    // Join the depos from the various kinematics.  The DepoMergers only
    // do 2-to-1 joining so have to use a few.  They don't take any real
    // configuration so just name them here to refer to them later.
    local joincb = { type: "DepoMerger", name: "CosmicBlipJoiner" };
    // local joincbb = { type: "DepoMerger", name: "CBBlipJoiner" };
    if with_blips then {
        edges: [
            {
                tail: { node: wc.tn(tracks) },
                head: { node: wc.tn(joincb), port:0 }
            },
            {
                tail: { node: wc.tn(blips) },
                head: { node: wc.tn(joincb), port:1 }
            },
        ],
        output: { node: wc.tn(joincb)},
        cfgseq: [ joincb, tracks, blips, ],
    }
    else {
        edges: [ ],
        output: { node: wc.tn(tracks)},
        cfgseq: [ tracks, ],
    },
        

    //
    // noise simulation parts
    //
    noise(params,anodes)::
    local static_csdb = {
        type: "StaticChannelStatus",
        name: "urasai",
    };

    local noise_model = {
        type: "EmpiricalNoiseModel",
        data: {
            anode: anodes.nominal,
            spectra_file: params.files.noise,
            chanstat: wc.tn(static_csdb),
            nsamples: params.daq.ticks_per_readout,
        }
    };
    local noise_source = {
        type: "NoiseSource",
        data: params.daq {
            model: wc.tn(noise_model),
	    anode: anodes.nominal,
            start_time: params.daq.start_time,
            stop_time: params.daq.stop_time,
            readout_time: params.daq.readout_time,
        }
    };

    // This is used to add noise to signal.
    local frame_summer = {
        type: "FrameSummer",
        data: {
            align: true,
            offset: 0.0*wc.s,
        }
    };

    {
        input: { node: wc.tn(frame_summer), port:0 },
        edges: [
            {
                tail: { node: wc.tn(noise_source) },
                head: { node: wc.tn(frame_summer), port:1 },
            },
        ],
        output:{ node: wc.tn(frame_summer) },
        cfgseq: [static_csdb, noise_model, noise_source, frame_summer],
    },                          // noise

    //
    //  Now, the simulation processing component nodes
    //
    signal(params, anodes)::
    local drifter = {
        type : "Drifter",
        data : params.lar + params.sim  {
            anode: anodes.nominal,
        }
    };
    // One ductor for each universe, all identical except for name and the
    // coresponding anode.
    local ductor_nominal = {
        type : 'Ductor',
        name : 'nominal',
        data : params.daq + params.lar + params.sim {
            continuous: false,
            nsigma : 3,
	    anode: anodes.nominal,
        }
    };
    local ductor_uvground = ductor_nominal {
        name : 'uvground',
        data : super.data {
            anode: anodes.uvground,
        }
    };
    local ductor_vyground = ductor_nominal {
        name : 'vyground',
        data : super.data {
            anode: anodes.vyground,
        }
    };

    // The guts of this chain can be generated with:
    // $ wirecell-util convert-uboone-wire-regions \
    //                 microboone-celltree-wires-v2.1.json.bz2 \
    //                 MicroBooNE_ShortedWireList_v2.csv \
    //                 foo.json
    //
    // Copy-paste the plane:0 and plane:2 in uv_ground and vy_ground, respectively
    local uboone_ductor_chain = [
        {
            ductor: wc.tn(ductor_uvground),
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
            ductor: wc.tn(ductor_vyground),
            rule: "wirebounds",
            args: [
                [ { plane:2, min:2336, max:2399 } ],
                [ { plane:2, min:2401, max:2414 } ],
                [ { plane:2, min:2416, max:2463 } ],
            ],
        },
        {               // catch all if the above do not match.
            ductor: wc.tn(ductor_nominal),
            rule: "bool",
            args: true,
        },

    ];

    // note, this rule chain is nonphysical and over-simplified to make
    // debugging easier.  A track from Z=0 to Z=3mm*500 will pass through:
    // N|UV|N|VY|N field response functions where N=nominal
    local test_ductor_chain = [
        {
            ductor: wc.tn(ductor_uvground),
            rule: "wirebounds",
            args: [ 
                [
                    { plane: 2, min:100, max:200 },
                ],
            ],
        },

        {
            ductor: wc.tn(ductor_vyground),
            rule: "wirebounds",
            args: [
                [
                    { plane: 2, min:300, max:400 },
                ],
            ],
        },

        {               // catch all if the above do not match.
            ductor: wc.tn(ductor_nominal),
            rule: "bool",
            args: true,
        },
    ];


    // One multiductor to rull them all.
    local multi_ductor = {
        type: "MultiDuctor",
        data : {
            anode: anodes.nominal,
            continuous: false,
            chains : [
                //test_ductor_chain,
                uboone_ductor_chain,
            ],
        }
    };


    {
        input: { node: wc.tn(drifter) },
        edges: [
            {
                tail: { node: wc.tn(drifter) },
                head: { node: wc.tn(multi_ductor) },
            },
        ],
        output: { node:wc.tn(multi_ductor) },
        cfgseq: [drifter, ductor_nominal, ductor_vyground, ductor_uvground, multi_ductor],
    },                          // signal

    // last bits
    sink(params, anodes)::
    // used for both noise-only, signal-only or both, so just define it
    // here instead of making a whole new file....
    local digitizer = {
        type: "Digitizer",
        data : params.adc {
            anode: anodes.nominal,
        }
    };

    // cap off the end of the graph
    local frame_sink = { type: "DumpFrames" };


    // here we do not return input/edges/output/cfgseq because user
    // likely wants to put a saver just before the sink.
    {
        digitizer: digitizer,
        sink: frame_sink,
    },
}


