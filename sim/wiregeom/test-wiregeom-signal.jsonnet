local wc = import "wirecell.jsonnet";

// user picks based on "tracklist" external
local tracklist = std.extVar("tracklist");
local output = std.extVar("output");

local uboone_params = import "uboone_params.jsonnet";
local params = uboone_params {
    sim: super.sim {
        fluctuate: false,
    }
};
local basics = import "basics.jsonnet";
local ionodes = import "ionodes.jsonnet";
local sim = import "simnodes.jsonnet";
local tracklists = import "tracklists.jsonnet";

local utils = basics.utils();
local anodes = basics.anodes(params);
local savers = ionodes.numpy(params, output);
local kine = sim.kine(params, tracklists[tracklist], false);
local signal = sim.signal(params,anodes);
local sink = sim.sink(params,anodes);


local edges = kine.edges + [
    {
        tail: kine.output,
        head: {node: wc.tn(savers.depo)},
    },
    {
        tail: {node: wc.tn(savers.depo)},
        head: signal.input,
    }
] +signal.edges + [
    {
        tail: signal.output,
        head: {node: wc.tn(sink.digitizer)},
    },
    {
        tail: { node: wc.tn(sink.digitizer) },
        head: { node: wc.tn(savers.frame) },
    },
    {                   // terminate the stream
        tail: { node: wc.tn(savers.frame) },
        head: { node: wc.tn(sink.sink) },
    },
];


// Here the nodes are joined into a graph for execution by the main
// app object.  
local app = {
    type: "Pgrapher",
    data: {
        edges: edges,
    }
};
local extra = [savers.depo, savers.frame, sink.digitizer, sink.sink, app];

utils.cfgseq + anodes.cfgseq + kine.cfgseq + signal.cfgseq + extra

