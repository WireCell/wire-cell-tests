local wc = import "wirecell.jsonnet";
local ar39 = import "ar39.jsonnet";
local v = import "vector.jsonnet";
local g = import "pgraph.jsonnet";

function(params, tools, tracklist)
{
    //
    // Define some regions and use them for regions in which to generate Ar39 events
    //
    local bigbox = {
        local half = v.scale(params.detector.extent, 0.5),
        tail: v.topoint(v.vsub(params.detector.center, half)),
        head: v.topoint(v.vadd(params.detector.center, half)),
    },
    local lilbox = {
        local half = v.frompoint(wc.point(1,1,1,0.5*wc.cm)),
        tail: v.topoint(v.vsub(params.detector.center, half)),
        head: v.topoint(v.vadd(params.detector.center, half)),
    },
    ar39blips: g.pnode({ 
        type: "BlipSource",
        name: "fullrate",
        data: {
            rng: wc.tn(tools.random),
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
    }, nin=0, nout=1, uses=[tools.random]),

    tracks: g.pnode({
        type: "TrackDepos",
        name: "cosmics",
        data: {
            step_size: 1.0 * wc.millimeter,
            tracks: tracklist,
        }
    }, nin=0, nout=1),

    blipjoiner: g.pnode({
        type: "DepoMerger",
        name: "BlibTrackJoiner",
    }, nin=2, nout=1),

    tracks_and_blips: g.intern(outnodes=[self.blipjoiner],
                               centernodes=[self.ar39blips, self.tracks],
                               iports=[],
                               edges=[
                                   g.edge(self.ar39blips, self.blipjoiner, 0, 0),
                                   g.edge(self.tracks, self.blipjoiner, 0, 1),
                               ]),
    
    local static_csdb = {
        type: "StaticChannelStatus",
        name: "urasai",
    },

    local noise_model = {
        type: "EmpiricalNoiseModel",
        data: {
            anode: wc.tn(tools.anode),
            spectra_file: params.files.noise,
            chanstat: wc.tn(static_csdb),
            nsamples: params.daq.ticks_per_readout,
        },
        uses: [tools.anode, static_csdb],
    },
    noise: g.pnode({
        type: "NoiseSource",
        data: params.daq {
            rng: wc.tn(tools.random),
            model: wc.tn(noise_model),
	    anode: wc.tn(tools.anode),
            start_time: params.daq.start_time,
            stop_time: params.daq.stop_time,
            readout_time: params.daq.readout_time,
        }}, nin=0, nout=1, uses=[tools.anode, noise_model]),


    // This is used to add noise to signal.
    noise_summer: g.pnode({
        type: "FrameSummer",
        data: {
            align: true,
            offset: 0.0*wc.s,
        }
    }, nin=2, nout=1),

    // A "frame filter" that adds in noise
    plus_noise: g.intern([self.noise_summer],[self.noise_summer],[self.noise],
                         edges = [
                             g.edge(self.noise, self.noise_summer, 0, 1),
                         ]),


    // Now the "signal" parts.

    drifter: g.pnode({
        type: "Drifter",
        data: params.lar + params.sim {
            rng: wc.tn(tools.random),
            xregions: [ {
                anode: params.sim.response_plane,
                cathode: params.sim.cathode_plane,
            } ],
        },
    },nin=1,nout=1, uses=[tools.random]),

    // One ductor per set of field response functions, three pirs per set.
    ductors: std.mapWithIndex(function (n, pirs) g.pnode({
        type: 'Ductor',
        name: 'ductor%d' % n,
        data: params.daq + params.lar + params.sim {
            rng: wc.tn(tools.random),
            anode: wc.tn(tools.anode),
            pirs: std.map(function(pir) wc.tn(pir), pirs),
        },
    }, nin=1,nout=1,uses=[tools.random, tools.anode] + pirs), tools.pirs),


    // The guts of this chain can be generated with:
    // $ wirecell-util convert-uboone-wire-regions \
    //                 microboone-celltree-wires-v2.1.json.bz2 \
    //                 MicroBooNE_ShortedWireList_v2.csv \
    //                 foo.json
    //
    // Copy-paste the plane:0 and plane:2 in uv_ground and vy_ground, respectively
    local uboone_ductor_chain = [
        {
            ductor: $.ductors[1].name,
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
            ductor: $.ductors[2].name,
            rule: "wirebounds",
            args: [
                [ { plane:2, min:2336, max:2399 } ],
                [ { plane:2, min:2401, max:2414 } ],
                [ { plane:2, min:2416, max:2463 } ],
            ],
        },
        {               // catch all if the above do not match.
            ductor: $.ductors[0].name,
            rule: "bool",
            args: true,
        },

    ],

    // One multiductor to rull them all.
    multi_ductor: g.pnode({
        type: "MultiDuctor",
        data : {
            anode: wc.tn(tools.anode),
            continuous: false,
            chains : [
                //test_ductor_chain,
                uboone_ductor_chain,
            ],
        }
    }, nin=1, nout=1, uses = $.ductors),

    // used for both noise-only, signal-only or both, so just define it
    // here instead of making a whole new file....
    digitizer: g.pnode({
        type: "Digitizer",
        data : params.adc {
            anode: wc.tn(tools.anode),
        }
    }, nin=1, nout=1, uses=[tools.anode]),

    // cap off the end of the graph
    frame_sink: g.pnode({ type: "DumpFrames" }, nin=1, nout=0),


    // drifter + ductor + digitizer = signal
    // signal: g.intern([self.drifter],[self.multi_ductor],
    //                  edges=[
    //                      g.edge(self.drifter, self.multi_ductor),
    //                  ]),


}


